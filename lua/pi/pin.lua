local Promise = require('pi.promise')

local M = {}

local function close_non_pi_windows(windows)
  if not windows then
    return
  end

  local keep = {}
  for _, win in ipairs({ windows.input_win, windows.output_win, windows.footer_win }) do
    if win then
      keep[win] = true
    end
  end

  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if not keep[win] and vim.api.nvim_win_is_valid(win) then
      pcall(vim.api.nvim_win_close, win, true)
    end
  end
end

M.open = Promise.async(function()
  local config = require('pi.config')
  local state = require('pi.state')
  local session_runtime = require('pi.services.session_runtime')
  local ui = require('pi.ui.ui')

  config.values.ui.position = 'current'

  session_runtime
    .open({
      new_session = false,
      focus = 'input',
      start_insert = true,
      open_action = 'create_fresh',
    })
    :await()

  close_non_pi_windows(state.windows)
  ui.focus_input({ restore_position = true, start_insert = true })
end)

return M
