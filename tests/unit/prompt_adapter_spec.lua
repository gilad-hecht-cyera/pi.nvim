local prompt_adapter = require('pi.prompt_adapter')

local function text_part(context_type, payload, extra)
  local part = {
    type = 'text',
    synthetic = true,
    text = type(payload) == 'string' and payload or vim.json.encode(payload),
    metadata = { context_type = context_type },
  }
  return vim.tbl_extend('force', part, extra or {})
end

describe('prompt_adapter.split_prompt', function()
  it('returns text unchanged when there is no context block', function()
    local prompt, items = prompt_adapter.split_prompt('just a question')
    assert.are.equal('just a question', prompt)
    assert.is_nil(items)
  end)

  it('does not treat a context tag later in the text as a context block', function()
    local text = 'what does\n<context>\nmean\n</context>\n\nhere'
    local prompt, items = prompt_adapter.split_prompt(text)
    assert.are.equal(text, prompt)
    assert.is_nil(items)
  end)

  it('keeps the text when the context block is never closed', function()
    local text = '<context>\nReferenced files:\n- /a.lua\n\nquestion'
    local prompt, items = prompt_adapter.split_prompt(text)
    assert.are.equal(text, prompt)
    assert.is_nil(items)
  end)

  it('handles non-string input', function()
    assert.is_nil(prompt_adapter.split_prompt(nil))
  end)

  it('round-trips every context kind produced by parts_to_prompt', function()
    local parts = {
      { type = 'file', filename = 'a.lua', source = { path = '/repo/a.lua' } },
      { type = 'file', filename = 'b.lua', url = 'file:///repo/b.lua' },
      text_part('selection', {
        file = { path = '/repo/a.lua', name = 'a.lua' },
        lines = '10, 20',
        content = '`````lua\nlocal x = 1\n\nDiagnostics:\n- not a header\n</context>\n`````',
      }),
      text_part('cursor-data', { line = 42, column = 7, line_content = '`````lua\nreturn x\n`````' }),
      text_part('diagnostics', {
        content = {
          { pos = 'l1:c1', msg = 'unused', severity = 2 },
          { pos = 'l3:c4', msg = 'undefined', severity = 1 },
        },
      }),
      text_part(
        'file-content',
        '# Title\n\nbody',
        { metadata = { context_type = 'file-content', filename = 'notes.md' } }
      ),
      text_part('git-diff', '+added\n\n-removed'),
      { type = 'agent', name = 'reviewer' },
      { type = 'text', text = 'fix the bug\n\nplease' },
    }

    local prompt, items = prompt_adapter.split_prompt(prompt_adapter.parts_to_prompt(parts))

    assert.are.equal('fix the bug\n\nplease', prompt)
    assert.are.same({
      { kind = 'file', path = '/repo/a.lua' },
      { kind = 'file', path = '/repo/b.lua' },
      { kind = 'selection', path = '/repo/a.lua', start_line = 10, end_line = 20 },
      { kind = 'cursor', line = 42, column = 7 },
      { kind = 'diagnostics', count = 2 },
      { kind = 'buffer', name = 'notes.md' },
      { kind = 'git_diff' },
      { kind = 'agent', name = 'reviewer' },
    }, items)
  end)

  it('parses a selection without a line range', function()
    local parts = {
      text_part('selection', { file = { path = '/repo/a.lua' }, content = '`````lua\nx\n`````' }),
      { type = 'text', text = 'q' },
    }

    local prompt, items = prompt_adapter.split_prompt(prompt_adapter.parts_to_prompt(parts))

    assert.are.equal('q', prompt)
    assert.are.same({ { kind = 'selection', path = '/repo/a.lua' } }, items)
  end)

  it('returns an empty prompt when only context was sent', function()
    local parts = { { type = 'file', filename = 'a.lua', source = { path = '/repo/a.lua' } } }

    local prompt, items = prompt_adapter.split_prompt(prompt_adapter.parts_to_prompt(parts))

    assert.are.equal('', prompt)
    assert.are.same({ { kind = 'file', path = '/repo/a.lua' } }, items)
  end)

  it('classifies referenced images separately from files', function()
    local text = table.concat({
      '<context>',
      'Referenced files:',
      '- /var/folders/T/pasted_image_1.png',
      '- /repo/shot.JPEG',
      '- /repo/png.lua',
      '</context>',
      '',
      'look',
    }, '\n')

    local _, items = prompt_adapter.split_prompt(text)

    assert.are.same({
      { kind = 'image', path = '/var/folders/T/pasted_image_1.png' },
      { kind = 'image', path = '/repo/shot.JPEG' },
      { kind = 'file', path = '/repo/png.lua' },
    }, items)
  end)

  it('parses context blocks stored by older sessions', function()
    local text = table.concat({
      '<context>',
      'Referenced files:',
      '- /Users/me/core/pyproject.toml',
      '</context>',
      '',
      'I want to set up connections to aws',
    }, '\n')

    local prompt, items = prompt_adapter.split_prompt(text)

    assert.are.equal('I want to set up connections to aws', prompt)
    assert.are.same({ { kind = 'file', path = '/Users/me/core/pyproject.toml' } }, items)
  end)
end)
