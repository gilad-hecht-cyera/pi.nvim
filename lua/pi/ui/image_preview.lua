local M = {}

local preview = nil

function M.close()
  if preview and preview.placement then
    pcall(preview.placement.close, preview.placement)
  end
  if preview and preview.win and vim.api.nvim_win_is_valid(preview.win) then
    pcall(vim.api.nvim_win_close, preview.win, true)
  end
  if preview and preview.buf and vim.api.nvim_buf_is_valid(preview.buf) then
    pcall(vim.api.nvim_buf_delete, preview.buf, { force = true })
  end
  preview = nil
end

function M.show(path, target_win)
  M.close()

  local config = require('pi.config')
  local state = require('pi.state')
  local opts = config.ui.input.image_preview
  local windows = state.windows
  target_win = target_win or (windows and windows.input_win)
  if not opts.enabled or not target_win or not vim.api.nvim_win_is_valid(target_win) then
    return false
  end

  local ok, Snacks = pcall(require, 'snacks')
  if not ok or not Snacks.image or not Snacks.image.buf then
    return false
  end

  local target_row, target_col = unpack(vim.api.nvim_win_get_position(target_win))
  local target_width = vim.api.nvim_win_get_width(target_win)
  local width = math.min(opts.width, target_width)
  local height = math.min(opts.height, math.max(1, vim.o.lines - 4))
  local cursor = vim.api.nvim_win_get_cursor(target_win)
  local screen_position = vim.fn.screenpos(target_win, cursor[1], cursor[2] + 1)
  local cursor_row = screen_position.row > 0 and screen_position.row - 1 or target_row
  local row = cursor_row + 1
  if row + height + 2 > vim.o.lines then
    row = cursor_row - height - 2
  end
  row = math.max(0, math.min(row, vim.o.lines - height - 2))
  local col = math.max(0, target_col + target_width - width)

  local buf = vim.api.nvim_create_buf(false, true)
  local win = vim.api.nvim_open_win(buf, false, {
    relative = 'editor',
    width = width,
    height = height,
    row = row,
    col = col,
    border = opts.border,
    focusable = false,
    style = 'minimal',
    zindex = 60,
  })

  preview = { buf = buf, win = win, path = path }
  local placement = Snacks.image.buf.attach(buf, {
    src = path,
    max_width = width,
    max_height = height,
  })
  preview.placement = placement
  return true
end

function M.toggle(path, target_win)
  if preview and preview.path == path then
    M.close()
    return false
  end
  return M.show(path, target_win)
end

return M
