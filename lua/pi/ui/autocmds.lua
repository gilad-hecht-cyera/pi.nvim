local input_window = require('pi.ui.input_window')
local output_window = require('pi.ui.output_window')
local M = {}

---Reflowed tables are laid out for a specific window width, so a width change
---requires re-rendering from cache. Debounced to avoid thrashing during drags.
local reflow_tables_on_width_change = require('pi.util').debounce(function()
  local config = require('pi.config')
  local tables = config.ui.output.rendering.tables
  if not tables or tables.reflow == false or tables.max_width then
    return
  end
  if not output_window.mounted() then
    return
  end
  require('pi.ui.ui').render_output_from_cache()
end, 120)

---@param windows PiWindowState?
---@return boolean changed
local function output_width_changed(windows)
  local win = windows and windows.output_win
  if not win or not vim.api.nvim_win_is_valid(win) then
    return false
  end

  local width = vim.api.nvim_win_get_width(win)
  if M._last_output_width == width then
    return false
  end
  M._last_output_width = width
  return true
end

function M.setup_autocmds(windows)
  local group = vim.api.nvim_create_augroup('PiWindows', { clear = true })
  input_window.setup_autocmds(windows, group)
  output_window.setup_autocmds(windows, group)

  -- Only keep shared autocmds here (e.g., WinClosed, WinLeave for all windows)
  local wins = { windows.input_win, windows.output_win, windows.footer_win }
  vim.api.nvim_create_autocmd('WinClosed', {
    group = group,
    pattern = table.concat(wins, ','),
    callback = function(opts)
      -- Don't close everything if we're just toggling the input window
      if input_window._toggling then
        return
      end

      local closed_win = tonumber(opts.match)
      if vim.tbl_contains(wins, closed_win) then
        vim.schedule(function()
          require('pi.ui.ui').teardown_visible_windows(windows)
        end)
      end
    end,
  })

  vim.api.nvim_create_autocmd({ 'BufWinEnter', 'BufFilePost', 'WinLeave' }, {
    group = group,
    pattern = '*',
    callback = function(args)
      if args.file == '' then
        return
      end
      local state = require('pi.state')
      state.ui.set_code_context(vim.api.nvim_get_current_win(), vim.api.nvim_get_current_buf())
    end,
  })

  vim.api.nvim_create_autocmd({ 'BufWritePost', 'BufFilePost', 'BufDelete', 'BufWipeout', 'FileChangedShellPost' }, {
    group = group,
    pattern = '*',
    callback = function(args)
      if args.file == '' or vim.bo[args.buf].buftype ~= '' then
        return
      end
      require('pi.ui.renderer.events').invalidate_reference_targets_for_file_change()
    end,
  })

  vim.api.nvim_create_autocmd('WinEnter', {
    group = group,
    pattern = '*',
    callback = function()
      require('pi.state').ui.set_panel_focused(require('pi.ui.ui').is_pi_focused())
    end,
  })

  vim.api.nvim_create_autocmd('DirChanged', {
    pattern = { 'global', 'tabpage' },
    group = group,
    callback = function(event)
      local state = require('pi.state')
      if state.current_cwd == event.file then
        return
      end

      if event.match == 'tabpage' then
        local windows = state.windows
        if not windows or not windows.output_win or not vim.api.nvim_win_is_valid(windows.output_win) then
          return
        end

        local ok, pi_tab = pcall(vim.api.nvim_win_get_tabpage, windows.output_win)
        if not ok then
          return
        end

        local changed_tab = vim.api.nvim_get_current_tabpage()
        local changed_window = event.data and event.data.changed_window
        if changed_window and vim.api.nvim_win_is_valid(changed_window) then
          local win_ok, win_tab = pcall(vim.api.nvim_win_get_tabpage, changed_window)
          if win_ok then
            changed_tab = win_tab
          end
        end

        if changed_tab ~= pi_tab then
          return
        end
      end

      state.context.set_current_cwd(event.file)
      require('pi.services.session_runtime').handle_directory_change()
    end,
  })

  if require('pi.config').ui.position == 'current' then
    vim.api.nvim_create_autocmd('BufEnter', {
      group = group,
      callback = function()
        local current_win = vim.api.nvim_get_current_win()
        local current_buf = vim.api.nvim_get_current_buf()

        if current_win ~= windows.output_win and current_win ~= windows.input_win then
          return
        end

        local is_pi_buf = (
          current_buf == windows.output_buf
          or current_buf == windows.input_buf
          or (windows.footer_buf and current_buf == windows.footer_buf)
        )

        if not is_pi_buf then
          vim.schedule(function()
            require('pi.ui.ui').teardown_visible_windows(windows)
          end)
        end
      end,
    })
  end
end

---@param windows PiWindowState?
function M.setup_resize_handler(windows)
  local resize_group = vim.api.nvim_create_augroup('PiResize', { clear = true })
  vim.api.nvim_create_autocmd('VimResized', {
    group = resize_group,
    callback = function()
      require('pi.ui.topbar').render()
      require('pi.ui.footer').update_window(windows)
      input_window.update_dimensions(windows)
      output_window.update_dimensions(windows)
      if output_width_changed(windows) then
        reflow_tables_on_width_change()
      end
    end,
  })
  vim.api.nvim_create_autocmd('WinResized', {
    group = resize_group,
    callback = function(args)
      local win = tonumber(args.match) --[[@as integer]]
      if not win or not vim.api.nvim_win_is_valid(win) or not output_window.mounted() then
        return
      end

      local floating = vim.api.nvim_win_get_config(win).relative ~= ''
      if floating then
        return
      end

      require('pi.ui.topbar').render()
      require('pi.ui.footer').update_window(windows)
      if output_width_changed(windows) then
        reflow_tables_on_width_change()
      end
    end,
  })
end

return M
