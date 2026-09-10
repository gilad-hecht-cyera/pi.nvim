---@class PiStateStore
local M = {}

---@class PiStateData
---@field windows PiWindowState|nil
---@field is_opening boolean
---@field input_content table
---@field is_pi_focused boolean
---@field last_focused_pi_window string|nil
---@field last_input_window_position integer[]|nil
---@field last_output_window_position integer[]|nil
---@field last_code_win_before_pi integer|nil
---@field current_code_buf number|nil
---@field current_code_view table|nil
---@field saved_window_options table|nil
---@field display_route string|nil
---@field current_mode string|nil
---@field last_output number
---@field last_sent_context PiContext|nil
---@field current_context_config PiContextConfig|nil
---@field context_updated_at number|nil
---@field active_session Session|nil
---@field restore_points RestorePoint[]
---@field current_model string|nil
---@field user_mode_model_map table<string, string>
---@field current_model_info table|nil
---@field current_variant string|nil
---@field extension_statuses table<string, string>
---@field messages PiMessage[]|nil
---@field current_message PiMessage|nil
---@field pending_permissions PiPermission[]
---@field cost number
---@field tokens_count number
---@field session_stats table|nil
---@field job_count number
---@field user_message_count table<string, number>
---@field pi_server PiServer|nil
---@field api_client PiApiClient|nil
---@field event_manager EventManager|nil
---@field pre_zoom_width integer|nil
---@field last_window_width_ratio number|nil
---@field required_version string
---@field pi_cli_version Promise<string>|nil
---@field current_cwd string|nil
---@field session_locked boolean|nil
---@field _hidden_buffers PiHiddenBuffers|nil

---@type PiStateData
local _state = {
  windows = nil,
  is_opening = false,
  input_content = {},
  is_pi_focused = false,
  last_focused_pi_window = nil,
  last_input_window_position = nil,
  last_output_window_position = nil,
  last_code_win_before_pi = nil,
  current_code_buf = nil,
  saved_window_options = nil,
  display_route = nil,
  current_mode = nil,
  last_output = 0,
  pre_zoom_width = nil,
  last_window_width_ratio = nil,
  last_sent_context = nil,
  current_context_config = nil,
  context_updated_at = nil,
  active_session = nil,
  restore_points = {},
  current_model = nil,
  user_mode_model_map = {},
  current_model_info = nil,
  current_variant = nil,
  extension_statuses = {},
  messages = nil,
  current_message = nil,
  pending_permissions = {},
  cost = 0,
  tokens_count = 0,
  session_stats = nil,
  job_count = 0,
  user_message_count = {},
  queued_user_messages = {},
  pi_server = nil,
  api_client = nil,
  event_manager = nil,
  required_version = '0.6.3',
  pi_cli_version = nil,
  current_cwd = vim.fn.getcwd(),
  session_locked = nil,
  _hidden_buffers = nil,
}

local _listeners = {}
local _batch_depth = 0
local _batched_changes = {}
local _batched_order = {}

---@generic K extends keyof PiStateData
---@param key K
---@param new_val std.RawGet<PiStateData, K>
---@param old_val std.RawGet<PiStateData, K>
local function queue_emit(key, new_val, old_val)
  if vim.deep_equal(old_val, new_val) then
    return false
  end

  if _batch_depth == 0 then
    M.emit(key, new_val, old_val)
    return true
  end

  if not _batched_changes[key] then
    _batched_changes[key] = {
      old_val = old_val,
      new_val = new_val,
    }
    table.insert(_batched_order, key)
    return true
  end

  _batched_changes[key].new_val = new_val
  return true
end

local function flush_batched_emits()
  if _batch_depth > 0 or #_batched_order == 0 then
    return
  end

  local pending_changes = _batched_changes
  local pending_order = _batched_order
  _batched_changes = {}
  _batched_order = {}

  for _, key in ipairs(pending_order) do
    local change = pending_changes[key]
    if change then
      M.emit(key, change.new_val, change.old_val)
    end
  end
end

function M.state()
  return _state
end

---@generic K extends keyof PiStateData
---@param key K
---@return std.RawGet<PiStateData, K>
function M.get(key)
  return _state[key]
end

---@generic K extends keyof PiStateData
---@param key K
---@param value std.RawGet<PiStateData, K>
---@return std.RawGet<PiStateData, K>
function M.set(key, value)
  local old = _state[key]

  _state[key] = value
  queue_emit(key, value, old)

  return value
end

---@generic K extends keyof PiStateData
---@param key K
---@param value std.RawGet<PiStateData, K>
---@return std.RawGet<PiStateData, K>
function M.set_raw(key, value)
  _state[key] = value
  return value
end

---@generic K extends keyof PiStateData
---@param key K
---@param updater fun(current: std.RawGet<PiStateData, K>): std.RawGet<PiStateData, K>
---@return std.RawGet<PiStateData, K>
function M.update(key, updater)
  local next_value = updater(_state[key])
  M.set(key, next_value)
  return next_value
end

---@param callback fun(store: PiStateStore)
function M.batch(callback)
  _batch_depth = _batch_depth + 1
  local ok, result = pcall(callback, M)
  _batch_depth = _batch_depth - 1

  if _batch_depth == 0 then
    flush_batched_emits()
  end

  if not ok then
    error(result, 0)
  end

  return result
end

---@generic K extends keyof PiStateData
---@param key K
---@param mutator fun(current: std.RawGet<PiStateData, K>):nil
---@return std.RawGet<PiStateData, K>
function M.mutate(key, mutator)
  if _state[key] == nil then
    _state[key] = {} --[[@as std.RawGet<PiStateData, K>]]
  end

  if type(_state[key]) ~= 'table' then
    error('State key is not a table: ' .. key)
  end

  local current = _state[key]
  local old = vim.tbl_extend('force', {}, current)
  mutator(current)
  queue_emit(key, current, old)
  return current
end

---@generic K extends keyof PiStateData
---@param key K|K[]|nil
---@param cb fun(key:K, new_val:std.RawGet<PiStateData, K>, old_val:std.RawGet<PiStateData, K>)
function M.subscribe(key, cb)
  if type(key) == 'table' then
    for _, current_key in ipairs(key) do
      M.subscribe(current_key, cb)
    end
    return
  end

  key = key or '*'
  if not _listeners[key] then
    _listeners[key] = {}
  end

  for _, fn in ipairs(_listeners[key]) do
    if fn == cb then
      return
    end
  end

  table.insert(_listeners[key], cb)
end

---@generic K extends keyof PiStateData
---@param key K|nil
---@param cb fun(key:K, new_val:std.RawGet<PiStateData, K>, old_val:std.RawGet<PiStateData, K>)
function M.unsubscribe(key, cb)
  key = key or '*'
  local list = _listeners[key]
  if not list then
    return
  end

  for i = #list, 1, -1 do
    if list[i] == cb then
      table.remove(list, i)
    end
  end
end

---@generic K extends keyof PiStateData
---@param key K
---@param new_val std.RawGet<PiStateData, K>
---@param old_val std.RawGet<PiStateData, K>
function M.emit(key, new_val, old_val)
  vim.schedule(function()
    if _listeners[key] then
      for _, cb in ipairs(_listeners[key]) do
        local ok, err = pcall(cb, key, new_val, old_val)
        if not ok then
          vim.notify(err --[[@as string]])
        end
      end
    end

    if _listeners['*'] then
      for _, cb in ipairs(_listeners['*']) do
        pcall(cb, key, new_val, old_val)
      end
    end
  end)
end

---@generic K extends keyof PiStateData
---@param key K
---@param value std.RawGet<PiStateData, K> extends any[] and std.RawGet<PiStateData, K>[integer] or never
function M.append(key, value)
  if type(value) ~= 'table' then
    error('Value must be a table to append')
  end

  M.mutate(key, function(current)
    table.insert(current --[[@as table]], value)
  end)
end

---@generic K extends keyof PiStateData
---@param key K
---@param idx integer
function M.remove(key, idx)
  if not _state[key] then
    return
  end

  M.mutate(key, function(current)
    table.remove(current --[[@as table]], idx)
  end)
end

return M
