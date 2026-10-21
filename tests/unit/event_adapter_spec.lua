local event_adapter = require('pi.event_adapter')
local state = require('pi.state')

describe('event_adapter', function()
  local original_event_manager
  local original_active_session
  local events

  before_each(function()
    original_event_manager = state.event_manager
    original_active_session = state.active_session
    events = {}
    state.session.set_active({ id = 'ses_stream' })
    state.jobs.set_event_manager({
      throttling_emitter = {
        enqueue = function(_, event)
          table.insert(events, event)
        end,
      },
    })
  end)

  after_each(function()
    state.jobs.set_event_manager(original_event_manager)
    state.session.set_active(original_active_session)
    event_adapter.handle_event({ type = 'agent_settled' })
  end)

  it('updates the active session when the backend names it', function()
    event_adapter.handle_event({ type = 'session_info_changed', name = 'Automatic session naming' })

    assert.equal('Automatic session naming', state.active_session.title)
    assert.equal('Automatic session naming', state.active_session.description)
    assert.same({
      type = 'session.updated',
      properties = { info = state.active_session },
    }, events[1])
  end)

  it('uses one stable part id for tool planning, execution, and final message events', function()
    local tool_call = {
      id = 'call_shell_1',
      name = 'bash',
      arguments = { command = 'echo streamed-tool-once' },
    }

    event_adapter.handle_event({
      type = 'message_start',
      message = { role = 'assistant', content = {}, responseId = 'assistant_1', timestamp = 1 },
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

    local part_ids = {}
    local statuses = {}
    for _, event in ipairs(events) do
      if event.type == 'message.part.updated' and event.properties.part.type == 'tool' then
        part_ids[event.properties.part.id] = true
        table.insert(statuses, event.properties.part.state.status)
      end
    end

    assert.are.same({ completed = true, running = true }, {
      completed = vim.tbl_contains(statuses, 'completed'),
      running = vim.tbl_contains(statuses, 'running'),
    })
    assert.are.equal(1, vim.tbl_count(part_ids))
  end)
  local function reasoning_parts()
    local parts = {}
    for _, event in ipairs(events) do
      if event.type == 'message.part.updated' and event.properties.part.type == 'reasoning' then
        table.insert(parts, event.properties.part)
      end
    end
    return parts
  end

  it('emits streamed thinking as reasoning parts with one stable id', function()
    event_adapter.handle_event({
      type = 'message_start',
      message = { role = 'assistant', content = {}, responseId = 'assistant_think', timestamp = 1 },
    })
    event_adapter.handle_event({
      type = 'message_update',
      assistantMessageEvent = { type = 'thinking_start', contentIndex = 0 },
    })
    event_adapter.handle_event({
      type = 'message_update',
      assistantMessageEvent = { type = 'thinking_delta', contentIndex = 0, delta = 'pondering' },
    })
    event_adapter.handle_event({
      type = 'message_update',
      assistantMessageEvent = { type = 'text_start', contentIndex = 1 },
    })
    event_adapter.handle_event({
      type = 'message_update',
      assistantMessageEvent = { type = 'text_delta', contentIndex = 1, delta = 'answer' },
    })
    event_adapter.handle_event({
      type = 'message_end',
      message = {
        role = 'assistant',
        content = {
          { type = 'thinking', thinking = 'pondering deeply' },
          { type = 'text', text = 'answer' },
        },
        responseId = 'assistant_think',
        timestamp = 1,
      },
    })

    local parts = reasoning_parts()
    local ids = {}
    for _, part in ipairs(parts) do
      ids[part.id] = true
      assert.is_nil(part.synthetic)
    end
    assert.are.equal(1, vim.tbl_count(ids))
    assert.are.equal('pondering', parts[2].text)
    assert.are.equal('pondering deeply', parts[#parts].text)

    for _, event in ipairs(events) do
      local part = event.properties and event.properties.part
      if part and part.type == 'text' then
        assert.is_falsy(part.text:find('pondering', 1, true))
      end
    end
  end)

  it('converts thinking from history into reasoning parts', function()
    local messages = event_adapter.messages_from_pi({
      {
        role = 'assistant',
        responseId = 'assistant_hist',
        timestamp = 1,
        content = {
          { type = 'thinking', thinking = 'hidden thoughts' },
          { type = 'text', text = 'visible answer' },
        },
      },
    })

    local parts = messages[1].parts
    assert.are.equal('reasoning', parts[1].type)
    assert.are.equal('hidden thoughts', parts[1].text)
    assert.is_nil(parts[1].synthetic)
    assert.are.equal('text', parts[2].type)
    assert.are.equal('visible answer', parts[2].text)
  end)

  it('emits thinking from full messages as reasoning parts', function()
    event_adapter.emit_messages({
      {
        role = 'assistant',
        responseId = 'assistant_full',
        timestamp = 1,
        content = {
          { type = 'thinking', thinking = 'full thoughts' },
          { type = 'text', text = 'full answer' },
        },
      },
    })

    local parts = reasoning_parts()
    assert.are.equal(1, #parts)
    assert.are.equal('full thoughts', parts[1].text)
  end)

  describe('reset_live', function()
    local function tool_events()
      return vim.tbl_filter(function(event)
        return event.type == 'message.part.updated' and event.properties.part.type == 'tool'
      end, events)
    end

    local function run_tool(id)
      event_adapter.handle_event({ type = 'tool_execution_start', toolCallId = id, toolName = 'bash', args = {} })
      event_adapter.handle_event({
        type = 'tool_execution_end',
        toolCallId = id,
        toolName = 'bash',
        args = {},
        result = { content = 'out' },
      })
    end

    it('ignores tool events for a message started before the reset', function()
      event_adapter.handle_event({
        type = 'message_start',
        message = { role = 'assistant', content = {}, responseId = 'before_reset', timestamp = 1 },
      })
      event_adapter.reset_live()
      events = {}

      run_tool('call_after_reset')

      assert.are.equal(0, #tool_events())
      assert.are.equal(0, #vim.tbl_filter(function(event)
        return event.type == 'message.updated'
      end, events))
    end)

    it('handles tool events again once a new assistant message starts', function()
      event_adapter.reset_live()
      event_adapter.handle_event({
        type = 'message_start',
        message = { role = 'assistant', content = {}, responseId = 'after_reset', timestamp = 2 },
      })

      run_tool('call_new_message')

      local parts = tool_events()
      assert.is_true(#parts > 0)
      assert.are.equal('pi_msg_after_reset', parts[1].properties.part.messageID)
    end)

    it('streams text into a fresh part after the reset', function()
      event_adapter.handle_event({
        type = 'message_start',
        message = { role = 'assistant', content = {}, responseId = 'old', timestamp = 3 },
      })
      event_adapter.handle_event({
        type = 'message_update',
        assistantMessageEvent = { type = 'text_delta', contentIndex = 0, delta = 'old text ' },
      })
      event_adapter.reset_live()
      event_adapter.handle_event({
        type = 'message_start',
        message = { role = 'assistant', content = {}, responseId = 'new', timestamp = 4 },
      })
      event_adapter.handle_event({
        type = 'message_update',
        assistantMessageEvent = { type = 'text_delta', contentIndex = 0, delta = 'new' },
      })

      local last = events[#events].properties.part
      assert.are.equal('pi_msg_new', last.messageID)
      assert.are.equal('new', last.text)
    end)
  end)
end)
