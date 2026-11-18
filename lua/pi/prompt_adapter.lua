local M = {}

local function read_json(text)
  local ok, value = pcall(vim.json.decode, text or '')
  if ok and type(value) == 'table' then
    return value
  end
end

local function file_path_from_part(part)
  if part.source and part.source.path then
    return part.source.path
  end
  if part.url and part.url:match('^file://') then
    return part.url:gsub('^file://', '')
  end
  return part.filename
end

local function format_text_context(part)
  local metadata = part.metadata or {}
  local context_type = metadata.context_type

  if context_type == 'selection' then
    local data = read_json(part.text)
    if not data then
      return part.text
    end
    local file = data.file or {}
    local path = file.path or file.name or 'unknown file'
    local lines = data.lines and (' lines ' .. data.lines) or ''
    return string.format('Selected text from %s%s:\n%s', path, lines, data.content or '')
  end

  if context_type == 'diagnostics' then
    local data = read_json(part.text)
    if not data or type(data.content) ~= 'table' or #data.content == 0 then
      return nil
    end
    local lines = { 'Diagnostics:' }
    for _, diag in ipairs(data.content) do
      table.insert(lines, string.format('- %s %s', diag.pos or '', diag.msg or ''))
    end
    return table.concat(lines, '\n')
  end

  if context_type == 'cursor-data' then
    local data = read_json(part.text)
    if not data then
      return part.text
    end
    return string.format(
      'Cursor context at line %s, column %s:\n%s',
      tostring(data.line or '?'),
      tostring(data.column or '?'),
      data.line_content or ''
    )
  end

  if context_type == 'file-content' then
    local filename = metadata.filename or 'buffer'
    return string.format('Open buffer %s:\n```\n%s\n```', filename, part.text or '')
  end

  if context_type == 'git-diff' then
    return 'Current git diff:\n```diff\n' .. (part.text or '') .. '\n```'
  end

  return part.text
end

function M.parts_to_prompt(parts)
  local prompt = nil
  local context_blocks = {}
  local referenced_files = {}

  for _, part in ipairs(parts or {}) do
    if part.type == 'file' then
      local path = file_path_from_part(part)
      if path and path ~= '' then
        table.insert(referenced_files, path)
      end
    elseif part.type == 'text' then
      if part.synthetic or part.metadata then
        local text = format_text_context(part)
        if text and text ~= '' then
          table.insert(context_blocks, text)
        end
      elseif part.text and part.text ~= '' then
        prompt = part.text
      end
    elseif part.type == 'agent' and part.name then
      table.insert(context_blocks, 'Requested skill/agent context: ' .. tostring(part.name))
    end
  end

  if #referenced_files > 0 then
    local lines = { 'Referenced files:' }
    for _, path in ipairs(referenced_files) do
      table.insert(lines, '- ' .. path)
    end
    table.insert(context_blocks, 1, table.concat(lines, '\n'))
  end

  if #context_blocks == 0 then
    return prompt or ''
  end

  return table.concat({
    '<context>',
    table.concat(context_blocks, '\n\n'),
    '</context>',
    '',
    prompt or '',
  }, '\n')
end

---@class PiPromptContextItem
---@field kind 'file'|'image'|'selection'|'cursor'|'diagnostics'|'buffer'|'git_diff'|'agent'
---@field path? string
---@field start_line? integer
---@field end_line? integer
---@field line? integer
---@field column? integer
---@field count? integer
---@field name? string

local image_extensions = { png = true, jpg = true, jpeg = true, gif = true, webp = true, bmp = true }

local function referenced_file_item(path)
  local extension = (path:match('%.([%w]+)$') or ''):lower()
  return { kind = image_extensions[extension] and 'image' or 'file', path = path }
end

local function fence_opener(line)
  return line:match('^%s*(```+)')
end

local function closes_fence(line, opener)
  local ticks = line:match('^%s*(```+)%s*$')
  return ticks ~= nil and #ticks >= #opener
end

---@param line string
---@return PiPromptContextItem|nil item
---@return 'files'|'diagnostics'|nil list_mode
local function parse_header(line)
  if line == 'Referenced files:' then
    return nil, 'files'
  end
  if line == 'Diagnostics:' then
    return { kind = 'diagnostics', count = 0 }, 'diagnostics'
  end
  if line == 'Current git diff:' then
    return { kind = 'git_diff' }
  end

  local path, start_line, end_line = line:match('^Selected text from (.-) lines (%d+), (%d+):$')
  if path then
    return { kind = 'selection', path = path, start_line = tonumber(start_line), end_line = tonumber(end_line) }
  end
  path = line:match('^Selected text from (.-):$')
  if path then
    return { kind = 'selection', path = path }
  end

  local cursor_line, cursor_column = line:match('^Cursor context at line (%S+), column (%S+):$')
  if cursor_line then
    return { kind = 'cursor', line = tonumber(cursor_line), column = tonumber(cursor_column) }
  end

  local buffer_name = line:match('^Open buffer (.-):$')
  if buffer_name then
    return { kind = 'buffer', name = buffer_name }
  end

  local agent_name = line:match('^Requested skill/agent context: (.+)$')
  if agent_name then
    return { kind = 'agent', name = agent_name }
  end
end

---Split a prompt built by `parts_to_prompt` back into the user's text and a
---summary of the context block that was prepended to it.
---@param text string|nil
---@return string|nil prompt
---@return PiPromptContextItem[]|nil items nil when the text has no context block
function M.split_prompt(text)
  if type(text) ~= 'string' or not vim.startswith(text, '<context>\n') then
    return text, nil
  end

  local lines = vim.split(text, '\n', { plain = true })
  local items = {}
  local list_mode = nil
  local diagnostics = nil
  local fence = nil
  local close_index = nil

  for i = 2, #lines do
    local line = lines[i]
    if fence then
      if closes_fence(line, fence) then
        fence = nil
      end
    elseif line == '</context>' then
      close_index = i
      break
    elseif fence_opener(line) then
      fence = fence_opener(line)
      list_mode = nil
    elseif line == '' then
      list_mode = nil
    elseif list_mode and vim.startswith(line, '- ') then
      if list_mode == 'files' then
        table.insert(items, referenced_file_item(line:sub(3)))
      elseif diagnostics then
        diagnostics.count = diagnostics.count + 1
      end
    else
      local item, mode = parse_header(line)
      list_mode = mode
      diagnostics = mode == 'diagnostics' and item or nil
      if item then
        table.insert(items, item)
      end
    end
  end

  if not close_index then
    return text, nil
  end

  local prompt_start = close_index + 1
  if lines[prompt_start] == '' then
    prompt_start = prompt_start + 1
  end

  return table.concat(lines, '\n', prompt_start), items
end

return M
