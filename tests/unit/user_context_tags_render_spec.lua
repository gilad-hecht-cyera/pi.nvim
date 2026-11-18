local helpers = require('tests.helpers')
local state = require('pi.state')
local ctx = require('pi.ui.renderer.ctx')

describe('user message context tags', function()
  local renderer

  before_each(function()
    helpers.replay_setup()
    renderer = require('pi.ui.renderer')
    state.session.set_active({ id = 'ses_test', title = 'Test Session' })
  end)

  after_each(function()
    ctx:reset()
    if state.windows then
      require('pi.ui.ui').close_windows(state.windows)
    end
  end)

  local function render_user_message(context_items)
    renderer._render_full_session_data({
      {
        info = { id = 'msg_u', role = 'user', sessionID = 'ses_test', time = { created = 1 } },
        parts = {
          {
            id = 'prt_u',
            messageID = 'msg_u',
            sessionID = 'ses_test',
            type = 'text',
            text = 'hello',
            context_items = context_items,
          },
        },
      },
      {
        info = { id = 'msg_a', role = 'assistant', sessionID = 'ses_test', time = { created = 2 } },
        parts = { { id = 'prt_a', messageID = 'msg_a', sessionID = 'ses_test', type = 'text', text = 'answer' } },
      },
    })
    return vim.api.nvim_buf_get_lines(state.windows.output_buf, 0, -1, false)
  end

  local function find_line(lines, needle)
    for i, line in ipairs(lines) do
      if line:find(needle, 1, true) then
        return i
      end
    end
  end

  it('shows the message actions on the tag line', function()
    local lines = render_user_message({ { kind = 'file', path = '/repo/a.lua' } })

    local prompt_line = find_line(lines, 'hello')
    local tag_line = find_line(lines, 'a.lua')
    assert.are.equal(prompt_line + 2, tag_line)
    assert.are.equal('', lines[prompt_line + 1])

    local actions = renderer.get_actions_for_line(tag_line - 1)
    assert.is_truthy(actions and #actions > 0)
    for _, action in ipairs(actions) do
      assert.are.equal(tag_line - 1, action.display_line)
    end
  end)

  it('resolves a file tag to its target in the rendered buffer', function()
    local lines = render_user_message({ { kind = 'selection', path = '/repo/a.lua', start_line = 4, end_line = 9 } })

    local tag_line = find_line(lines, 'a.lua:4-9')
    local col = lines[tag_line]:find('a.lua', 1, true)
    local target = renderer.get_target_at_position(tag_line, col)

    assert.is_not_nil(target)
    assert.are.equal('/repo/a.lua', target.path)
    assert.are.equal(4, target.line)
  end)

  it('keeps the actions on the trailing blank line without context', function()
    local lines = render_user_message(nil)

    local prompt_line = find_line(lines, 'hello')
    local actions = renderer.get_actions_for_line(prompt_line - 1)
    assert.is_truthy(actions and #actions > 0)
    assert.are.equal(prompt_line, actions[1].display_line)
    assert.are.equal('', lines[prompt_line + 1])
  end)
end)
