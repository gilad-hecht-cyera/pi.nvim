---Reflow GFM markdown tables so every cell wraps inside its own column instead
---of producing a single very long line that soft-wraps into an unreadable blob.
---
---The module works on raw markdown text and returns the rewritten text plus a
---list of byte-offset segments describing where the original text ended up.
---Callers that track offsets (reference/mention ranges) use `map_ranges` to
---translate their offsets into the reflowed text.
local config = require('pi.config')

local M = {}

local MIN_TOTAL_WIDTH = 24
local SHRINK_ITERATION_CAP = 10000
local ELLIPSIS = '…'
local RULE = '─'
local BR_PATTERN = '<[bB][rR]%s*/?>'
local BOX = {
  top = { '┌', '┬', '┐', '─' },
  head = { '╞', '╪', '╡', '═' },
  rule = { '├', '┼', '┤', '─' },
  bottom = { '└', '┴', '┘', '─' },
}

---@class PiTableSegment
---@field orig integer 1-based byte offset in the original text
---@field new integer 1-based byte offset in the reflowed text
---@field len integer byte length of the mapped chunk

---@class PiTableHighlight
---@field line integer 1-based line in the reflowed text
---@field start_col integer 0-based byte column
---@field end_col integer 0-based exclusive byte column
---@field hl_group string

local function tables_config()
  local rendering = config.ui and config.ui.output and config.ui.output.rendering
  return (rendering and rendering.tables) or {}
end

local function display_width(text)
  if vim.fn and vim.fn.strdisplaywidth then
    return vim.fn.strdisplaywidth(text)
  end
  return #text
end

local function utf8_chars(text)
  local chars = {}
  for char in text:gmatch('[%z\1-\127\194-\244][\128-\191]*') do
    chars[#chars + 1] = char
  end
  return chars
end

---Like `utf8_chars` but keeps backslash escapes (e.g. `\|`) as one unit so
---splitting never leaves a dangling backslash.
local function split_units(text)
  local units = {}
  local chars = utf8_chars(text)
  local index = 1
  while index <= #chars do
    if chars[index] == '\\' and chars[index + 1] then
      units[#units + 1] = chars[index] .. chars[index + 1]
      index = index + 2
    else
      units[#units + 1] = chars[index]
      index = index + 1
    end
  end
  return units
end

---Width available for a rendered table, in cells.
---@return integer
function M.available_width()
  local settings = tables_config()
  if type(settings.max_width) == 'number' and settings.max_width > 0 then
    return math.max(MIN_TOTAL_WIDTH, math.floor(settings.max_width))
  end

  local state = require('pi.state')
  local win = state.windows and state.windows.output_win
  if win and vim.api.nvim_win_is_valid(win) then
    local width = vim.api.nvim_win_get_width(win)
    local textoff = 0
    local ok, info = pcall(vim.fn.getwininfo, win)
    if ok and info and info[1] and info[1].textoff then
      textoff = info[1].textoff
    end
    return math.max(MIN_TOTAL_WIDTH, width - textoff - 1)
  end

  local width = config.ui and config.ui.window_width or 80
  if width > 0 and width <= 1 then
    width = math.floor((vim.o.columns or 120) * width)
  end
  return math.max(MIN_TOTAL_WIDTH, math.floor(width) - 4)
end

---@param line string
---@param from integer
---@param to integer
---@param line_offset integer
local function make_cell(line, from, to, line_offset)
  local raw = line:sub(from, to)
  local lead = #(raw:match('^%s*') or '')
  local text = raw:match('^%s*(.-)%s*$') or ''
  return { text = text, offset = line_offset + from - 1 + lead }
end

---Split a table row into trimmed cells, ignoring pipes inside inline code and
---escaped pipes.
---@param line string
---@param line_offset integer 1-based byte offset of the line inside the full text
---@return {text: string, offset: integer}[]
local function split_cells(line, line_offset)
  local i = #(line:match('^%s*') or '') + 1
  if line:sub(i, i) == '|' then
    i = i + 1
  end

  local cells = {}
  local cell_start = i
  local fence_len = 0

  while i <= #line do
    local char = line:sub(i, i)
    if char == '\\' then
      i = i + 2
    elseif char == '`' then
      local run = line:match('^`+', i)
      if fence_len == 0 then
        fence_len = #run
      elseif #run == fence_len then
        fence_len = 0
      end
      i = i + #run
    elseif char == '|' and fence_len == 0 then
      cells[#cells + 1] = make_cell(line, cell_start, i - 1, line_offset)
      i = i + 1
      cell_start = i
    else
      i = i + 1
    end
  end

  if line:sub(cell_start):match('%S') then
    cells[#cells + 1] = make_cell(line, cell_start, #line, line_offset)
  end

  return cells
end

---@param cells {text: string}[]
local function delimiter_alignments(cells)
  if #cells == 0 then
    return nil
  end

  local alignments = {}
  for _, cell in ipairs(cells) do
    local left, dashes, right = cell.text:match('^(:?)(%-+)(:?)$')
    if not dashes then
      return nil
    end
    if left == ':' and right == ':' then
      alignments[#alignments + 1] = 'center'
    elseif right == ':' then
      alignments[#alignments + 1] = 'right'
    else
      alignments[#alignments + 1] = 'left'
    end
  end
  return alignments
end

---Escape pipes so they stay inside their cell. GFM resolves `\|` back to a
---literal pipe, including inside inline code spans.
---@param text string
---@return string escaped, boolean changed
local function escape_pipes(text)
  if not text:find('|', 1, true) then
    return text, false
  end
  local escaped = text:gsub('\\|', '|'):gsub('|', '\\|')
  return escaped, escaped ~= text
end

---Drop backslash escapes, which have no meaning outside markdown.
---@param text string
local function unescape(text)
  return (text:gsub('\\(%p)', '%1'))
end

---Whether `**` markers pair up outside inline code, so stripping them only
---removes emphasis instead of mangling text such as `**kwargs`.
---@param text string
local function has_balanced_bold(text)
  local outside = text:gsub('(`+).-%1', '')
  local _, count = outside:gsub('%*%*+', '')
  return count > 0 and count % 2 == 0
end

---Turn a raw markdown token into plain text for box tables: inline code fences,
---bold markers and backslash escapes are dropped. Only the code span, or the
---text between bold markers, keeps a mapping to the original offsets.
---@param raw string
---@param offset integer 1-based byte offset of `raw` in the original text
---@param strip_bold boolean
local function plain_token(raw, offset, strip_bold)
  local function clean(text)
    if strip_bold then
      text = text:gsub('%*%*+', '')
    end
    return unescape(text)
  end

  local open_start, open_end = raw:find('`+')
  if open_start then
    local fence = raw:sub(open_start, open_end)
    local close_start, close_end = raw:find(fence, open_end + 1, true)
    if close_start then
      local prefix = clean(raw:sub(1, open_start - 1))
      local inner = raw:sub(open_end + 1, close_start - 1)
      local code = inner:gsub('\\|', '|')
      local text = prefix .. code .. clean(raw:sub(close_end + 1))
      if text ~= '' then
        local mappable = code == inner and #inner > 0
        return {
          text = text,
          map = mappable and { col = #prefix + 1, orig = offset + open_end, len = #inner } or nil,
        }
      end
    end
  end

  local text = clean(raw)
  if text == '' then
    return { text = raw, map = { col = 1, orig = offset, len = #raw } }
  end

  local lead = strip_bold and raw:match('^%*%*+') or ''
  local core = raw:sub(#lead + 1)
  if strip_bold then
    core = core:match('^(.-)%*%*+[^%w%s]*$') or core
  end
  local mappable = #core > 0 and text:sub(1, #core) == core
  return { text = text, map = mappable and { col = 1, orig = offset + #lead, len = #core } or nil }
end

---Split cell content into tokens, keeping inline code spans intact.
---@param cell {text: string, offset: integer}
---@param style 'box'|'markdown'
---@param strip_bold boolean
local function tokenize(cell, style, strip_bold)
  local text = cell.text
  local tokens = {}
  local pos = 1

  while true do
    local start = text:find('%S', pos)
    if not start then
      break
    end

    local stop
    if text:sub(start, start) == '`' then
      local run = text:match('^`+', start)
      local close_start, close_end = text:find(run, start + #run, true)
      stop = close_end or #text
      local trailing = text:find('%s', stop + 1)
      stop = (trailing and trailing - 1) or #text
    else
      local space = text:find('%s', start)
      stop = (space and space - 1) or #text
    end

    local raw = text:sub(start, stop)
    local raw_offset = cell.offset + start - 1
    if style == 'box' then
      tokens[#tokens + 1] = plain_token(raw, raw_offset, strip_bold)
    else
      local escaped, changed = escape_pipes(raw)
      tokens[#tokens + 1] = {
        text = escaped,
        -- Escaping shifts byte offsets, so these tokens cannot carry range mappings.
        map = (not changed) and { col = 1, orig = raw_offset, len = #raw } or nil,
      }
    end
    pos = stop + 1
  end

  return tokens
end

---Characters after which a long token may be split. Breaking an identifier at a
---separator reads far better than a hard mid-word cut.
local BREAK_AFTER = { ['_'] = true, ['-'] = true, ['.'] = true, ['/'] = true, [','] = true, [':'] = true, [')'] = true }

---Restrict a piece mapping to bytes `from..to` of the piece text, for a chunk
---that places byte `from` at column `col`.
---@param map {col: integer, orig: integer, len: integer}|nil
---@param from integer
---@param to integer
---@param col integer
local function slice_map(map, from, to, col)
  if not map then
    return nil
  end
  local first = math.max(from, map.col)
  local last = math.min(to, map.col + map.len - 1)
  if last < first then
    return nil
  end
  return { col = col + first - from, orig = map.orig + first - map.col, len = last - first + 1 }
end

---Split a token that is wider than the column into chunks. Inline code spans are
---re-fenced on every chunk so the markdown stays valid after wrapping.
---@param token {text: string, map?: {col: integer, orig: integer, len: integer}}
---@param width integer
---@param refence boolean
local function break_token(token, width, refence)
  local fence = refence and token.text:match('^`+') or nil
  local inner = token.text
  local inner_start = 1
  local chunk_width = width

  if fence and token.text:sub(-#fence) == fence and #token.text > 2 * #fence and width > 2 * #fence then
    inner = token.text:sub(#fence + 1, -#fence - 1)
    inner_start = #fence + 1
    chunk_width = width - 2 * #fence
  else
    fence = nil
  end

  local chunks = {}
  local units = split_units(inner)
  local index = 1
  local byte_offset = 0

  while index <= #units do
    local used = 0
    local bytes = 0
    local last = index - 1
    local break_at, break_bytes = nil, nil

    -- Greedily consume units up to the column width, remembering the last
    -- position where a break would land on a separator character.
    while last + 1 <= #units do
      local unit = units[last + 1]
      local unit_width = display_width(unit)
      if used > 0 and used + unit_width > chunk_width then
        break
      end
      last = last + 1
      used = used + unit_width
      bytes = bytes + #unit
      if BREAK_AFTER[unit] and last < #units then
        break_at, break_bytes = last, bytes
      end
    end

    -- Only honour a separator break when it keeps a useful amount of content.
    if break_at and last < #units and break_at > index and used - (bytes - break_bytes) >= chunk_width / 2 then
      last, bytes = break_at, break_bytes
    end

    local body = table.concat(units, '', index, last)
    local from = inner_start + byte_offset
    chunks[#chunks + 1] = {
      text = fence and (fence .. body .. fence) or body,
      map = slice_map(token.map, from, from + #body - 1, 1 + (fence and #fence or 0)),
    }

    byte_offset = byte_offset + bytes
    index = last + 1
  end

  return chunks
end

---Wrap tokens into lines of at most `width` display cells. `hard_break` tokens
---(from `<br>`) always start a new line.
---@return {text: string, map?: table}[][]
local function wrap_tokens(tokens, width, refence)
  local lines = {}
  local current = {}
  local current_width = 0
  local after_break = false

  local function flush()
    if #current > 0 then
      lines[#lines + 1] = current
      current = {}
      current_width = 0
    end
  end

  for _, token in ipairs(tokens) do
    local token_width = token.hard_break and 0 or display_width(token.text)
    if token.hard_break then
      if #current > 0 then
        flush()
      elseif after_break then
        lines[#lines + 1] = {}
      end
    elseif token_width > width then
      flush()
      for _, chunk in ipairs(break_token(token, width, refence)) do
        lines[#lines + 1] = { chunk }
      end
    elseif current_width == 0 then
      current = { token }
      current_width = token_width
    elseif current_width + 1 + token_width <= width then
      current[#current + 1] = token
      current_width = current_width + 1 + token_width
    else
      flush()
      current = { token }
      current_width = token_width
    end
    after_break = token.hard_break == true
  end
  flush()

  if #lines == 0 then
    lines = { {} }
  end
  return lines
end

---@param columns {text: string, offset: integer}[][][] tokens per row per column
---@param column_count integer
---@param total_width integer
---@param min_width integer
local function compute_widths(rows_tokens, column_count, total_width, min_width)
  local natural = {}
  for column = 1, column_count do
    natural[column] = 1
  end

  for _, row in ipairs(rows_tokens) do
    for column = 1, column_count do
      local width = 0
      for _, token in ipairs(row[column] or {}) do
        if token.hard_break then
          width = 0
        else
          width = width + display_width(token.text) + (width > 0 and 1 or 0)
          natural[column] = math.max(natural[column], width)
        end
      end
    end
  end

  local borders = 3 * column_count + 1
  local available = total_width - borders
  if available < column_count then
    available = column_count
  end

  local total = 0
  for _, width in ipairs(natural) do
    total = total + width
  end
  if total <= available then
    return natural
  end

  local floor = math.max(1, math.min(min_width, math.floor(available / column_count)))
  local widths = vim.deepcopy(natural)
  local iterations = 0

  while total > available and iterations < SHRINK_ITERATION_CAP do
    iterations = iterations + 1
    local widest, widest_width = nil, 0
    for column, width in ipairs(widths) do
      if width > floor and width > widest_width then
        widest, widest_width = column, width
      end
    end
    if not widest then
      break
    end
    widths[widest] = widths[widest] - 1
    total = total - 1
  end

  if total > available then
    local each = math.max(1, math.floor(available / column_count))
    for column = 1, column_count do
      widths[column] = each
    end
  end

  return widths
end

---@param pieces {text: string, offset: integer}[]
---@param width integer
---@return {text: string, offset: integer}[] pieces truncated to fit `width`
local function truncate_pieces(pieces, width)
  local kept = {}
  local used = 0

  pieces = vim.tbl_filter(function(piece)
    return not piece.hard_break
  end, pieces)

  for index, piece in ipairs(pieces) do
    local separator = index > 1 and 1 or 0
    local piece_width = display_width(piece.text)
    if used + separator + piece_width <= width then
      kept[#kept + 1] = piece
      used = used + separator + piece_width
    else
      -- Reserve one cell for the ellipsis that replaces the dropped content.
      local budget = width - used - separator - 1
      local text, byte_len = {}, 0
      local taken = 0
      for _, char in ipairs(split_units(piece.text)) do
        local char_width = display_width(char)
        if taken + char_width > budget then
          break
        end
        text[#text + 1] = char
        taken = taken + char_width
        byte_len = byte_len + #char
      end

      if byte_len > 0 then
        kept[#kept + 1] = {
          text = table.concat(text) .. ELLIPSIS,
          map = slice_map(piece.map, 1, byte_len, 1),
        }
      elseif used + separator + 1 <= width then
        kept[#kept + 1] = { text = ELLIPSIS }
      elseif #kept > 0 then
        kept[#kept] = { text = ELLIPSIS }
      end
      break
    end
  end

  return kept
end

---@param pieces {text: string, offset: integer}[]
---@param width integer
---@param alignment string
---@return string content, {col: integer, orig: integer, len: integer}[] mapped
local function render_cell(pieces, width, alignment)
  local parts = {}
  local mapped = {}
  local col = 1

  for index, piece in ipairs(pieces) do
    if index > 1 then
      parts[#parts + 1] = ' '
      col = col + 1
    end
    parts[#parts + 1] = piece.text
    if piece.map then
      mapped[#mapped + 1] = { col = col + piece.map.col - 1, orig = piece.map.orig, len = piece.map.len }
    end
    col = col + #piece.text
  end

  local content = table.concat(parts)
  local pad = width - display_width(content)
  if pad < 0 then
    pad = 0
  end

  local left_pad = 0
  if alignment == 'right' then
    left_pad = pad
  elseif alignment == 'center' then
    left_pad = math.floor(pad / 2)
  end

  if left_pad > 0 then
    content = string.rep(' ', left_pad) .. content
    for _, entry in ipairs(mapped) do
      entry.col = entry.col + left_pad
    end
  end
  content = content .. string.rep(' ', pad - left_pad)

  return content, mapped
end

---@param row_cells {text: string, offset: integer}[][] tokens per column
---@param widths integer[]
---@param alignments string[]
---@param prefix string
---@param single_line? boolean Truncate instead of wrapping (required for header rows,
---which must stay adjacent to the delimiter row to remain a valid GFM table)
---@param bar? string Column border, `|` unless given
local function render_row(row_cells, widths, alignments, prefix, single_line, bar)
  bar = bar or '|'
  local refence = bar == '|'
  local column_count = #widths
  local wrapped = {}
  local height = 1

  for column = 1, column_count do
    if single_line then
      wrapped[column] = { truncate_pieces(row_cells[column] or {}, widths[column]) }
    else
      wrapped[column] = wrap_tokens(row_cells[column] or {}, widths[column], refence)
      height = math.max(height, #wrapped[column])
    end
  end

  local lines = {}
  for line_index = 1, height do
    local parts = { prefix, bar }
    local col = #prefix + #bar + 1
    local mapped = {}
    local cells = {}

    for column = 1, column_count do
      local pieces = wrapped[column][line_index] or {}
      local content, cell_mapped = render_cell(pieces, widths[column], alignments[column] or 'left')
      parts[#parts + 1] = ' '
      col = col + 1
      for _, entry in ipairs(cell_mapped) do
        mapped[#mapped + 1] = { col = col + entry.col - 1, orig = entry.orig, len = entry.len }
      end
      local first = content:find('%S')
      if first then
        local last = #content - #content:match('%s*$')
        cells[column] = { col = col + first - 1, len = last - first + 1 }
      end
      parts[#parts + 1] = content
      col = col + #content
      parts[#parts + 1] = ' ' .. bar
      col = col + 1 + #bar
    end

    lines[#lines + 1] = { text = table.concat(parts), mapped = mapped, cells = cells }
  end

  return lines
end

---@param widths integer[]
---@param alignments string[]
---@param prefix string
local function render_delimiter(widths, alignments, prefix)
  local parts = { prefix, '|' }
  for column, width in ipairs(widths) do
    local alignment = alignments[column] or 'left'
    local dashes
    if alignment == 'center' then
      dashes = ':' .. string.rep('-', math.max(1, width - 2)) .. ':'
    elseif alignment == 'right' then
      dashes = string.rep('-', math.max(1, width - 1)) .. ':'
    else
      dashes = string.rep('-', math.max(1, width))
    end
    parts[#parts + 1] = ' ' .. dashes .. ' |'
  end
  return table.concat(parts)
end

---A rule between body rows. It is still a normal table row (so the table stays
---valid GFM and column borders keep lining up) whose cells are box-drawing
---lines. ASCII dashes cannot be used: parsers such as tree-sitter treat a
---dash-only row as the delimiter row of a new table.
---@param widths integer[]
---@param prefix string
local function render_row_separator(widths, prefix)
  local rule_width = math.max(1, display_width(RULE))
  local parts = { prefix, '|' }
  for _, width in ipairs(widths) do
    local count = math.max(1, math.floor(width / rule_width))
    local pad = math.max(0, width - count * rule_width)
    parts[#parts + 1] = ' ' .. string.rep(RULE, count) .. string.rep(' ', pad) .. ' |'
  end
  return table.concat(parts)
end

---@param widths integer[]
---@param prefix string
---@param chars string[] left, junction, right and fill characters
local function render_box_border(widths, prefix, chars)
  local parts = { prefix, chars[1] }
  for column, width in ipairs(widths) do
    parts[#parts + 1] = string.rep(chars[4], width + 2)
    parts[#parts + 1] = column < #widths and chars[2] or chars[3]
  end
  return table.concat(parts)
end

---Split a cell at `<br>` tags into consecutive sub-cells.
---@param cell {text: string, offset: integer}
---@return {text: string, offset: integer}[]
local function split_breaks(cell)
  local parts = {}
  local pos = 1
  while true do
    local from, to = cell.text:find(BR_PATTERN, pos)
    if not from then
      break
    end
    parts[#parts + 1] = { text = cell.text:sub(pos, from - 1), offset = cell.offset + pos - 1 }
    pos = to + 1
  end
  parts[#parts + 1] = { text = cell.text:sub(pos), offset = cell.offset + pos - 1 }
  return parts
end

---@param style 'box'|'markdown'
local function row_tokens(cells, column_count, style)
  local columns = {}
  for column = 1, column_count do
    columns[column] = {}
  end

  for index, cell in ipairs(cells) do
    local column = math.min(index, column_count)
    local strip_bold = style == 'box' and has_balanced_bold(cell.text)
    for part_index, part in ipairs(split_breaks(cell)) do
      if part_index > 1 then
        table.insert(columns[column], { hard_break = true })
      end
      for _, token in ipairs(tokenize(part, style, strip_bold)) do
        table.insert(columns[column], token)
      end
    end
  end

  return columns
end

---Fence long enough that no backtick run inside the table can close it.
---@param lines {text: string}[]
local function code_fence(lines)
  local longest = 0
  for _, line in ipairs(lines) do
    for run in line.text:gmatch('`+') do
      longest = math.max(longest, #run)
    end
  end
  return string.rep('`', math.max(3, longest + 1))
end

local function block_prefix(line)
  local prefix = line:match('^([%s>]*)') or ''
  if prefix:find('%S') and not prefix:find('>') then
    return nil
  end
  return prefix
end

local function is_fence(line)
  return line:match('^%s*```') ~= nil or line:match('^%s*~~~') ~= nil
end

---Reflow every GFM table found in `text`. With the default `box` style each
---table becomes a ```box code block drawn with box characters; the `markdown`
---style keeps a GFM table.
---@param text string
---@return string reflowed
---@return PiTableSegment[]|nil segments nil when the text was left untouched
---@return PiTableHighlight[]|nil highlights header and first-column cells of box tables
function M.reflow(text)
  if type(text) ~= 'string' or text == '' then
    return text, nil
  end

  local settings = tables_config()
  if settings.reflow == false then
    return text, nil
  end
  if not text:find('|', 1, true) then
    return text, nil
  end

  local lines = vim.split(text, '\n', { plain = true })
  local line_offsets = {}
  local offset = 1
  for index, line in ipairs(lines) do
    line_offsets[index] = offset
    offset = offset + #line + 1
  end

  local total_width = M.available_width()
  local min_width = math.max(1, math.floor(settings.min_column_width or 8))
  local style = settings.style == 'markdown' and 'markdown' or 'box'

  local out_lines = {}
  local segments = {}
  local highlights = {}
  local new_offset = 1

  ---@param line string
  ---@param mapped {col: integer, orig: integer, len: integer}[]|nil
  ---@param cells? {col: integer, len: integer}[]
  ---@param header? boolean
  local function emit(line, mapped, cells, header)
    out_lines[#out_lines + 1] = line
    for _, entry in ipairs(mapped or {}) do
      segments[#segments + 1] = { orig = entry.orig, new = new_offset + entry.col - 1, len = entry.len }
    end
    for column, cell in pairs(cells or {}) do
      local group = header and 'PiTableHeader' or (column == 1 and 'PiTableFirstColumn' or nil)
      if group then
        highlights[#highlights + 1] =
          { line = #out_lines, start_col = cell.col - 1, end_col = cell.col - 1 + cell.len, hl_group = group }
      end
    end
    new_offset = new_offset + #line + 1
  end

  local index = 1
  local in_fence = false

  while index <= #lines do
    local line = lines[index]

    if in_fence then
      if is_fence(line) then
        in_fence = false
      end
      emit(line, { { col = 1, orig = line_offsets[index], len = #line } })
      index = index + 1
    elseif is_fence(line) then
      in_fence = true
      emit(line, { { col = 1, orig = line_offsets[index], len = #line } })
      index = index + 1
    else
      local prefix = block_prefix(line)
      local next_line = lines[index + 1]
      local alignments = nil

      if prefix and line:find('|', 1, true) and next_line and block_prefix(next_line) == prefix then
        alignments = delimiter_alignments(split_cells(next_line, line_offsets[index + 1]))
      end

      if not alignments then
        emit(line, { { col = 1, orig = line_offsets[index], len = #line } })
        index = index + 1
      else
        local column_count = #alignments
        local rows = { row_tokens(split_cells(line, line_offsets[index]), column_count, style) }
        local last = index + 1

        local cursor = index + 2
        while cursor <= #lines do
          local body = lines[cursor]
          if not body:find('|', 1, true) or block_prefix(body) ~= prefix or is_fence(body) then
            break
          end
          rows[#rows + 1] = row_tokens(split_cells(body, line_offsets[cursor]), column_count, style)
          last = cursor
          cursor = cursor + 1
        end

        local widths = compute_widths(rows, column_count, total_width - #prefix, min_width)
        local box = style == 'box'

        local rendered_rows = {}
        local any_multiline = false
        for row_index, row in ipairs(rows) do
          rendered_rows[row_index] =
            render_row(row, widths, alignments, prefix, not box and row_index == 1, box and '│' or '|')
          if row_index > 1 and #rendered_rows[row_index] > 1 then
            any_multiline = true
          end
        end

        local separator_mode = settings.row_separator or 'auto'
        local separate_rows = separator_mode == 'always' or (separator_mode == 'auto' and any_multiline)

        local table_lines = {}
        local function push(text_line, mapped, cells, header)
          table_lines[#table_lines + 1] = { text = text_line, mapped = mapped, cells = cells, header = header }
        end

        if box then
          push(render_box_border(widths, prefix, BOX.top))
        end
        for row_index, rendered in ipairs(rendered_rows) do
          if separate_rows and row_index > 2 then
            push(box and render_box_border(widths, prefix, BOX.rule) or render_row_separator(widths, prefix))
          end
          for _, rendered_line in ipairs(rendered) do
            push(
              rendered_line.text,
              rendered_line.mapped,
              box and (row_index == 1 or column_count > 1) and rendered_line.cells or nil,
              box and row_index == 1
            )
          end
          if row_index == 1 and not box then
            push(render_delimiter(widths, alignments, prefix))
          elseif row_index == 1 and #rendered_rows > 1 then
            push(render_box_border(widths, prefix, BOX.head))
          end
        end

        if box then
          local fence = code_fence(table_lines)
          emit(prefix .. fence .. 'box', nil)
          push(render_box_border(widths, prefix, BOX.bottom))
          push(prefix .. fence)
        end
        for _, table_line in ipairs(table_lines) do
          emit(table_line.text, table_line.mapped, table_line.cells, table_line.header)
        end

        index = last + 1
      end
    end
  end

  local reflowed = table.concat(out_lines, '\n')
  if reflowed == text then
    return text, nil
  end
  return reflowed, segments, highlights
end

---Translate offset ranges from the original text into the reflowed text.
---Ranges that span several reflowed lines are split into one range per line.
---@generic T: {start_offset: integer, end_offset: integer}
---@param ranges T[]
---@param segments PiTableSegment[]|nil
---@return T[]
function M.map_ranges(ranges, segments)
  if not segments or not ranges or #ranges == 0 then
    return ranges or {}
  end

  local mapped = {}
  for _, range in ipairs(ranges) do
    for _, segment in ipairs(segments) do
      local seg_start = segment.orig
      local seg_end = segment.orig + segment.len - 1
      if range.start_offset <= seg_end and range.end_offset >= seg_start then
        local from = math.max(range.start_offset, seg_start)
        local to = math.min(range.end_offset, seg_end)
        local copy = vim.tbl_extend('force', {}, range)
        copy.start_offset = segment.new + (from - seg_start)
        copy.end_offset = segment.new + (to - seg_start)
        mapped[#mapped + 1] = copy
      end
    end
  end

  return mapped
end

return M
