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
            { reflow = true, min_column_width = 6, max_width = width, row_separator = 'auto' },
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
        if out_lines[index]:match('^[|%s%-]+$') then
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
