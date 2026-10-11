local assert = require('luassert')
local config = require('pi.config')
local markdown_table = require('pi.ui.markdown_table')

local function setup(width, overrides)
  config.setup({
    ui = {
      output = {
        rendering = {
          tables = vim.tbl_extend(
            'force',
            { style = 'markdown', reflow = true, min_column_width = 6, max_width = width, row_separator = 'auto' },
            overrides or {}
          ),
        },
      },
    },
  })
end

local function lines_of(text)
  return vim.split(text, '\n', { plain = true })
end

describe('pi.ui.markdown_table', function()
  before_each(function()
    setup(60)
  end)

  it('leaves text without tables untouched', function()
    local text = 'Just a paragraph\n\nwith | a stray pipe.'
    local out, segments = markdown_table.reflow(text)
    assert.equals(text, out)
    assert.is_nil(segments)
  end)

  it('wraps cell content inside its own column', function()
    local text = table.concat({
      '| Action | Description |',
      '| --- | --- |',
      '| Open | a fairly long description that must wrap across several lines |',
    }, '\n')

    local out = markdown_table.reflow(text)
    local out_lines = lines_of(out)

    assert.is_true(#out_lines > 3)
    for _, line in ipairs(out_lines) do
      assert.is_true(vim.fn.strdisplaywidth(line) <= 60)
      assert.equals('|', line:sub(1, 1))
      assert.equals('|', line:sub(-1))
    end
  end)

  it('keeps the header on a single line so the table stays valid GFM', function()
    local text = table.concat({
      '| An extremely long header cell that will not fit | B |',
      '| --- | --- |',
      '| value | other |',
    }, '\n')

    local out_lines = lines_of(markdown_table.reflow(text))
    assert.matches('^| ', out_lines[1])
    assert.matches('^|%s*%-+', out_lines[2])
  end)

  it('preserves column count and alignment markers', function()
    local text = table.concat({
      '| a | b | c |',
      '| :--- | :---: | ---: |',
      '| 1 | 2 | 3 |',
    }, '\n')

    local out_lines = lines_of(markdown_table.reflow(text))
    local delimiter = out_lines[2]

    local cells = {}
    for cell in delimiter:gmatch('|([^|]+)') do
      cells[#cells + 1] = vim.trim(cell)
    end

    assert.equals(3, #cells)
    assert.matches('^%-+$', cells[1])
    assert.matches('^:%-+:$', cells[2])
    assert.matches('^%-+:$', cells[3])
  end)

  it('keeps inline code spans balanced when they are split', function()
    local text = table.concat({
      '| cmd |',
      '| --- |',
      "| `require('pi.api').some_extremely_long_function_name()` |",
    }, '\n')

    for _, line in ipairs(lines_of(markdown_table.reflow(text))) do
      local _, backticks = line:gsub('`', '')
      assert.equals(0, backticks % 2)
    end
  end)

  it('does not treat pipes inside inline code as column separators', function()
    local text = table.concat({
      '| pattern | note |',
      '| --- | --- |',
      '| `a | b` | alternation |',
    }, '\n')

    local out_lines = lines_of(markdown_table.reflow(text))
    local body = out_lines[3]

    assert.is_true(body:find('\\|', 1, true) ~= nil)

    local _, separators = body:gsub('\\|', ''):gsub('|', '')
    assert.equals(3, separators)
  end)

  it('ignores tables inside fenced code blocks', function()
    local text = table.concat({
      '```markdown',
      '| a | b |',
      '| --- | --- |',
      '| 1 | 2 |',
      '```',
    }, '\n')

    local out, segments = markdown_table.reflow(text)
    assert.equals(text, out)
    assert.is_nil(segments)
  end)

  it('reflows tables nested in blockquotes keeping the prefix', function()
    local text = table.concat({
      '> | a | b |',
      '> | --- | --- |',
      '> | some longer value that needs wrapping here | 2 |',
    }, '\n')

    for _, line in ipairs(lines_of(markdown_table.reflow(text))) do
      assert.matches('^> |', line)
    end
  end)

  it('is a no-op when reflow is disabled', function()
    config.setup({ ui = { output = { rendering = { tables = { reflow = false } } } } })
    local text = '| a | b |\n| --- | --- |\n| 1 | 2 |'
    local out, segments = markdown_table.reflow(text)
    assert.equals(text, out)
    assert.is_nil(segments)
  end)

  describe('width handling', function()
    it('aligns every rendered line to the same display width', function()
      local text = table.concat({
        '| Feature | Status | Notes |',
        '| --- | :---: | --- |',
        "| Sidebar | ✅ | Short cell, wide emoji to check that double-width glyphs don't shift borders. |",
        '| CJK | ❓ | 表格格式化测试 — these characters are double-width so display width must be used. |',
        '| Code | ⚠️ | Uses `vim.api.nvim_buf_set_lines()` and `require("pi.sidebar").render()` here. |',
      }, '\n')

      local out_lines = lines_of(markdown_table.reflow(text))
      local expected = vim.fn.strdisplaywidth(out_lines[1])

      for _, line in ipairs(out_lines) do
        assert.equals(expected, vim.fn.strdisplaywidth(line))
      end
    end)

    it('breaks a long single token at separator characters', function()
      local text = table.concat({
        '| token |',
        '| --- |',
        '| averyveryverylongidentifier_without_any_spaces_at_all_to_check_overflow_behavior |',
      }, '\n')

      local out_lines = lines_of(markdown_table.reflow(text))
      local body = {}
      for index = 3, #out_lines do
        body[#body + 1] = vim.trim(out_lines[index]:match('^|(.*)|$'))
      end

      assert.is_true(#body > 1)
      -- Every chunk but the last should end on a separator rather than mid-word.
      for index = 1, #body - 1 do
        assert.matches('_$', body[index])
      end
      assert.equals(
        'averyveryverylongidentifier_without_any_spaces_at_all_to_check_overflow_behavior',
        table.concat(body)
      )
    end)
  end)

  describe('row separators', function()
    local function separator_count(out_lines)
      local count = 0
      -- Skip the header delimiter at index 2.
      for index = 3, #out_lines do
        if out_lines[index]:match('^[|%s─]+$') then
          count = count + 1
        end
      end
      return count
    end

    it('adds a rule between rows when some row wraps', function()
      local text = table.concat({
        '| a | b |',
        '| --- | --- |',
        '| first row with quite a lot of text that has to wrap somewhere | 1 |',
        '| second row also carrying enough text to require wrapping here | 2 |',
        '| third row with yet more text so that it wraps as well right | 3 |',
      }, '\n')

      assert.equals(2, separator_count(lines_of(markdown_table.reflow(text))))
    end)

    it('omits rules for compact tables under auto', function()
      local text = '| # | OK |\n| - | -- |\n| 1 | y |\n| 2 | n |'
      assert.equals(0, separator_count(lines_of(markdown_table.reflow(text))))
    end)

    it('always adds rules when configured', function()
      setup(60, { row_separator = 'always' })
      local text = '| # | OK |\n| - | -- |\n| 1 | y |\n| 2 | n |'
      assert.equals(1, separator_count(lines_of(markdown_table.reflow(text))))
    end)

    it('never adds rules when configured', function()
      setup(60, { row_separator = 'never' })
      local text = table.concat({
        '| a | b |',
        '| --- | --- |',
        '| first row with quite a lot of text that has to wrap somewhere | 1 |',
        '| second row also carrying enough text to require wrapping here | 2 |',
      }, '\n')

      assert.equals(0, separator_count(lines_of(markdown_table.reflow(text))))
    end)

    it('never emits dash-only body rows that parsers read as a new delimiter row', function()
      setup(60, { row_separator = 'always' })
      local text = '| a | b |\n| --- | --- |\n| 1 | 2 |\n| 3 | 4 |\n| 5 | 6 |'

      local out_lines = lines_of(markdown_table.reflow(text))
      for index = 3, #out_lines do
        assert.is_nil(out_lines[index]:match('^[|%s:%-]+$'))
      end
    end)

    it('keeps a reflowed table with rules as a single tree-sitter table', function()
      setup(60, { row_separator = 'always' })
      local text = '| a | b |\n| --- | --- |\n| 1 | 2 |\n| 3 | 4 |\n| 5 | 6 |'

      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines_of(markdown_table.reflow(text)))
      local ok, parser = pcall(vim.treesitter.get_parser, buf, 'markdown')
      if not ok or not parser then
        vim.api.nvim_buf_delete(buf, { force = true })
        return
      end

      local tables = 0
      local function count(node)
        if node:type() == 'pipe_table' then
          tables = tables + 1
        end
        for child in node:iter_children() do
          count(child)
        end
      end
      count(parser:parse()[1]:root())
      vim.api.nvim_buf_delete(buf, { force = true })

      assert.equals(1, tables)
    end)

    it('keeps separator rules the same width as the rows', function()
      setup(60, { row_separator = 'always' })
      local text = '| a | b |\n| --- | --- |\n| 1 | 2 |\n| 3 | 4 |'

      local out_lines = lines_of(markdown_table.reflow(text))
      local expected = vim.fn.strdisplaywidth(out_lines[1])
      for _, line in ipairs(out_lines) do
        assert.equals(expected, vim.fn.strdisplaywidth(line))
      end
    end)
  end)

  describe('box style', function()
    before_each(function()
      setup(60, { style = 'box' })
    end)

    local function table_lines(out)
      local result = {}
      for _, line in ipairs(lines_of(out)) do
        if line:find('[│┌└├╞]') then
          result[#result + 1] = line
        end
      end
      return result
    end

    local function cell_texts(line)
      local cells = {}
      for cell in line:gmatch('│([^│]*)') do
        cells[#cells + 1] = vim.trim(cell)
      end
      cells[#cells] = nil
      return cells
    end

    it('is the default style', function()
      config.setup({ ui = { output = { rendering = { tables = { max_width = 60 } } } } })
      local out = markdown_table.reflow('| a | b |\n| --- | --- |\n| 1 | 2 |')
      assert.equals('```box', lines_of(out)[1])
    end)

    it('wraps the table in a box code block with borders', function()
      local text = 'before\n| a | b |\n| --- | --- |\n| 1 | 2 |\nafter'
      assert.same({
        'before',
        '```box',
        '┌───┬───┐',
        '│ a │ b │',
        '╞═══╪═══╡',
        '│ 1 │ 2 │',
        '└───┴───┘',
        '```',
        'after',
      }, lines_of(markdown_table.reflow(text)))
    end)

    it('omits the header rule for a header-only table', function()
      local out_lines = lines_of(markdown_table.reflow('| a | b |\n| --- | --- |'))
      assert.same({ '```box', '┌───┬───┐', '│ a │ b │', '└───┴───┘', '```' }, out_lines)
    end)

    it('keeps every line within the width and aligned', function()
      local text = table.concat({
        '| An extremely long header cell that will not fit on one line | B |',
        '| --- | :---: |',
        '| CJK 表格格式化测试 and a long tail of text that needs to wrap | ✅ |',
      }, '\n')

      local lines = table_lines(markdown_table.reflow(text))
      local expected = vim.fn.strdisplaywidth(lines[1])
      assert.is_true(expected <= 60)
      for _, line in ipairs(lines) do
        assert.equals(expected, vim.fn.strdisplaywidth(line))
      end
    end)

    it('wraps the header instead of truncating it', function()
      local text = '| An extremely long header cell that will not fit on one line | B |\n| --- | --- |\n| x | y |'
      local out = markdown_table.reflow(text)
      assert.is_nil(out:find('…', 1, true))
      assert.is_not_nil(out:find('one line', 1, true))
    end)

    it('strips inline code fences, bold markers and pipe escapes', function()
      local text = '| a | b |\n| --- | --- |\n| **bold** `code` | `x \\| y` and \\| |'
      local lines = table_lines(markdown_table.reflow(text))
      assert.same({ 'bold code', 'x | y and |' }, cell_texts(lines[4]))
    end)

    it('keeps unpaired stars and stars inside code', function()
      local text = '| a | b |\n| --- | --- |\n| **kwargs | `**opts` and **bold** |'
      local lines = table_lines(markdown_table.reflow(text))
      assert.same({ '**kwargs', '**opts and bold' }, cell_texts(lines[4]))
    end)

    it('turns <br> into a line break inside the cell', function()
      local text = '| a | b |\n| --- | --- |\n| one<br>two<BR/>three | x |'
      local lines = table_lines(markdown_table.reflow(text))
      assert.same({ 'one', 'x' }, cell_texts(lines[4]))
      assert.same({ 'two', '' }, cell_texts(lines[5]))
      assert.same({ 'three', '' }, cell_texts(lines[6]))
    end)

    it('keeps blank lines from consecutive <br> tags', function()
      local text = '| a |\n| --- |\n| one<br><br>two |'
      local lines = table_lines(markdown_table.reflow(text))
      assert.same({ 'one' }, cell_texts(lines[4]))
      assert.same({ '' }, cell_texts(lines[5]))
      assert.same({ 'two' }, cell_texts(lines[6]))
    end)

    it('draws row rules when a body row wraps', function()
      local text = table.concat({
        '| a | b |',
        '| --- | --- |',
        '| first row with quite a lot of text that has to wrap somewhere | 1 |',
        '| second row | 2 |',
      }, '\n')

      local rules = 0
      for _, line in ipairs(lines_of(markdown_table.reflow(text))) do
        if line:match('^├') then
          rules = rules + 1
        end
      end
      assert.equals(1, rules)
    end)

    it('uses a longer fence when cells contain backtick runs', function()
      local text = '| a |\n| --- |\n| ```` ``` ```` |'
      local out_lines = lines_of(markdown_table.reflow(text))
      assert.equals('````box', out_lines[1])
      assert.equals('````', out_lines[#out_lines])
    end)

    it('keeps the blockquote prefix on fence and border lines', function()
      local text = '> | a | b |\n> | --- | --- |\n> | 1 | 2 |'
      for _, line in ipairs(lines_of(markdown_table.reflow(text))) do
        assert.matches('^> ', line)
      end
    end)

    it('maps ranges inside inline code onto the plain text', function()
      local text = table.concat({
        '| file | note |',
        '| --- | --- |',
        '| `lua/pi/init.lua`, **see** | some note that is long enough to wrap somewhere |',
      }, '\n')

      local needle = 'lua/pi/init.lua'
      local start_offset = text:find(needle, 1, true)
      local out, segments = markdown_table.reflow(text)
      local range = { start_offset = start_offset, end_offset = start_offset + #needle - 1 }
      local mapped = markdown_table.map_ranges({ range }, segments)

      local reconstructed = {}
      for _, entry in ipairs(mapped) do
        reconstructed[#reconstructed + 1] = out:sub(entry.start_offset, entry.end_offset)
      end
      assert.equals(needle, table.concat(reconstructed))
    end)

    it('maps ranges in a token split across lines', function()
      setup(30, { style = 'box' })
      local needle = 'averyveryverylongidentifier_without_spaces'
      local text = '| token |\n| --- |\n| `' .. needle .. '` |'
      local start_offset = text:find(needle, 1, true)
      local out, segments = markdown_table.reflow(text)
      local range = { start_offset = start_offset, end_offset = start_offset + #needle - 1 }
      local mapped = markdown_table.map_ranges({ range }, segments)

      assert.is_true(#mapped > 1)
      local reconstructed = {}
      for _, entry in ipairs(mapped) do
        reconstructed[#reconstructed + 1] = out:sub(entry.start_offset, entry.end_offset)
      end
      assert.equals(needle, table.concat(reconstructed))
    end)

    it('reports header and first column highlights over the cell text', function()
      local text = '| key | the value |\n| --- | --- |\n| first | 1 |\n| | 2 |'
      local out, _, highlights = markdown_table.reflow(text)
      local out_lines = lines_of(out)

      local seen = {}
      for _, highlight in ipairs(highlights) do
        local cell = out_lines[highlight.line]:sub(highlight.start_col + 1, highlight.end_col)
        seen[#seen + 1] = highlight.hl_group .. ':' .. cell
      end

      assert.same({ 'PiTableHeader:key', 'PiTableHeader:the value', 'PiTableFirstColumn:first' }, seen)
    end)

    it('highlights every line of a wrapped header', function()
      setup(30, { style = 'box' })
      local text = '| a header long enough to wrap around | b |\n| --- | --- |\n| x | y |'
      local out, _, highlights = markdown_table.reflow(text)
      local out_lines = lines_of(out)

      local header_lines = {}
      for _, highlight in ipairs(highlights) do
        if highlight.hl_group == 'PiTableHeader' and header_lines[#header_lines] ~= highlight.line then
          header_lines[#header_lines + 1] = highlight.line
        end
      end

      local rule = 3
      while not out_lines[rule]:match('^╞') do
        rule = rule + 1
      end
      local expected = {}
      for line = 3, rule - 1 do
        expected[#expected + 1] = line
      end
      assert.is_true(#expected > 1)
      assert.same(expected, header_lines)
    end)

    it('highlights only the header of a single-column table', function()
      local _, _, highlights = markdown_table.reflow('| a |\n| --- |\n| 1 |')
      assert.equals(1, #highlights)
      assert.equals('PiTableHeader', highlights[1].hl_group)
    end)

    it('reports no highlights for the markdown style', function()
      setup(60, { style = 'markdown' })
      local _, _, highlights = markdown_table.reflow('| a | b |\n| --- | --- |\n| 1 | 2 |')
      assert.same({}, highlights)
    end)

    it('parses as a single code block', function()
      local text = '| a | b |\n| --- | --- |\n| 1 | 2 |\n| 3 | 4 |'
      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines_of(markdown_table.reflow(text)))
      local parser = vim.treesitter.get_parser(buf, 'markdown')
      local root = parser:parse()[1]:root()
      local types = {}
      for child in root:iter_children() do
        for node in child:iter_children() do
          types[#types + 1] = node:type()
        end
      end
      vim.api.nvim_buf_delete(buf, { force = true })
      assert.same({ 'fenced_code_block' }, types)
    end)
  end)

  describe('map_ranges', function()
    it('returns ranges unchanged when there are no segments', function()
      local ranges = { { start_offset = 1, end_offset = 3 } }
      assert.same(ranges, markdown_table.map_ranges(ranges, nil))
    end)

    it('maps an offset range onto the reflowed text', function()
      local text = table.concat({
        '| file | note |',
        '| --- | --- |',
        '| lua/pi/init.lua | some note that is long enough to wrap somewhere |',
      }, '\n')

      local needle = 'lua/pi/init.lua'
      local start_offset = text:find(needle, 1, true)
      local range = {
        start_offset = start_offset,
        end_offset = start_offset + #needle - 1,
        path = needle,
      }

      local out, segments = markdown_table.reflow(text)
      assert.is_not_nil(segments)

      local mapped = markdown_table.map_ranges({ range }, segments)
      assert.is_true(#mapped >= 1)

      local reconstructed = {}
      for _, entry in ipairs(mapped) do
        assert.equals(needle, entry.path)
        reconstructed[#reconstructed + 1] = out:sub(entry.start_offset, entry.end_offset)
      end
      assert.equals(needle, table.concat(reconstructed))
    end)
  end)
end)
