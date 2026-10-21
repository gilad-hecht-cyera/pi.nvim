local state = require('pi.state')
local tab_runtimes = require('pi.tab_runtimes')
local event_adapter = require('pi.event_adapter')
local Promise = require('pi.promise')

---@class PiTabSnapshot
---@field scope table Saved tab-scoped state values
---@field output_view table|nil

local M = {}

---@type table<integer, PiTabSnapshot>
local snapshots = {}
---@type table<integer, fun()>
local settle_watchers = {}

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

  return true
end

---Open a new tab with a fresh session and switch to it.
---@param opts? PiTabRuntimeOpts
---@return Promise<PiTabRuntime>
function M.new(opts)
  local runtime = tab_runtimes.create(opts)
  M.switch(runtime.id)
  local session_runtime = require('pi.services.session_runtime')
  return session_runtime.create_new_session():and_then(function(session)
    if session and tab_runtimes.is_active(runtime.id) then
      state.session.set_active(session)
    end
    return runtime
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
  snapshots[id] = nil
  tab_runtimes.close(id)

  if replacement then
    event_adapter.reset_live()
    state.tab_scope.swap(nil)
    return M.new():and_then(function()
      return true
    end)
  end
  return Promise.new():resolve(true)
end

function M._reset()
  for id in pairs(settle_watchers) do
    stop_settle_watch(id)
  end
  snapshots = {}
end

return M
