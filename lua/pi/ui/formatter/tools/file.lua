local util = require('pi.util')
local icons = require('pi.ui.icons')
local utils = require('pi.ui.formatter.utils')

local M = {}

---@param file_path string
---@return string
local function resolve_file_name(file_path)
  if not file_path or file_path == '' then
    return ''
  end

  local cwd = vim.fn.getcwd()
  local absolute = vim.fn.fnamemodify(file_path, ':p')
  if vim.startswith(absolute, cwd .. '/') then
    return absolute:sub(#cwd + 2)
  end
  return absolute
end

---@param file_path string
---@param tool_output? string
---@return boolean
local function is_directory_path(file_path, tool_output)
  if not file_path or file_path == '' then
    return false
  end

  if vim.endswith(file_path, '/') then
    return true
  end

  return type(tool_output) == 'string' and tool_output:match('<type>directory</type>') ~= nil
end

---@param file_path string
---@param tool_output? string
---@return string
local function resolve_display_file_name(file_path, tool_output)
  local resolved = resolve_file_name(file_path)

  if resolved ~= '' and is_directory_path(file_path, tool_output) and not vim.endswith(resolved, '/') then
    resolved = resolved .. '/'
  end

  return resolved
end

local function input_file_path(input)
  return input.filePath or input.path or ''
end

---@param text string
---@return string[]
local function read_output_lines(text)
  text = text or ''
  text = text:gsub('^<file>\n?', ''):gsub('\n?</file>$', '')
  text = text:gsub('\n%(%s*End of file[^\n]*%)$', '')

  local lines = vim.split(text, '\n')
  for i, line in ipairs(lines) do
    lines[i] = line:gsub('^%d+| ?', '')
  end
  return lines
end

---@param output Output
---@param edits table[]
---@param file_type string
local function format_edit_blocks(output, edits, file_type)
  for index, edit in ipairs(edits or {}) do
    if #edits > 1 then
      output:add_empty_line()
      output:add_line('**Edit ' .. index .. '**')
    end

    if edit.oldText then
      output:add_empty_line()
      output:add_line('*Old*')
      utils.format_code(output, vim.split(edit.oldText, '\n'), file_type)
    end
    if edit.newText then
      output:add_empty_line()
      output:add_line('*New*')
      utils.format_code(output, vim.split(edit.newText, '\n'), file_type)
    end
  end
end

---@param output Output
---@param part PiMessagePart
function M.format(output, part)
  local input = part.state and part.state.input or {}
  local metadata = part.state and part.state.metadata or {}
  local tool_output = part.state and part.state.output or ''
  local tool_type = part.tool
  local file_path = input_file_path(input)

  local file_name = tool_type == 'read' and resolve_display_file_name(file_path, tool_output)
    or resolve_file_name(file_path)

  local file_type = file_path ~= '' and util.get_markdown_filetype(file_path) or ''

  local config = require('pi.config')

  local icon_text = icons.get(tool_type)
  utils.format_action(output, icon_text, tool_type, file_name, utils.get_duration_text(part))

  if file_name ~= '' and file_path ~= '' then
    local action_line = output:get_line_count()
    local line_content = output:get_line(action_line)
    output:add_target({
      kind = 'file',
      path = file_path,
      range = {
        line = action_line,
        start_col = 0,
        end_col = line_content and #line_content or 0,
      },
    })
  end

  local start_line = output:get_line_count() + 1
  if not (config.ui.output.tools.show_output or config.ui.output.tools.use_folds) then
    return
  end

  if tool_type == 'read' and tool_output and tool_output ~= '' then
    utils.format_code(output, read_output_lines(tool_output), file_type)
  elseif tool_type == 'edit' and metadata.diff then
    utils.format_diff(output, metadata.diff, file_type, file_path)
  elseif tool_type == 'edit' and input.edits then
    format_edit_blocks(output, input.edits, file_type)
  elseif tool_type == 'edit' and (input.oldText or input.newText) then
    format_edit_blocks(output, { input }, file_type)
  elseif tool_type == 'write' and input.content then
    utils.format_code(output, vim.split(input.content, '\n'), file_type)
  elseif tool_output and tool_output ~= '' then
    utils.format_code(output, vim.split(tool_output, '\n'), '')
  end

  output:add_fold_with_threshold(start_line, config.ui.output.tools.show_output, config.ui.output.tools.use_folds)
end

---@param part PiMessagePart
---@param input FileToolInput
---@return string, string, string
function M.summary(part, input)
  local tool = part.tool
  local file_path = input_file_path(input or {})
  if tool == 'read' then
    local tool_output = part.state and part.state.output or nil
    return icons.get('read'), 'read', resolve_display_file_name(file_path, tool_output)
  end
  return icons.get(tool), tool, resolve_file_name(file_path)
end

return M
