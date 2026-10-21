local state = require('pi.state')
local tab_runtimes = require('pi.tab_runtimes')
local event_adapter = require('pi.event_adapter')
local Promise = require('pi.promise')

---@class PiTabSnapshot
---@field scope table Saved tab-scoped state values
---@field output_view table|nil

---@class PiTabView
---@field id integer
---@field index integer
---@field title string
---@field running boolean
---@field active boolean

local M = {}

local NEW_SESSION_TITLE = 'New session'

---@type table<integer, PiTabSnapshot>
local snapshots = {}
---@type table<integer, fun()>
local settle_watchers = {}
---@type table<integer, fun()>
local status_watchers = {}

local function output_win()
  local win = state.windows and state.windows.output_win
  if win and vim.api.nvim_win_is_valid(win) then
    return win
  end
end

local function capture_output_view()
  local win = output_win()
  if not win then
    return nil
  end
  local ok, view = pcall(vim.api.nvim_win_call, win, vim.fn.winsaveview)
  return ok and view or nil
end

local function restore_output_view(view)
  local win = output_win()
  if win and view then
    pcall(vim.api.nvim_win_call, win, function()
      vim.fn.winrestview(view)
    end)
  end
end

local function sync_input_buffer()
  local input_window = require('pi.ui.input_window')
  if state.windows and state.windows.input_buf then
    input_window.set_content(state.input_content or { '' })
  end
end

local function stop_settle_watch(id)
  if settle_watchers[id] then
    settle_watchers[id]()
    settle_watchers[id] = nil
  end
end

---A tab switched into mid-run only shows the replayed in-progress message.
---Re-render once it settles so tool results and status are exact again.
local function resync_when_settled(runtime)
  stop_settle_watch(runtime.id)
  settle_watchers[runtime.id] = runtime.process:on_event(function(event)
    if event.type ~= 'agent_settled' then
      return
    end
    stop_settle_watch(runtime.id)
    if tab_runtimes.is_active(runtime.id) then
      require('pi.ui.renderer').render_full_session()
    end
  end)
end

local function replay_stream(runtime)
  for _, event in ipairs(runtime.rpc_client.stream_events or {}) do
    event_adapter.handle_event(event)
  end
end

---@return PiTabRuntime[]
function M.list()
  return tab_runtimes.list()
end

local function session_of(id)
  if tab_runtimes.is_active(id) then
    return state.active_session
  end
  local snapshot = snapshots[id]
  return snapshot and snapshot.scope and snapshot.scope.active_session
end

local function session_title(session)
  local title = session and session.title
  if type(title) ~= 'string' or title == '' then
    return NEW_SESSION_TITLE
  end
  return title
end

local function rename_background_session(id, name)
  local session = session_of(id)
  if tab_runtimes.is_active(id) or not session or not name or name == '' then
    return
  end
  session.title = name
  session.description = name
end

local function track(runtime)
  if status_watchers[runtime.id] then
    return
  end
  status_watchers[runtime.id] = runtime.process:on_event(function(event)
    if event.type == 'session_info_changed' then
      rename_background_session(runtime.id, event.name)
      M.publish()
    elseif event.type == 'agent_start' or event.type == 'agent_settled' or event.type == 'process_exit' then
      M.publish()
    end
  end)
end

local function untrack(id)
  if status_watchers[id] then
    status_watchers[id]()
    status_watchers[id] = nil
  end
end

---@return PiTabView[]
function M.list_view()
  local views = {}
  for index, runtime in ipairs(tab_runtimes.list()) do
    track(runtime)
    table.insert(views, {
      id = runtime.id,
      index = index,
      title = session_title(session_of(runtime.id)),
      running = runtime.rpc_client.streaming == true,
      active = tab_runtimes.is_active(runtime.id),
    })
  end
  return views
end

function M.publish()
  state.ui.set_tabs(M.list_view())
end

---Find the tab that has `session_id` open.
---@param session_id string|nil
---@return integer|nil tab_id
function M.find_by_session(session_id)
  if not session_id then
    return nil
  end
  for _, runtime in ipairs(tab_runtimes.list()) do
    local session = session_of(runtime.id)
    if session and session.id == session_id then
      return runtime.id
    end
  end
end

---@return integer|nil
function M.active_id()
  return tab_runtimes.active_id()
end

---Make `id` the active tab: its process backs `rpc_client.get()`, its state is loaded into the store,
---and its session is re-rendered from Pi.
---@param id integer
---@return boolean switched
function M.switch(id)
  local current_id = tab_runtimes.active_id()
  if id == current_id then
    return true
  end
  local target = tab_runtimes.get(id)
  if not target then
    return false
  end

  local view = capture_output_view()
  local incoming = snapshots[id] or {}
  snapshots[id] = nil

  tab_runtimes.set_active(id)
  event_adapter.reset_live()
  local outgoing = state.tab_scope.swap(incoming.scope)
  if current_id and tab_runtimes.get(current_id) then
    snapshots[current_id] = { scope = outgoing, output_view = view }
    stop_settle_watch(current_id)
  end

  sync_input_buffer()

  local session = state.active_session
  if session and session.id then
    require('pi.ui.renderer').after_session_render(session.id, function()
      if not tab_runtimes.is_active(id) then
        return
      end
      restore_output_view(incoming.output_view)
      replay_stream(target)
    end)
  end

  if target.rpc_client.streaming then
    resync_when_settled(target)
  end

  M.publish()
  return true
end

---@param delta integer 1 for next, -1 for previous; wraps around
---@return boolean switched
function M.cycle(delta)
  local list = tab_runtimes.list()
  if #list < 2 then
    return false
  end
  for i, runtime in ipairs(list) do
    if tab_runtimes.is_active(runtime.id) then
      return M.switch(list[((i - 1 + delta) % #list) + 1].id)
    end
  end
  return false
end

---@param index integer 1-based position in the tab bar
---@return boolean switched
function M.go_to(index)
  local runtime = tab_runtimes.list()[index]
  return runtime ~= nil and M.switch(runtime.id)
end

---@param runtime_opts? PiTabRuntimeOpts
---@param load_session fun(): Promise<Session|nil>
---@return Promise<PiTabRuntime>
local function open_tab(runtime_opts, load_session)
  local runtime = tab_runtimes.create(runtime_opts)
  track(runtime)
  M.switch(runtime.id)
  return load_session():and_then(function(session)
    if session and tab_runtimes.is_active(runtime.id) then
      state.session.set_active(session)
    end
    M.publish()
    return runtime
  end)
end

---Open a new tab with a fresh session and switch to it.
---@param opts? PiTabRuntimeOpts
---@return Promise<PiTabRuntime>
function M.new(opts)
  return open_tab(opts, function()
    return require('pi.services.session_runtime').create_new_session()
  end)
end

---Open a new tab holding a fork of the active tab's session at its current position.
---The fork happens in the new tab's process (`pi --fork`), so the source tab keeps running.
---@return Promise<PiTabRuntime>
function M.fork_current()
  return tab_runtimes.active().rpc_client:get_state():and_then(function(pi_state)
    local path = pi_state and pi_state.sessionFile
    if not path or not vim.uv.fs_stat(path) then
      return Promise.new():reject('Nothing to fork yet: the current session has no saved messages')
    end
    return open_tab({ extra_args = { '--fork', path } }, function()
      return require('pi.rpc_client').get():get_state():and_then(function(forked)
        return require('pi.session').get_by_id(forked.sessionFile)
      end)
    end)
  end)
end

local function neighbor_of(id)
  local list = tab_runtimes.list()
  for i, runtime in ipairs(list) do
    if runtime.id == id then
      local neighbor = list[i + 1] or list[i - 1]
      return neighbor and neighbor.id or nil
    end
  end
end

---Close a tab, stopping its process. Closing the active tab switches to a neighbor;
---closing the last tab replaces it with a new empty one.
---@param id integer
---@return Promise<boolean>
function M.close(id)
  if not tab_runtimes.get(id) then
    return Promise.new():resolve(false)
  end

  local replacement = nil
  if tab_runtimes.is_active(id) then
    local neighbor = neighbor_of(id)
    if neighbor then
      M.switch(neighbor)
    else
      replacement = true
    end
  end

  stop_settle_watch(id)
  untrack(id)
  snapshots[id] = nil
  tab_runtimes.close(id)

  if replacement then
    event_adapter.reset_live()
    state.tab_scope.swap(nil)
    return M.new():and_then(function()
      return true
    end)
  end
  M.publish()
  return Promise.new():resolve(true)
end

---@return Promise<boolean>
function M.close_active()
  local id = tab_runtimes.active_id()
  if not id then
    return Promise.new():resolve(false)
  end
  return M.close(id)
end

function M._reset()
  for id in pairs(settle_watchers) do
    stop_settle_watch(id)
  end
  for id in pairs(status_watchers) do
    untrack(id)
  end
  snapshots = {}
end

return M
