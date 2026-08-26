local state = require('pi.state')

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

local function sanitize_id(value)
  return tostring(value):gsub('[^%w_%-]', '_')
end

local function message_id_from_message(role, message, fallback)
  if message and message.responseId and message.responseId ~= '' then
    return 'pi_msg_' .. sanitize_id(message.responseId)
  end
  if message and message.timestamp then
    return 'pi_msg_' .. sanitize_id(role or 'message') .. '_' .. sanitize_id(message.timestamp)
  end
  return fallback or next_id('pi_msg', 'message')
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

local function normalize_tool_name(name)
  name = tostring(name or 'tool')
  local lower = name:lower()
  local aliases = {
    read = 'read',
    edit = 'edit',
    write = 'write',
    bash = 'bash',
    run = 'bash',
    glob = 'glob',
    grep = 'grep',
    list = 'list',
    ls = 'list',
    question = 'question',
    todowrite = 'todowrite',
    todo_write = 'todowrite',
  }
  return aliases[lower] or lower
end

local function update_tool_part(message_id, part_id, tool_name, input, state)
  emit('message.part.updated', {
    part = {
      id = part_id,
      messageID = message_id,
      sessionID = session_id(),
      type = 'tool',
      tool = normalize_tool_name(tool_name),
      callID = state and state.callID or nil,
      state = {
        input = input or {},
        metadata = (state and state.metadata) or {},
        time = (state and state.time) or {},
        status = (state and state.status) or 'completed',
        output = state and state.output or nil,
        error = state and state.error or nil,
      },
    },
  })
end

local function tool_part_key(call_id, fallback)
  if call_id and call_id ~= '' then
    return tostring(call_id)
  end
  return fallback
end

local function ensure_tool_part(call_id, fallback, tool_name, input)
  local key = tool_part_key(call_id, fallback)
  if not key then
    return {
      id = next_id('pi_prt', 'part'),
      tool = tool_name,
      input = input or {},
      time = {},
    }
  end

  local cached = live.tool_parts[key]
  if type(cached) ~= 'table' then
    cached = {
      id = cached or next_id('pi_prt', 'part'),
      tool = tool_name,
      input = input or {},
      time = {},
    }
    live.tool_parts[key] = cached
  end

  cached.tool = tool_name or cached.tool
  if input and type(input) == 'table' and next(input) ~= nil then
    cached.input = input
  end
  return cached
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
  local message_id = message_id_from_message(role, message, 'pi_msg_' .. tostring(index))
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
        update_tool_part(message_id, part_id, item.name, item.arguments or {}, {
          callID = item.id or item.callID,
          status = 'completed',
        })
      else
        update_text_part(message_id, part_id, content_to_text({ item }), nil)
      end
    end
  else
    update_text_part(message_id, message_id .. '_part_1', content_to_text(message.content), nil)
  end
end

function M.messages_from_pi(messages)
  local converted = {}
  for i, message in ipairs(messages or {}) do
    local role = message.role == 'toolResult' and 'assistant' or message.role
    if role ~= 'user' and role ~= 'assistant' then
      role = 'assistant'
    end

    local message_id = message_id_from_message(role, message, 'pi_msg_' .. tostring(i))
    local parts = {}

    if message.role == 'toolResult' then
      table.insert(parts, {
        id = message_id .. '_part_1',
        messageID = message_id,
        sessionID = session_id(),
        type = 'text',
        text = content_to_text(message.content),
        synthetic = true,
      })
    elseif type(message.content) == 'table' then
      if #message.content == 0 and (message.stopReason == 'error' or message.stopReason == 'aborted') then
        table.insert(parts, {
          id = message_id .. '_part_1',
          messageID = message_id,
          sessionID = session_id(),
          type = 'text',
          text = 'Pi stopped: ' .. tostring(message.errorMessage or message.stopReason),
          synthetic = true,
        })
      end
      for part_index, item in ipairs(message.content) do
        local part = {
          id = message_id .. '_part_' .. tostring(part_index),
          messageID = message_id,
          sessionID = session_id(),
          type = 'text',
        }
        if item.type == 'thinking' then
          part.text = item.thinking or ''
          part.synthetic = true
        elseif item.type == 'toolCall' then
          part.type = 'tool'
          part.tool = normalize_tool_name(item.name)
          part.callID = item.id or item.callID
          part.state = {
            input = item.arguments or {},
            metadata = {},
            time = {},
            status = 'completed',
          }
        else
          part.text = content_to_text({ item })
        end
        table.insert(parts, part)
      end
    else
      table.insert(parts, {
        id = message_id .. '_part_1',
        messageID = message_id,
        sessionID = session_id(),
        type = 'text',
        text = content_to_text(message.content),
      })
    end

    table.insert(converted, {
      info = message_info(role, message_id, message),
      parts = parts,
    })
  end
  return converted
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
  live.assistant_message_id = message_id_from_message('assistant', message)
  update_message('assistant', live.assistant_message_id, message)
  return live.assistant_message_id
end

function M.handle_event(event)
  if not event or not event.type then
    return
  end

  if event.type == 'agent_start' then
    emit('session.status', { sessionID = session_id(), status = { type = 'busy', message = 'Pi is working' } })
    return
  end

  if event.type == 'agent_end' then
    emit('session.status', { sessionID = session_id(), status = { type = event.willRetry and 'retry' or 'idle' } })
    return
  end

  if event.type == 'auto_retry_start' then
    emit('session.status', {
      sessionID = session_id(),
      status = {
        type = 'retry',
        message = event.errorMessage,
        attempt = event.attempt,
        next = event.delayMs and (vim.uv.now() + event.delayMs) or nil,
      },
    })
    return
  end

  if event.type == 'auto_retry_end' and event.success == false then
    local message_id = ensure_live_assistant()
    update_text_part(message_id, next_id('pi_prt', 'part'), 'Pi retry failed: ' .. tostring(event.finalError or 'unknown error'), true)
    emit('session.status', { sessionID = session_id(), status = { type = 'idle' } })
    return
  end

  if event.type == 'compaction_start' then
    emit('session.status', { sessionID = session_id(), status = { type = 'busy', message = 'Compacting session' } })
    return
  end

  if event.type == 'compaction_end' then
    local message_id = ensure_live_assistant()
    local text = event.aborted and 'Compaction aborted' or 'Compaction complete'
    if event.errorMessage then
      text = 'Compaction failed: ' .. event.errorMessage
    elseif event.result and event.result.summary then
      text = text .. '\n\n' .. event.result.summary
    end
    update_text_part(message_id, next_id('pi_prt', 'part'), text, true)
    emit('session.status', { sessionID = session_id(), status = { type = event.willRetry and 'retry' or 'idle' } })
    return
  end

  if event.type == 'extension_error' then
    local message_id = ensure_live_assistant()
    update_text_part(message_id, next_id('pi_prt', 'part'), 'Pi extension error: ' .. tostring(event.error or 'unknown error'), true)
    return
  end

  if event.type == 'message_start' and event.message then
    if event.message.role == 'assistant' then
      live.assistant_message_id = message_id_from_message('assistant', event.message)
      live.text_parts = {}
      live.thinking_parts = {}
      live.tool_parts = {}
      update_message('assistant', live.assistant_message_id, event.message)
    elseif event.message.role == 'user' then
      local message_id = message_id_from_message('user', event.message)
      update_message('user', message_id, event.message)
      update_text_part(message_id, message_id .. '_part_1', content_to_text(event.message.content), nil)
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
      local call_id = tool.id or tool.callID
      local cached = ensure_tool_part(call_id, 'content:' .. key, tool.name, tool.arguments or {})
      update_tool_part(message_id, cached.id, tool.name, cached.input or tool.arguments or {}, {
        callID = call_id,
        time = cached.time,
        status = cached.status or 'completed',
        output = cached.output,
        error = cached.error,
        metadata = cached.metadata,
      })
    elseif delta.type == 'error' then
      update_text_part(message_id, next_id('pi_prt', 'part'), 'Pi error: ' .. tostring(delta.reason or 'unknown error'), true)
    end
    return
  end

  if event.type == 'message_end' and event.message and event.message.role == 'assistant' then
    local message_id = ensure_live_assistant(event.message)
    update_message('assistant', message_id, event.message)

    if type(event.message.content) == 'table' then
      if #event.message.content == 0 and (event.message.stopReason == 'error' or event.message.stopReason == 'aborted') then
        update_text_part(
          message_id,
          next_id('pi_prt', 'part'),
          'Pi stopped: ' .. tostring(event.message.errorMessage or event.message.stopReason),
          true
        )
      end
      for content_index, item in ipairs(event.message.content) do
        local key = tostring(content_index - 1)
        if item.type == 'text' then
          live.text_parts[key] = live.text_parts[key] or { id = next_id('pi_prt', 'part'), text = '' }
          live.text_parts[key].text = item.text or live.text_parts[key].text or ''
          update_text_part(message_id, live.text_parts[key].id, live.text_parts[key].text, nil)
        elseif item.type == 'thinking' then
          live.thinking_parts[key] = live.thinking_parts[key] or { id = next_id('pi_prt', 'part'), text = '' }
          live.thinking_parts[key].text = item.thinking or live.thinking_parts[key].text or ''
          update_text_part(message_id, live.thinking_parts[key].id, live.thinking_parts[key].text, true)
        elseif item.type == 'toolCall' then
          local call_id = item.id or item.callID
          local cached = ensure_tool_part(call_id, 'content:' .. key, item.name, item.arguments or {})
          update_tool_part(message_id, cached.id, item.name, cached.input or item.arguments or {}, {
            callID = call_id,
            time = cached.time,
            status = cached.status or 'completed',
            output = cached.output,
            error = cached.error,
            metadata = cached.metadata,
          })
        end
      end
    elseif type(event.message.content) == 'string' and event.message.content ~= '' then
      live.text_parts['0'] = live.text_parts['0'] or { id = next_id('pi_prt', 'part'), text = '' }
      live.text_parts['0'].text = event.message.content
      update_text_part(message_id, live.text_parts['0'].id, event.message.content, nil)
    elseif event.message.stopReason == 'error' or event.message.stopReason == 'aborted' then
      update_text_part(message_id, next_id('pi_prt', 'part'), 'Pi stopped: ' .. tostring(event.message.stopReason), true)
    end
    return
  end

  if event.type == 'tool_execution_start' then
    local message_id = ensure_live_assistant()
    local cached = ensure_tool_part(event.toolCallId, nil, event.toolName, event.args or {})
    cached.time = cached.time or {}
    cached.time.start = cached.time.start or vim.uv.now()
    cached.status = 'running'
    update_tool_part(message_id, cached.id, event.toolName, cached.input or event.args or {}, {
      callID = event.toolCallId,
      time = cached.time,
      status = 'running',
      output = cached.output,
      error = cached.error,
      metadata = cached.metadata,
    })
    return
  end

  if event.type == 'tool_execution_update' or event.type == 'tool_execution_end' then
    local message_id = ensure_live_assistant()
    local cached = ensure_tool_part(event.toolCallId, nil, event.toolName, event.args or {})
    local result = event.partialResult or event.result or {}
    local status = event.type == 'tool_execution_end' and 'completed' or 'running'
    if result.isError or event.error then
      status = 'error'
    end
    cached.time = cached.time or {}
    cached.time['end'] = event.type == 'tool_execution_end' and vim.uv.now() or cached.time['end']
    cached.status = status
    cached.output = content_to_text(result.content)
    cached.error = event.error or result.error
    cached.metadata = result.metadata or {}
    update_tool_part(message_id, cached.id, event.toolName or cached.tool, event.args or cached.input or {}, {
      callID = event.toolCallId,
      time = cached.time,
      status = status,
      output = cached.output,
      error = cached.error,
      metadata = cached.metadata,
    })
    if event.type == 'tool_execution_end' then
      vim.cmd('checktime')
    end
    return
  end

  if event.type == 'agent_settled' then
    emit('session.status', { sessionID = session_id(), status = { type = 'idle' } })
    emit('session.idle', { sessionID = session_id() })
    live.assistant_message_id = nil
    live.text_parts = {}
    live.thinking_parts = {}
    live.tool_parts = {}
  end
end

return M
