local state = require('pi.state')
local tab_runtimes = require('pi.tab_runtimes')
local event_adapter = require('pi.event_adapter')
local Promise = require('pi.promise')

---@class PiTabSnapshot
---@field scope table Saved tab-scoped state values
---@field output_view table|nil

---@alias PiTabStatus 'idle'|'running'|'waiting'|'done'

---@class PiTabView
---@field id integer
---@field index integer
---@field title string
---@field status PiTabStatus
---@field active boolean

local M = {}

local NEW_SESSION_TITLE = 'New session'

---@type table<integer, PiTabSnapshot>
local snapshots = {}
---@type table<integer, fun()>
local settle_watchers = {}
---@type table<integer, fun()>
local status_watchers = {}
---Dialog requests (`extension_ui_request`) a background tab is blocked on, shown when it becomes active.
---@type table<integer, table[]>
local pending_dialogs = {}
---Background tabs that finished a run the user has not looked at yet.
---@type table<integer, boolean>
local unseen_done = {}
---@type table<integer, boolean>
local ran = {}

local DIALOG_METHODS = { select = true, confirm = true, input = true, editor = true }

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

local function tab_label(id)
  for index, runtime in ipairs(tab_runtimes.list()) do
    if runtime.id == id then
      return string.format('Pi tab %d "%s"', index, session_title(session_of(id)))
    end
  end
  return 'Pi tab'
end

local function notify_background(id, message, level)
  if require('pi.config').ui.tabs.notify ~= false then
    vim.notify(tab_label(id) .. ' ' .. message, level or vim.log.levels.INFO)
  end
end

local function set_background_status(id, key, value)
  local snapshot = snapshots[id]
  if not snapshot or not key or key == '' then
    return
  end
  snapshot.scope = snapshot.scope or {}
  local statuses = vim.deepcopy(snapshot.scope.extension_statuses or {})
  statuses[key] = (value ~= nil and value ~= '') and value or nil
  snapshot.scope.extension_statuses = statuses
end

---Background tabs do not render, so their extension UI requests are handled here instead.
local function on_background_ui_request(id, event)
  if DIALOG_METHODS[event.method] then
    pending_dialogs[id] = pending_dialogs[id] or {}
    table.insert(pending_dialogs[id], event)
    notify_background(id, 'needs input', vim.log.levels.WARN)
  elseif event.method == 'notify' then
    notify_background(id, event.message or '', vim.log.levels.INFO)
  elseif event.method == 'setStatus' then
    set_background_status(id, event.statusKey, event.statusText)
  end
end

local function on_runtime_event(runtime, event)
  local id = runtime.id
  local background = not tab_runtimes.is_active(id)
  if event.type == 'session_info_changed' then
    rename_background_session(id, event.name)
  elseif event.type == 'extension_ui_request' then
    if not background then
      return
    end
    on_background_ui_request(id, event)
  elseif event.type == 'agent_start' then
    ran[id] = true
    unseen_done[id] = nil
  elseif event.type == 'agent_settled' or event.type == 'process_exit' then
    pending_dialogs[id] = nil
    if background and ran[id] and event.type == 'agent_settled' then
      unseen_done[id] = true
      notify_background(id, 'finished')
    end
    ran[id] = nil
  else
    return
  end
  M.publish()
end

local function track(runtime)
  if status_watchers[runtime.id] then
    return
  end
  status_watchers[runtime.id] = runtime.process:on_event(function(event)
    on_runtime_event(runtime, event)
  end)
end

local function untrack(id)
  if status_watchers[id] then
    status_watchers[id]()
    status_watchers[id] = nil
  end
  pending_dialogs[id] = nil
  unseen_done[id] = nil
  ran[id] = nil
end

local function show_pending_dialogs(runtime)
  local dialogs = pending_dialogs[runtime.id]
  pending_dialogs[runtime.id] = nil
  for _, event in ipairs(dialogs or {}) do
    runtime.rpc_client:replay_ui_request(event)
  end
end

---@param runtime PiTabRuntime
---@return PiTabStatus
local function status_of(runtime)
  if pending_dialogs[runtime.id] and #pending_dialogs[runtime.id] > 0 then
    return 'waiting'
  elseif runtime.rpc_client.streaming then
    return 'running'
  elseif unseen_done[runtime.id] then
    return 'done'
  end
  return 'idle'
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
      status = status_of(runtime),
      active = tab_runtimes.is_active(runtime.id),
    })
  end
  return views
end

local restoring = false
local restored = false
local last_saved = nil

local function session_file(session)
  local path = session and (session.sessionFile or session.path or session.id)
  if type(path) == 'string' and vim.uv.fs_stat(path) then
    return path
  end
end

---Persist the open tabs for the current working directory. Tabs whose session has not been
---written to disk yet are skipped, since there is nothing to reopen. Nothing is saved before
---`restore` had its chance, so an early save cannot overwrite the tabs about to be restored.
function M.save()
  if restoring or not restored or not require('pi.config').ui.tabs.persist then
    return
  end
  local sessions = {}
  local active = 1
  for _, runtime in ipairs(tab_runtimes.list()) do
    local path = session_file(session_of(runtime.id))
    if path then
      table.insert(sessions, path)
      if tab_runtimes.is_active(runtime.id) then
        active = #sessions
      end
    end
  end
  local saved = #sessions > 0 and { sessions = sessions, active = active } or nil
  local cwd = vim.fn.getcwd()
  local encoded = cwd .. vim.json.encode(saved or vim.NIL)
  if encoded == last_saved then
    return
  end
  last_saved = encoded
  require('pi.tab_persistence').write(cwd, saved)
end

function M.publish()
  state.ui.set_tabs(M.list_view())
  M.save()
end

---Recreate the tabs saved for the current working directory. Background tabs get a runtime
---started with `--session <file>`, whose process only spawns when the tab is first used.
---The saved active tab reuses the existing first runtime; its session file is returned so the
---caller can load it the usual way. Runs once, and only before any extra tab exists.
---@return string|nil active_session_file
function M.restore()
  if restored then
    return nil
  end
  restored = true
  if not require('pi.config').ui.tabs.persist then
    return nil
  end
  if #tab_runtimes.list() > 1 then
    return nil
  end

  local saved = require('pi.tab_persistence').read(vim.fn.getcwd())
  if not saved then
    return nil
  end
  local sessions = {}
  local active_path = saved.sessions[saved.active]
  for _, path in ipairs(saved.sessions) do
    if type(path) == 'string' and vim.uv.fs_stat(path) and not vim.tbl_contains(sessions, path) then
      table.insert(sessions, path)
    end
  end
  if #sessions == 0 then
    return nil
  end
  if not vim.tbl_contains(sessions, active_path) then
    active_path = sessions[1]
  end

  restoring = true
  local first = tab_runtimes.active()
  local ids = {}
  for _, path in ipairs(sessions) do
    if path == active_path then
      table.insert(ids, first.id)
    else
      local runtime = tab_runtimes.create({ extra_args = { '--session', path } })
      track(runtime)
      local scope = state.tab_scope.defaults()
      scope.active_session = require('pi.pi_sessions').get_by_path(path)
      snapshots[runtime.id] = { scope = scope }
      table.insert(ids, runtime.id)
    end
  end
  tab_runtimes.set_order(ids)
  restoring = false
  return active_path
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

  unseen_done[id] = nil
  if pending_dialogs[id] then
    vim.schedule(function()
      if tab_runtimes.is_active(id) then
        show_pending_dialogs(target)
        M.publish()
      end
    end)
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
  restored = true
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

---@class PiForkIntoTabOpts
---@field source_path? string Session file to fork; defaults to the active tab's session
---@field entry_id? string Fork from this earlier user entry instead of the current position

local function source_session_file(opts)
  if opts.source_path then
    return Promise.new():resolve(opts.source_path)
  end
  return tab_runtimes.active().rpc_client:get_state():and_then(function(pi_state)
    return pi_state and pi_state.sessionFile
  end)
end

---The new tab's process starts from `pi --fork <source>`, a full copy. An entry fork then
---branches that copy in-process, and the copy is deleted because nothing else uses it.
---@return Promise<{ path: string, text: string|nil }>
local function fork_in_new_process(entry_id)
  local rpc = require('pi.rpc_client').get()
  return rpc:get_state():and_then(function(copy)
    if not entry_id then
      return { path = copy.sessionFile }
    end
    return rpc
      :fork(entry_id)
      :and_then(function(response)
        if response and response.cancelled then
          return { path = copy.sessionFile }
        end
        return rpc:get_state():and_then(function(forked)
          if forked.sessionFile and forked.sessionFile ~= copy.sessionFile then
            os.remove(copy.sessionFile)
          end
          return { path = forked.sessionFile, text = response and response.text }
        end)
      end)
      :catch(function(err)
        vim.notify(
          '[pi.nvim] Fork from message failed, the new tab forks at the current position: ' .. tostring(err),
          vim.log.levels.WARN
        )
        return { path = copy.sessionFile }
      end)
  end)
end

---Open a new tab holding a fork of a session. The fork happens in the new tab's process,
---so the source tab keeps running untouched.
---@param opts? PiForkIntoTabOpts
---@return Promise<PiTabRuntime>
function M.fork_into_tab(opts)
  opts = opts or {}
  local source_title = session_title(state.active_session)
  return source_session_file(opts):and_then(function(path)
    if not path or not vim.uv.fs_stat(path) then
      return Promise.new():reject('Nothing to fork yet: the session has no saved messages')
    end
    if opts.source_path then
      local source = require('pi.pi_sessions').get_by_path(path)
      source_title = source and source.title
    end
    local name = require('pi.api_client').next_fork_title(source_title)
    local prompt_text
    return open_tab({ extra_args = { '--fork', path } }, function()
      return fork_in_new_process(opts.entry_id):and_then(function(result)
        prompt_text = result.text
        local rpc = require('pi.rpc_client').get()
        return rpc
          :set_session_name(name)
          :catch(function() end)
          :and_then(function()
            return require('pi.session').get_by_id(result.path)
          end)
      end)
    end):and_then(function(runtime)
      if prompt_text and prompt_text ~= '' and tab_runtimes.is_active(runtime.id) then
        state.ui.set_input_content(vim.split(prompt_text, '\n'))
        sync_input_buffer()
      end
      return runtime
    end)
  end)
end

---Fork the active tab's session at its current position into a new tab.
---@return Promise<PiTabRuntime>
function M.fork_current()
  return M.fork_into_tab()
end

local FORK_CHOICES = { 'New tab', 'Replace current session' }

---Run `handlers.tab` or `handlers.current` according to `ui.tabs.fork_target`, asking when it is `ask`.
---`handlers.cancel` runs when the question is dismissed.
---@param handlers { tab: fun(), current: fun(), cancel?: fun() }
function M.choose_fork_target(handlers)
  local target = require('pi.config').ui.tabs.fork_target
  if target == 'tab' then
    return handlers.tab()
  elseif target == 'current' then
    return handlers.current()
  end
  vim.ui.select(FORK_CHOICES, { prompt = 'Fork into:' }, function(choice)
    if choice == FORK_CHOICES[1] then
      handlers.tab()
    elseif choice == FORK_CHOICES[2] then
      handlers.current()
    elseif handlers.cancel then
      handlers.cancel()
    end
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
  restoring = false
  restored = false
  last_saved = nil
end

return M
