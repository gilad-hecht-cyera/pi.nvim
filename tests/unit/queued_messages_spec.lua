local queued_messages = require('pi.ui.queued_messages')
local state = require('pi.state')

local function create_windows(width)
  local input_buf = vim.api.nvim_create_buf(false, true)
  local output_buf = vim.api.nvim_create_buf(false, true)
  local output_win = vim.api.nvim_open_win(output_buf, false, {
    relative = 'editor',
    width = width,
    height = 7,
    row = 0,
    col = 2,
  })
  local input_win = vim.api.nvim_open_win(input_buf, true, {
    relative = 'editor',
    width = width,
    height = 3,
    row = 8,
    col = 2,
  })
  return { input_buf = input_buf, input_win = input_win, output_buf = output_buf, output_win = output_win }
end

describe('queued messages', function()
  local windows

  before_each(function()
    queued_messages.teardown()
    state.session.clear_queued_user_messages()
    state.session.set_active({ id = 'session-a' })
    windows = create_windows(42)
    state.ui.set_windows(windows)
    queued_messages.setup(windows)
  end)

  after_each(function()
    queued_messages.teardown()
    if windows.input_win and vim.api.nvim_win_is_valid(windows.input_win) then
      vim.api.nvim_win_close(windows.input_win, true)
    end
    if windows.output_win and vim.api.nvim_win_is_valid(windows.output_win) then
      vim.api.nvim_win_close(windows.output_win, true)
    end
    if windows.input_buf and vim.api.nvim_buf_is_valid(windows.input_buf) then
      vim.api.nvim_buf_delete(windows.input_buf, { force = true })
    end
    if windows.output_buf and vim.api.nvim_buf_is_valid(windows.output_buf) then
      vim.api.nvim_buf_delete(windows.output_buf, { force = true })
    end
    state.ui.clear_windows()
    state.renderer.set_messages(nil)
    state.session.clear_queued_user_messages()
    state.session.clear_active()
  end)

  it('shows active session prompts above the right side of the input', function()
    state.session.queue_user_message('session-b', 'not visible')
    state.session.queue_user_message('session-a', 'first queued prompt')
    state.session.queue_user_message('session-a', 'second\nqueued prompt')
    assert.is_true(vim.wait(1000, function()
      return queued_messages._window() ~= nil
    end))

    local win = queued_messages._window()
    assert.is_true(vim.api.nvim_win_is_valid(win))

    local buf = vim.api.nvim_win_get_buf(win)
    assert.same(
      { 'Queued (2)', '1  first queued prompt', '2  second queued prompt' },
      vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    )

    local config = vim.api.nvim_win_get_config(win)
    assert.equal('SW', config.anchor)
    assert.equal(windows.input_win, config.win)
    assert.equal(0, config.row)
    assert.is_true(config.col > 0)
  end)

  it('closes once the active queue is empty', function()
    local id = state.session.queue_user_message('session-a', 'pending')
    assert.is_true(vim.wait(1000, function()
      return queued_messages._window() ~= nil
    end))
    local win = queued_messages._window()

    state.session.remove_queued_user_message('session-a', id)
    assert.is_true(vim.wait(1000, function()
      return queued_messages._window() == nil
    end))

    assert.is_false(vim.api.nvim_win_is_valid(win))
    assert.is_nil(queued_messages._window())
  end)

  it('removes the oldest prompt only after its text is rendered', function()
    state.renderer.set_messages({})
    state.session.queue_user_message('session-a', 'first')
    state.session.queue_user_message('session-a', 'second')

    local events = require('pi.ui.renderer.events')
    events.on_message_updated({
      info = { id = 'message-1', sessionID = 'session-a', role = 'user' },
      parts = {},
    })
    assert.equal(2, #state.queued_user_messages['session-a'])

    events.on_part_updated({
      part = {
        id = 'part-1',
        messageID = 'message-1',
        sessionID = 'session-a',
        type = 'text',
        text = 'first',
      },
    })
    require('pi.ui.renderer.flush').flush()

    assert.equal(1, #state.queued_user_messages['session-a'])
    assert.equal('second', state.queued_user_messages['session-a'][1].prompt)

    events.on_part_updated({
      part = {
        id = 'part-1',
        messageID = 'message-1',
        sessionID = 'session-a',
        type = 'text',
        text = 'first updated',
      },
    })
    require('pi.ui.renderer.flush').flush()

    assert.equal(1, #state.queued_user_messages['session-a'])
    assert.equal('second', state.queued_user_messages['session-a'][1].prompt)
  end)

  it('limits the preview and reports hidden prompts', function()
    for index = 1, 5 do
      state.session.queue_user_message('session-a', string.rep(tostring(index), 80))
    end
    assert.is_true(vim.wait(1000, function()
      return queued_messages._window() ~= nil
    end))

    local win = queued_messages._window()
    local buf = vim.api.nvim_win_get_buf(win)
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)

    assert.equal(5, #lines)
    assert.equal('Queued (5)', lines[1])
    assert.equal('…  2 more', lines[5])
    assert.is_true(lines[2]:sub(-3) == '…')
    assert.is_true(vim.fn.strdisplaywidth(lines[2]) <= vim.api.nvim_win_get_width(win))
  end)
end)
