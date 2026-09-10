local state = require('pi.state')

local M = {}

local buffer
local window
local subscribed = false

local function active_queue()
  local session_id = state.active_session and state.active_session.id
  if not session_id then
    return {}
  end
  return (state.queued_user_messages or {})[session_id] or {}
end

local function close_window()
  if window and vim.api.nvim_win_is_valid(window) then
    pcall(vim.api.nvim_win_close, window, true)
  end
  window = nil
end

local function fit(text, width)
  if vim.fn.strdisplaywidth(text) <= width then
    return text
  end
  local suffix = '…'
  local target = math.max(0, width - vim.fn.strdisplaywidth(suffix))
  local result = text
  while result ~= '' and vim.fn.strdisplaywidth(result) > target do
    result = vim.fn.strcharpart(result, 0, vim.fn.strchars(result) - 1)
  end
  return result .. suffix
end

local function display_lines(queue, width)
  local lines = { string.format('Queued (%d)', #queue) }
  local visible = math.min(#queue, 3)
  for index = 1, visible do
    local prompt = tostring(queue[index].prompt or ''):gsub('%s+', ' ')
    lines[#lines + 1] = fit(string.format('%d  %s', index, prompt), width)
  end
  if #queue > visible then
    lines[#lines + 1] = string.format('…  %d more', #queue - visible)
  end
  return lines
end

local function desired_width(queue, available)
  local width = vim.fn.strdisplaywidth(string.format('Queued (%d)', #queue))
  for index = 1, math.min(#queue, 3) do
    local prompt = tostring(queue[index].prompt or ''):gsub('%s+', ' ')
    width = math.max(width, vim.fn.strdisplaywidth(string.format('%d  %s', index, prompt)))
  end
  if #queue > 3 then
    width = math.max(width, vim.fn.strdisplaywidth(string.format('…  %d more', #queue - 3)))
  end
  return math.min(60, available, math.max(12, width))
end

local function window_config(input_win, width, height)
  local input_width = vim.api.nvim_win_get_width(input_win)
  return {
    relative = 'win',
    win = input_win,
    anchor = 'SW',
    width = width,
    height = height,
    row = 0,
    col = math.max(0, input_width - width - 2),
    focusable = false,
    style = 'minimal',
    border = 'rounded',
    zindex = 60,
  }
end

function M.render(windows)
  windows = windows or state.windows
  local queue = active_queue()
  if #queue == 0 or not windows or not windows.input_win or not vim.api.nvim_win_is_valid(windows.input_win) then
    close_window()
    return
  end

  local input_width = vim.api.nvim_win_get_width(windows.input_win)
  if input_width < 8 then
    close_window()
    return
  end

  local width = desired_width(queue, input_width - 2)
  local lines = display_lines(queue, width)

  if not buffer or not vim.api.nvim_buf_is_valid(buffer) then
    buffer = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_option_value('buftype', 'nofile', { buf = buffer })
    vim.api.nvim_set_option_value('bufhidden', 'hide', { buf = buffer })
    vim.api.nvim_set_option_value('swapfile', false, { buf = buffer })
  end

  vim.api.nvim_set_option_value('modifiable', true, { buf = buffer })
  vim.api.nvim_buf_set_lines(buffer, 0, -1, false, lines)
  vim.api.nvim_set_option_value('modifiable', false, { buf = buffer })

  local win_config = window_config(windows.input_win, width, #lines)
  if window and vim.api.nvim_win_is_valid(window) then
    pcall(vim.api.nvim_win_set_config, window, win_config)
  else
    window = vim.api.nvim_open_win(buffer, false, win_config)
    vim.api.nvim_set_option_value('winhl', 'Normal:PiHint,FloatBorder:PiBorder', { win = window })
    vim.api.nvim_set_option_value('wrap', false, { win = window })
  end
end

local function on_change()
  M.render()
end

function M.setup(windows)
  if not subscribed then
    state.store.subscribe('queued_user_messages', on_change)
    state.store.subscribe('active_session', on_change)
    subscribed = true
  end
  M.render(windows)
end

function M.close()
  close_window()
end

function M.teardown()
  close_window()
  if buffer and vim.api.nvim_buf_is_valid(buffer) then
    pcall(vim.api.nvim_buf_delete, buffer, { force = true })
  end
  buffer = nil
  if subscribed then
    state.store.unsubscribe('queued_user_messages', on_change)
    state.store.unsubscribe('active_session', on_change)
    subscribed = false
  end
end

M._display_lines = display_lines
M._window_config = window_config
M._window = function()
  return window
end

return M
