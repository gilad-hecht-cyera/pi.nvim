--- Image pasting functionality from clipboard
--- @see https://github.com/sst/pi/blob/45180104fe84e2d0b9d29be0f9f8a5e52d18e102/packages/pi/src/cli/cmd/tui/util/clipboard.ts
local context = require('pi.context')
local state = require('pi.state')

local M = {}
local cached_temp_dir = nil

--- Check if a file exists and has content
--- @param path string
--- @return boolean
local function is_valid_file(path)
  return vim.fn.getfsize(path) > 0
end

--- Run shell or powershell command and return success
--- @param cmd string|table
--- @param opts table?
--- @return boolean
local function run_shell_cmd(cmd, opts)
  local sys_cmd
  if type(cmd) == 'string' then
    sys_cmd = { 'sh', '-c', cmd }
  else
    sys_cmd = cmd
  end
  return vim.system(sys_cmd, opts):wait().code == 0
end

--- Save base64 data to file
--- @param data string
--- @param path string
--- @return boolean
local function save_base64(data, path)
  if vim.fn.has('win32') == 1 then
    local script =
      string.format('[System.IO.File]::WriteAllBytes("%s", [System.Convert]::FromBase64String("%s"))', path, data)
    return run_shell_cmd({ 'powershell.exe', '-command', '-' }, { stdin = script })
  else
    local decode_arg = vim.uv.os_uname().sysname == 'Darwin' and '-D' or '-d'
    return run_shell_cmd(string.format('base64 %s > "%s"', decode_arg, path), { stdin = data })
  end
end

--- macOS clipboard image handler using osascript
--- @param path string
--- @return boolean
local function handle_darwin_clipboard(path)
  if vim.fn.executable('osascript') ~= 1 then
    return false
  end
  local cmd = string.format(
    "osascript -e 'set imageData to the clipboard as \"PNGf\"' -e 'set fileRef to open for access POSIX file \"%s\" with write permission' -e 'set eof fileRef to 0' -e 'write imageData to fileRef' -e 'close access fileRef'",
    path
  )
  return run_shell_cmd(cmd)
end

--- Linux clipboard image handler supporting Wayland and X11
--- @param path string
--- @return boolean
local function handle_linux_clipboard(path)
  if vim.fn.executable('wl-paste') == 1 and run_shell_cmd(string.format('wl-paste -t image/png > "%s"', path)) then
    return true
  end
  return vim.fn.executable('xclip') == 1
    and run_shell_cmd(string.format('xclip -selection clipboard -t image/png -o > "%s"', path))
end

--- Windows clipboard image handler using PowerShell
--- @param path string
--- @return boolean
local function handle_windows_clipboard(path)
  if vim.fn.executable('powershell.exe') ~= 1 then
    return false
  end
  local win_path = path
  if vim.fn.exists('$WSL_DISTRO_NAME') == 1 then
    local res = vim.system({ 'wslpath', '-w', path }):wait()
    if res.code == 0 then
      win_path = res.stdout:gsub('%s+$', '')
    end
  end

  local script = string.format(
    [[
      $img = Get-Clipboard -Format Image;
      if ($img) {
        $img.Save('%s', [System.Drawing.Imaging.ImageFormat]::Png);
      } else {
        exit 1
      }
    ]],
    win_path
  )
  return run_shell_cmd({ 'powershell.exe', '-STA', '-command', '-' }, { stdin = script })
end

local handlers = {
  Darwin = handle_darwin_clipboard,
  Linux = handle_linux_clipboard,
  Windows_NT = handle_windows_clipboard,
}

--- Try to get image from system clipboard
--- @param image_path string
--- @return boolean
local function try_system_clipboard(image_path)
  local os_name = vim.uv.os_uname().sysname
  local handler = handlers[os_name]

  -- WSL detection and override
  if vim.fn.exists('$WSL_DISTRO_NAME') == 1 then
    handler = handlers.Windows_NT
  end

  return handler and handler(image_path) and is_valid_file(image_path) or false
end

--- Try to parse base64 image data from clipboard
--- @param temp_dir string
--- @param timestamp string
--- @return boolean, string?
local function try_base64_clipboard(temp_dir, timestamp)
  local content = vim.fn.getreg('+')
  if not content or content == '' then
    return false
  end

  local format, data = content:match('^data:image/([^;]+);base64,(.+)$')
  if not format or not data then
    return false
  end

  local image_path = string.format('%s/pasted_image_%s.%s', temp_dir, timestamp, format)
  local success = save_base64(data, image_path) and is_valid_file(image_path)

  return success, success and image_path or nil
end

--- Restore full path of a pasted image by its name
--- @param name string
--- @return string?
function M.restore_img_path(name)
  if not cached_temp_dir or not name:find('^pasted_image_') then
    return nil
  end
  local path = cached_temp_dir .. '/' .. name
  return is_valid_file(path) and path or nil
end

--- Handle clipboard image data by saving it to a file and adding it to context
--- @return boolean success True if image was successfully handled
function M.paste_image_from_clipboard(notify_on_failure)
  if not cached_temp_dir then
    cached_temp_dir = vim.fn.tempname()
    vim.fn.mkdir(cached_temp_dir, 'p')
  end
  local temp_dir = cached_temp_dir
  local timestamp = os.date('%Y%m%d_%H%M%S')
  local image_path = string.format('%s/pasted_image_%s.png', temp_dir, timestamp)

  local success = try_system_clipboard(image_path)

  if not success then
    local base64_success, base64_path = try_base64_clipboard(temp_dir, timestamp --[[@as string]])
    success = base64_success
    if base64_path then
      image_path = base64_path
    end
  end

  if success then
    require('pi.ui.mention').mention(function(mention_cb)
      local name = vim.fn.fnamemodify(image_path, ':t')
      mention_cb(name)
      context.add_file(image_path)
    end)

    require('pi.ui.image_preview').show(image_path)
    vim.notify('Image saved and added to context: ' .. vim.fn.fnamemodify(image_path, ':t'), vim.log.levels.INFO)
    return true
  end

  if notify_on_failure ~= false then
    vim.notify('No image found in clipboard.', vim.log.levels.WARN)
  end
  return false
end

function M.preview_image_at_cursor()
  local line = vim.api.nvim_get_current_line()
  local cursor_col = vim.api.nvim_win_get_cursor(0)[2] + 1
  local search_from = 1
  local matches = {}

  while true do
    local mention_start, mention_end, name = line:find('(pasted_image_[%w_.%-]+)', search_from)
    if not mention_start then
      break
    end
    local match = { start_col = mention_start, end_col = mention_end, name = name }
    table.insert(matches, match)
    if cursor_col >= mention_start and cursor_col <= mention_end then
      matches = { match }
      break
    end
    search_from = mention_end + 1
  end

  if #matches == 1 then
    local path = M.restore_img_path(matches[1].name)
    if not path then
      vim.notify('Pasted image is no longer available.', vim.log.levels.WARN)
      return false
    end
    return require('pi.ui.image_preview').toggle(path, vim.api.nvim_get_current_win())
  end

  vim.notify('Cursor is not on a pasted image.', vim.log.levels.WARN)
  return false
end

function M.paste(fallback)
  if vim.bo.filetype == 'pi' and M.paste_image_from_clipboard(false) then
    return true
  end

  if fallback == 'p' or fallback == 'P' then
    vim.api.nvim_feedkeys(fallback, 'n', false)
    return false
  end

  local content = vim.fn.getreg('+')
  if type(content) == 'table' then
    content = table.concat(content, '\n')
  end
  if not content or content == '' then
    vim.notify('Nothing in clipboard.', vim.log.levels.WARN)
    return false
  end

  vim.api.nvim_paste(content, true, -1)
  return false
end

return M
