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
end)
