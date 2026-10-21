local state = require('pi.state')
local ui = require('pi.ui.ui')
local helpers = require('tests.helpers')
local output_window = require('pi.ui.output_window')
local assert = require('luassert')
local stub = require('luassert.stub')
local config = require('pi.config')

describe('renderer unit tests', function()
  local function event_subscriptions()
    local names = {}
    for _, sub in ipairs(require('pi.ui.renderer').event_subscriptions()) do
      table.insert(names, sub[1])
    end
    return names
  end

  before_each(function()
    require('pi.event_manager').setup()
  end)

  it('subsribes to events correctly', function()
    local renderer = require('pi.ui.renderer')
    local event_manager = state.event_manager

    event_manager.events = {}

    renderer.setup_subscriptions()

    for _, event_name in ipairs(event_subscriptions()) do
      assert.is_true(
        event_manager.events[event_name] ~= nil,
        string.format('Renderer did not subscribe to event: %s', event_name)
      )
    end
  end)

  it('subscribes to file watcher updates for reference target invalidation', function()
    assert(vim.tbl_contains(event_subscriptions(), 'file.watcher.updated'))
    assert.is_true(require('pi.ui.event_scope').should_handle('file.watcher.updated', {
      file = 'src/ok.lua',
      event = 'unlink',
    }))
  end)

  it('unsubsribes from events correctly', function()
    local renderer = require('pi.ui.renderer')
    local event_manager = state.event_manager

    renderer.setup_subscriptions()

    renderer.setup_subscriptions(false)

    for _, event_name in ipairs(event_subscriptions()) do
      assert.is_true(
        vim.tbl_isempty(event_manager.events[event_name]),
        string.format('Renderer did not unsubscribe from event: %s', event_name)
      )
    end
  end)

  it('captures stable output window state', function()
    helpers.replay_setup()

    output_window.set_lines({ 'one', 'two', 'three' })
    vim.api.nvim_win_set_cursor(state.windows.output_win, { 2, 0 })

    local actual = helpers.capture_output(state.windows.output_buf, output_window.namespace)
    local window_keys = vim.tbl_keys(actual.window)
    table.sort(window_keys)

    assert.are.same({ 'cursor', 'effective_bottom', 'line_count', 'visible_bottom' }, window_keys)
    assert.are.same({ 2, 0 }, actual.window.cursor)
    assert.are.equal(3, actual.window.visible_bottom)
    assert.are.equal(3, actual.window.line_count)
    assert.are.equal(3, actual.window.effective_bottom)

    local existing_file = vim.fn.tempname()
    local file = assert(io.open(existing_file, 'w'))
    file:write(vim.json.encode({ timestamp = 123 }))
    file:close()

    local snapshot = helpers.output_snapshot(state.windows.output_buf, output_window.namespace, existing_file)
    vim.fn.delete(existing_file)

    assert.are.equal(123, snapshot.timestamp)
    assert.are.same(actual.window, snapshot.window)

    local existing_without_timestamp = vim.fn.tempname()
    file = assert(io.open(existing_without_timestamp, 'w'))
    file:write(vim.json.encode({ lines = {} }))
    file:close()

    local snapshot_without_timestamp =
      helpers.output_snapshot(state.windows.output_buf, output_window.namespace, existing_without_timestamp)
    vim.fn.delete(existing_without_timestamp)

    assert.is_nil(snapshot_without_timestamp.timestamp)

    ui.close_windows(state.windows)
  end)

  it('updates active session title from session.updated event', function()
    local renderer = require('pi.ui.renderer')
    local topbar = require('pi.ui.topbar')

    state.session.set_active({
      id = 'ses_123',
      title = 'New session - 2026-02-05T22:26:08.579Z',
      time = { created = 1, updated = 1 },
    })

    local active_session_ref = state.active_session

    renderer.on_session_updated({
      info = {
        id = 'ses_123',
        title = 'Branch review request',
        time = { created = 1, updated = 2 },
      },
    })

    assert.are.equal('Branch review request', state.active_session.title)
  end)

  it('rerenders full session when revert changes', function()
    local renderer = require('pi.ui.renderer')

    state.renderer.set_messages({})
    state.session.set_active({
      id = 'ses_123',
      title = 'Session',
      time = { created = 1, updated = 1 },
      revert = { messageID = 'msg_1', snapshot = 'a', diff = '' },
    })

    local render_stub = stub(renderer, '_render_full_session_data')

    renderer.on_session_updated({
      info = {
        id = 'ses_123',
        title = 'Session',
        time = { created = 1, updated = 2 },
        revert = { messageID = 'msg_2', snapshot = 'b', diff = '' },
      },
    })

    assert.stub(render_stub).was_called_with(state.messages)
    render_stub:revert()
  end)

  it('refreshes the full session when compacted', function()
    local renderer = require('pi.ui.renderer')
    local events = require('pi.ui.renderer.events')

    state.session.set_active({
      id = 'ses_123',
      title = 'Session',
      time = { created = 1, updated = 1 },
    })

    local render_stub = stub(renderer, 'render_full_session')

    events.on_session_compacted()

    assert.stub(render_stub).was_called(1)
    render_stub:revert()
  end)

  it('render_output and render_lines do not write targets into RenderState', function()
    local renderer = require('pi.ui.renderer')
    local ctx = require('pi.ui.renderer.ctx')
    local Output = require('pi.ui.output')

    helpers.replay_setup()
    local add_targets_stub = stub(ctx.render_state, 'add_targets')
    local clear_targets_stub = stub(ctx.render_state, 'clear_targets')

    local output = Output.new()
    output:add_line('open README.md')
    output:add_extmark(0, { hl_group = 'PiReference', start_col = 5, end_col = 14 })
    output:add_fold(1, 1)
    output:add_target({
      kind = 'file',
      path = 'README.md',
      range = { line = 1, start_col = 5, end_col = 14 },
    })

    renderer.render_output(output)
    renderer.render_lines({ 'display only' })

    local lines = vim.api.nvim_buf_get_lines(state.windows.output_buf, 0, -1, false)

    add_targets_stub:revert()
    clear_targets_stub:revert()
    ui.close_windows(state.windows)

    assert.are.same({ 'display only' }, lines)
    assert.stub(add_targets_stub).was_not_called()
    assert.stub(clear_targets_stub).was_not_called()
  end)

  it('inserts a single synthetic revert message during full session render', function()
    local renderer = require('pi.ui.renderer')

    helpers.replay_setup()

    state.session.set_active({
      id = 'ses_123',
      title = 'Session',
      time = { created = 1, updated = 1 },
      revert = { messageID = 'msg_1', snapshot = 'a', diff = '' },
    })

    renderer._render_full_session_data({
      {
        info = {
          id = 'msg_1',
          role = 'assistant',
          sessionID = 'ses_123',
        },
        parts = {},
      },
    })

    local revert_messages = vim.tbl_filter(function(message)
      return message.info and message.info.id == '__pi_revert_message__'
    end, state.messages or {})

    assert.are.equal(1, #revert_messages)
  end)

  it('renders live Pi messages after existing history without ID collisions', function()
    local renderer = require('pi.ui.renderer')
    local event_adapter = require('pi.event_adapter')

    helpers.replay_setup()

    state.session.set_active({
      id = 'ses_stream',
      title = 'Session',
      time = { created = 1, updated = 1 },
    })
    renderer.setup_subscriptions(true)
    renderer._render_full_session_data(event_adapter.messages_from_pi({
      { role = 'user', content = { { type = 'text', text = 'old history' } }, timestamp = 1000 },
      { role = 'assistant', content = { { type = 'text', text = 'old answer' } }, timestamp = 1001 },
    }))

    event_adapter.handle_event({
      type = 'message_start',
      message = { role = 'user', content = 'new live message', timestamp = 2000 },
    })
    state.event_manager.throttling_emitter:_drain()

    local lines = table.concat(vim.api.nvim_buf_get_lines(state.windows.output_buf, 0, -1, false), '\n')
    assert.is_truthy(lines:find('old history', 1, true))
    assert.is_truthy(lines:find('new live message', 1, true))
  end)

  it('flushes streamed events when the event batch finishes', function()
    local renderer = require('pi.ui.renderer')
    local event_adapter = require('pi.event_adapter')

    helpers.replay_setup()

    state.session.set_active({
      id = 'ses_stream',
      title = 'Session',
      time = { created = 1, updated = 1 },
    })
    renderer.setup_subscriptions(true)

    event_adapter.handle_event({
      type = 'message_start',
      message = { role = 'user', content = 'streamed message visible', timestamp = 1 },
    })
    state.event_manager.throttling_emitter:_drain()

    local lines = table.concat(vim.api.nvim_buf_get_lines(state.windows.output_buf, 0, -1, false), '\n')
    assert.is_truthy(lines:find('streamed message visible', 1, true))
  end)

  it('does not duplicate a streamed tool across planning, execution, and final message events', function()
    local renderer = require('pi.ui.renderer')
    local event_adapter = require('pi.event_adapter')

    helpers.replay_setup()

    state.session.set_active({
      id = 'ses_stream',
      title = 'Session',
      time = { created = 1, updated = 1 },
    })
    renderer.setup_subscriptions(true)

    local tool_call = {
      id = 'call_shell_1',
      name = 'bash',
      arguments = { command = 'echo streamed-tool-once' },
    }

    event_adapter.handle_event({
      type = 'message_start',
      message = {
        role = 'assistant',
        content = {},
        responseId = 'assistant_1',
        timestamp = 1,
      },
    })
    event_adapter.handle_event({
      type = 'message_update',
      assistantMessageEvent = { type = 'toolcall_end', contentIndex = 0, toolCall = tool_call },
    })
    event_adapter.handle_event({
      type = 'tool_execution_start',
      toolCallId = 'call_shell_1',
      toolName = 'bash',
      args = tool_call.arguments,
    })
    event_adapter.handle_event({
      type = 'tool_execution_end',
      toolCallId = 'call_shell_1',
      toolName = 'bash',
      args = tool_call.arguments,
      result = { content = 'streamed-tool-once\n' },
    })
    event_adapter.handle_event({
      type = 'message_end',
      message = {
        role = 'assistant',
        content = {
          {
            type = 'toolCall',
            id = 'call_shell_1',
            name = 'bash',
            arguments = tool_call.arguments,
          },
        },
        responseId = 'assistant_1',
        timestamp = 1,
      },
    })
    state.event_manager.throttling_emitter:_drain()

    local lines = table.concat(vim.api.nvim_buf_get_lines(state.windows.output_buf, 0, -1, false), '\n')
    local _, run_count = lines:gsub('%*%*.- run%*%*', '')
    assert.are.equal(1, run_count)
  end)

  it('supports output target navigation from a replayed assistant file reference', function()
    local renderer = require('pi.ui.renderer')
    local navigation = require('pi.ui.navigation')

    helpers.replay_setup()

    local code_buf = vim.api.nvim_create_buf(false, true)
    local code_win = vim.api.nvim_open_win(code_buf, false, {
      relative = 'editor',
      width = 40,
      height = 8,
      row = 0,
      col = 0,
    })

    state.ui.set_last_code_window(code_win)
    local path = 'lua/pi/ui/navigation.lua'
    local test_root = vim.fn.tempname()
    local absolute_path = test_root .. '/' .. path
    vim.fn.mkdir(vim.fn.fnamemodify(absolute_path, ':h'), 'p')
    local file = assert(io.open(absolute_path, 'w'))
    file:write('abc')
    file:close()

    local original_getcwd = vim.fn.getcwd
    vim.fn.getcwd = function()
      return test_root
    end
    vim.api.nvim_buf_set_name(code_buf, absolute_path)
    vim.api.nvim_buf_set_lines(code_buf, 0, -1, false, { 'abc' })
    local events = helpers.load_test_data('tests/data/output-target-navigation.json')
    state.session.set_active(helpers.get_session_from_events(events, true))
    local session_data = helpers.load_session_from_events(events)
    local ok, err = pcall(function()
      renderer._render_full_session_data(session_data)

      local lines = vim.api.nvim_buf_get_lines(state.windows.output_buf, 0, -1, false)
      local target_line, target_col
      for idx, line in ipairs(lines) do
        local col = line:find(path, 1, true)
        if col then
          target_line = idx
          target_col = col - 1
          break
        end
      end

      assert.is_not_nil(target_line, 'replayed output did not contain file reference')
      vim.api.nvim_set_current_win(state.windows.output_win)
      vim.api.nvim_win_set_cursor(state.windows.output_win, { target_line, target_col })

      navigation.jump_to_target_at_cursor()

      assert.equals(code_win, vim.api.nvim_get_current_win())
      assert.matches(path .. '$', vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(code_win)))
      assert.same({ 1, 2 }, vim.api.nvim_win_get_cursor(code_win))
    end)

    vim.fn.getcwd = original_getcwd
    pcall(vim.api.nvim_win_close, code_win, true)
    pcall(vim.api.nvim_buf_delete, code_buf, { force = true })
    pcall(vim.fn.delete, test_root, 'rf')
    if not ok then
      error(err)
    end
  end)

  it('renders reference-scoped symbol highlights through full session replay', function()
    local renderer = require('pi.ui.renderer')
    local symbol_snapshot = require('pi.ui.symbol_snapshot')
    local events = helpers.load_test_data('tests/data/symbol-reference-navigation.json')
    local referenced_file = 'lua/pi/ui/symbol_snapshot.lua'
    local cycle = { id = 'cycle' }
    local new_cycle_stub = stub(symbol_snapshot, 'new_cycle').returns(cycle)
    local targets_for_token_stub = stub(symbol_snapshot, 'targets_for_token').invokes(
      function(received_cycle, token, candidate_files)
        assert.are.equal(cycle, received_cycle)
        if token ~= 'collect' then
          return {}
        end
        assert.are.equal(1, #candidate_files)
        assert.matches(referenced_file .. '$', candidate_files[1])
        return {
          {
            path = candidate_files[1],
            line = 1,
            col = 10,
            token = token,
          },
        }
      end
    )

    helpers.replay_setup()
    local original_filereadable = vim.fn.filereadable
    vim.fn.filereadable = function(path)
      if path:match(referenced_file .. '$') then
        return 1
      end
      return original_filereadable(path)
    end
    state.session.set_active(helpers.get_session_from_events(events, true))
    renderer._render_full_session_data(helpers.load_session_from_events(events))

    local actual = helpers.capture_output(state.windows.output_buf, output_window.namespace)
    local symbol_mark
    for _, mark in ipairs(actual.extmarks) do
      if mark[4] and mark[4].hl_group == 'PiSymbolReference' then
        symbol_mark = mark
        break
      end
    end

    new_cycle_stub:revert()
    targets_for_token_stub:revert()
    vim.fn.filereadable = original_filereadable

    assert.is_not_nil(symbol_mark)
  end)

  it('limits rendered messages and inserts a hidden-messages notice', function()
    local renderer = require('pi.ui.renderer')

    helpers.replay_setup()
    config.ui.output.max_messages = 2

    state.session.set_active({
      id = 'ses_123',
      title = 'Session',
      time = { created = 1, updated = 1 },
    })

    renderer._render_full_session_data({
      {
        info = { id = 'msg_1', role = 'user', sessionID = 'ses_123', time = { created = 1 } },
        parts = {
          { id = 'part_1', messageID = 'msg_1', sessionID = 'ses_123', type = 'text', text = 'first' },
        },
      },
      {
        info = { id = 'msg_2', role = 'assistant', sessionID = 'ses_123', time = { created = 2 } },
        parts = {
          { id = 'part_2', messageID = 'msg_2', sessionID = 'ses_123', type = 'text', text = 'second' },
        },
      },
      {
        info = { id = 'msg_3', role = 'assistant', sessionID = 'ses_123', time = { created = 3 } },
        parts = {
          { id = 'part_3', messageID = 'msg_3', sessionID = 'ses_123', type = 'text', text = 'third' },
        },
      },
    })

    assert.is_not_nil(renderer.get_rendered_message('__pi_hidden_messages_notice__'))
    assert.is_nil(renderer.get_rendered_message('msg_1'))
    assert.is_not_nil(renderer.get_rendered_message('msg_2'))
    assert.is_not_nil(renderer.get_rendered_message('msg_3'))

    local lines = vim.api.nvim_buf_get_lines(state.windows.output_buf, 0, -1, false)
    assert.are.equal('> 1 older message is not displayed.', lines[1])

    config.ui.output.max_messages = nil
  end)

  it('evicts the oldest rendered message during streaming updates', function()
    local renderer = require('pi.ui.renderer')
    local events = require('pi.ui.renderer.events')
    local flush = require('pi.ui.renderer.flush')

    helpers.replay_setup()
    config.ui.output.max_messages = 2

    state.session.set_active({
      id = 'ses_123',
      title = 'Session',
      time = { created = 1, updated = 1 },
    })
    state.renderer.set_messages({
      {
        info = { id = 'msg_1', role = 'user', sessionID = 'ses_123', time = { created = 1 } },
        parts = {
          { id = 'part_1', messageID = 'msg_1', sessionID = 'ses_123', type = 'text', text = 'first' },
        },
      },
      {
        info = { id = 'msg_2', role = 'assistant', sessionID = 'ses_123', time = { created = 2 } },
        parts = {
          { id = 'part_2', messageID = 'msg_2', sessionID = 'ses_123', type = 'text', text = 'second' },
        },
      },
    })

    renderer._render_full_session_data(state.messages)

    events.on_message_updated({
      info = { id = 'msg_3', role = 'assistant', sessionID = 'ses_123', time = { created = 3 } },
      parts = {},
    })
    events.on_part_updated({
      part = { id = 'part_3', messageID = 'msg_3', sessionID = 'ses_123', type = 'text', text = 'third' },
    })
    flush.flush()

    assert.is_nil(renderer.get_rendered_message('msg_1'))
    assert.is_not_nil(renderer.get_rendered_message('msg_2'))
    assert.is_not_nil(renderer.get_rendered_message('msg_3'))

    local lines = vim.api.nvim_buf_get_lines(state.windows.output_buf, 0, -1, false)
    assert.are.equal('> 1 older message is not displayed.', lines[1])

    config.ui.output.max_messages = nil
  end)

  it('updates the hidden-messages notice when an older hidden message is removed', function()
    local renderer = require('pi.ui.renderer')
    local events = require('pi.ui.renderer.events')
    local flush = require('pi.ui.renderer.flush')

    helpers.replay_setup()
    config.ui.output.max_messages = 2

    state.session.set_active({
      id = 'ses_123',
      title = 'Session',
      time = { created = 1, updated = 1 },
    })

    renderer._render_full_session_data({
      {
        info = { id = 'msg_1', role = 'user', sessionID = 'ses_123', time = { created = 1 } },
        parts = {
          { id = 'part_1', messageID = 'msg_1', sessionID = 'ses_123', type = 'text', text = 'first' },
        },
      },
      {
        info = { id = 'msg_2', role = 'assistant', sessionID = 'ses_123', time = { created = 2 } },
        parts = {
          { id = 'part_2', messageID = 'msg_2', sessionID = 'ses_123', type = 'text', text = 'second' },
        },
      },
      {
        info = { id = 'msg_3', role = 'assistant', sessionID = 'ses_123', time = { created = 3 } },
        parts = {
          { id = 'part_3', messageID = 'msg_3', sessionID = 'ses_123', type = 'text', text = 'third' },
        },
      },
      {
        info = { id = 'msg_4', role = 'assistant', sessionID = 'ses_123', time = { created = 4 } },
        parts = {
          { id = 'part_4', messageID = 'msg_4', sessionID = 'ses_123', type = 'text', text = 'fourth' },
        },
      },
    })

    events.on_message_removed({ sessionID = 'ses_123', messageID = 'msg_1' })
    flush.flush()

    local lines = vim.api.nvim_buf_get_lines(state.windows.output_buf, 0, -1, false)
    assert.are.equal('> 1 older message is not displayed.', lines[1])

    config.ui.output.max_messages = nil
  end)

  it('updates the hidden-messages notice count after multiple hidden removals', function()
    local renderer = require('pi.ui.renderer')
    local events = require('pi.ui.renderer.events')
    local flush = require('pi.ui.renderer.flush')

    helpers.replay_setup()
    config.ui.output.max_messages = 2

    state.session.set_active({
      id = 'ses_123',
      title = 'Session',
      time = { created = 1, updated = 1 },
    })

    renderer._render_full_session_data({
      {
        info = { id = 'msg_1', role = 'user', sessionID = 'ses_123', time = { created = 1 } },
        parts = {
          { id = 'part_1', messageID = 'msg_1', sessionID = 'ses_123', type = 'text', text = 'first' },
        },
      },
      {
        info = { id = 'msg_2', role = 'assistant', sessionID = 'ses_123', time = { created = 2 } },
        parts = {
          { id = 'part_2', messageID = 'msg_2', sessionID = 'ses_123', type = 'text', text = 'second' },
        },
      },
      {
        info = { id = 'msg_3', role = 'assistant', sessionID = 'ses_123', time = { created = 3 } },
        parts = {
          { id = 'part_3', messageID = 'msg_3', sessionID = 'ses_123', type = 'text', text = 'third' },
        },
      },
      {
        info = { id = 'msg_4', role = 'assistant', sessionID = 'ses_123', time = { created = 4 } },
        parts = {
          { id = 'part_4', messageID = 'msg_4', sessionID = 'ses_123', type = 'text', text = 'fourth' },
        },
      },
    })

    events.on_message_removed({ sessionID = 'ses_123', messageID = 'msg_1' })
    flush.flush()

    local lines = vim.api.nvim_buf_get_lines(state.windows.output_buf, 0, -1, false)
    assert.are.equal('> 1 older message is not displayed.', lines[1])

    events.on_message_removed({ sessionID = 'ses_123', messageID = 'msg_2' })
    flush.flush()

    lines = vim.api.nvim_buf_get_lines(state.windows.output_buf, 0, -1, false)
    assert.are.equal('----', lines[1])

    config.ui.output.max_messages = nil
  end)

  it('ignores session.updated for non-active session IDs', function()
    local renderer = require('pi.ui.renderer')

    state.session.set_active({
      id = 'ses_123',
      title = 'Session',
      time = { created = 1, updated = 1 },
    })

    local render_stub = stub(renderer, '_render_full_session_data')

    renderer.on_session_updated({
      info = {
        id = 'ses_999',
        title = 'Should not apply',
      },
    })

    assert.are.equal('Session', state.active_session.title)
    assert.stub(render_stub).was_not_called()
    render_stub:revert()
  end)
end)
