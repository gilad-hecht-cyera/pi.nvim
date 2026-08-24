local state = require('opencode.state')

local M = {}

local counters = { message = 0, part = 0, session = 0 }
local live = { assistant_message_id = nil, text_parts = {}, thinking_parts = {}, tool_parts = {} }

local function next_id(prefix, key)
  counters[key] = (counters[key] or 0) + 1
  return prefix .. '_' .. tostring(counters[key])
end

local function session_id()
  if state.active_session and state.active_session.id then
    return state.active_session.id
  end
  return 'pi_session'
end

local function emit(event_type, properties)
  if state.event_manager then
    state.event_manager.throttling_emitter:enqueue({ type = event_type, properties = properties })
  end
end

local function message_info(role, id, message)
  return {
    id = id,
    role = role,
    sessionID = session_id(),
    providerID = message and message.provider,
    modelID = message and message.model,
    time = { created = message and message.timestamp or vim.uv.now() },
  }
end

local function update_message(role, id, message)
  emit('message.updated', { info = message_info(role, id, message) })
end

local function update_text_part(message_id, part_id, text, synthetic)
  emit('message.part.updated', {
    part = {
      id = part_id,
      messageID = message_id,
      sessionID = session_id(),
      type = 'text',
      text = text or '',
      synthetic = synthetic or nil,
    },
  })
end

local function content_to_text(content)
  if type(content) == 'string' then
    return content
  end
  if type(content) ~= 'table' then
    return tostring(content or '')
  end
  local chunks = {}
  for _, item in ipairs(content) do
    if type(item) == 'string' then
      table.insert(chunks, item)
    elseif item.type == 'text' then
      table.insert(chunks, item.text or '')
    elseif item.type == 'thinking' then
      table.insert(chunks, item.thinking or '')
    elseif item.type == 'toolCall' then
      table.insert(chunks, string.format('Called %s with %s', item.name or 'tool', vim.json.encode(item.arguments or {})))
    elseif item.type == 'image' then
      table.insert(chunks, '[image]')
    end
  end
  return table.concat(chunks, '\n')
end

local function emit_full_message(message, index)
  local role = message.role == 'toolResult' and 'assistant' or message.role
  if role ~= 'user' and role ~= 'assistant' then
    role = 'assistant'
  end
  local message_id = 'pi_msg_' .. tostring(index)
  update_message(role, message_id, message)

  if message.role == 'toolResult' then
    update_text_part(message_id, message_id .. '_part_1', content_to_text(message.content), true)
    return
  end

  if type(message.content) == 'table' then
    for i, item in ipairs(message.content) do
      local part_id = message_id .. '_part_' .. tostring(i)
      if item.type == 'thinking' then
        update_text_part(message_id, part_id, item.thinking or '', true)
      elseif item.type == 'toolCall' then
        update_text_part(message_id, part_id, string.format('Called %s with %s', item.name or 'tool', vim.json.encode(item.arguments or {})), true)
      else
        update_text_part(message_id, part_id, content_to_text({ item }), nil)
      end
    end
  else
    update_text_part(message_id, message_id .. '_part_1', content_to_text(message.content), nil)
  end
end

function M.emit_messages(messages)
  for i, message in ipairs(messages or {}) do
    emit_full_message(message, i)
  end
end

local function ensure_live_assistant(message)
  if live.assistant_message_id then
    return live.assistant_message_id
  end
  live.assistant_message_id = next_id('pi_msg', 'message')
  update_message('assistant', live.assistant_message_id, message)
  return live.assistant_message_id
end

function M.handle_event(event)
  if not event or not event.type then
    return
  end

  if event.type == 'message_start' and event.message then
    if event.message.role == 'assistant' then
      live.assistant_message_id = next_id('pi_msg', 'message')
      live.text_parts = {}
      live.thinking_parts = {}
      update_message('assistant', live.assistant_message_id, event.message)
    elseif event.message.role == 'user' then
      local message_id = next_id('pi_msg', 'message')
      update_message('user', message_id, event.message)
      update_text_part(message_id, next_id('pi_prt', 'part'), content_to_text(event.message.content), nil)
    end
    return
  end

  if event.type == 'message_update' then
    local delta = event.assistantMessageEvent or {}
    local message_id = ensure_live_assistant(event.message)
    local key = tostring(delta.contentIndex or 0)
    if delta.type == 'text_start' then
      live.text_parts[key] = { id = next_id('pi_prt', 'part'), text = '' }
      update_text_part(message_id, live.text_parts[key].id, '', nil)
    elseif delta.type == 'text_delta' then
      live.text_parts[key] = live.text_parts[key] or { id = next_id('pi_prt', 'part'), text = '' }
      live.text_parts[key].text = live.text_parts[key].text .. (delta.delta or '')
      update_text_part(message_id, live.text_parts[key].id, live.text_parts[key].text, nil)
    elseif delta.type == 'thinking_start' then
      live.thinking_parts[key] = { id = next_id('pi_prt', 'part'), text = '' }
      update_text_part(message_id, live.thinking_parts[key].id, '', true)
    elseif delta.type == 'thinking_delta' then
      live.thinking_parts[key] = live.thinking_parts[key] or { id = next_id('pi_prt', 'part'), text = '' }
      live.thinking_parts[key].text = live.thinking_parts[key].text .. (delta.delta or '')
      update_text_part(message_id, live.thinking_parts[key].id, live.thinking_parts[key].text, true)
    elseif delta.type == 'toolcall_end' and delta.toolCall then
      local tool = delta.toolCall
      update_text_part(message_id, next_id('pi_prt', 'part'), string.format('Called %s with %s', tool.name or 'tool', vim.json.encode(tool.arguments or {})), true)
    end
    return
  end

  if event.type == 'tool_execution_start' then
    local message_id = ensure_live_assistant()
    live.tool_parts[event.toolCallId] = next_id('pi_prt', 'part')
    update_text_part(message_id, live.tool_parts[event.toolCallId], string.format('Running %s with %s', event.toolName or 'tool', vim.json.encode(event.args or {})), true)
    return
  end

  if event.type == 'tool_execution_update' or event.type == 'tool_execution_end' then
    local message_id = ensure_live_assistant()
    local part_id = live.tool_parts[event.toolCallId] or next_id('pi_prt', 'part')
    live.tool_parts[event.toolCallId] = part_id
    local result = event.partialResult or event.result or {}
    update_text_part(message_id, part_id, content_to_text(result.content), true)
    if event.type == 'tool_execution_end' then
      vim.cmd('checktime')
    end
    return
  end

  if event.type == 'agent_settled' then
    emit('session.idle', { sessionID = session_id() })
    live.assistant_message_id = nil
    live.text_parts = {}
    live.thinking_parts = {}
    live.tool_parts = {}
  end
end

return M
