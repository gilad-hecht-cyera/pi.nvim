local Promise = require('pi.promise')
local PiProcess = require('pi.pi_process')
local event_adapter = require('pi.event_adapter')

local RpcClient = {}
RpcClient.__index = RpcClient

local instance
local request_counter = 0

local function next_request_id()
  request_counter = request_counter + 1
  return 'nvim-' .. tostring(request_counter)
end

function RpcClient.new()
  local self = setmetatable({
    process = PiProcess.get(),
    pending = {},
    streaming = false,
  }, RpcClient)

  self.process:on_event(function(event)
    self:_handle_event(event)
  end)

  return self
end

function RpcClient.get()
  if not instance then
    instance = RpcClient.new()
  end
  return instance
end

local function notify_type(level)
  if level == 'error' then
    return vim.log.levels.ERROR
  elseif level == 'warning' then
    return vim.log.levels.WARN
  end
  return vim.log.levels.INFO
end

function RpcClient:_refresh_session_stats()
  self:get_session_stats():and_then(function(stats)
    local ok, state = pcall(require, 'pi.state')
    if ok and state.renderer and state.renderer.set_session_stats then
      state.renderer.set_session_stats(stats)
    end
  end):catch(function(_)
  end)
end

function RpcClient:_handle_extension_ui_request(event)
  local method = event.method
  if method == 'notify' then
    vim.notify(event.message or '', notify_type(event.notifyType))
    return
  elseif method == 'set_editor_text' then
    local ok, input_window = pcall(require, 'pi.ui.input_window')
    if ok and input_window.set_content then
      input_window.set_content(event.text or '')
    end
    return
  elseif method == 'setTitle' then
    if event.title and event.title ~= '' then
      vim.opt.titlestring = event.title
      vim.opt.title = true
    end
    return
  elseif method == 'setStatus' then
    local ok, state = pcall(require, 'pi.state')
    if ok and state.ui and state.ui.set_extension_status then
      state.ui.set_extension_status(event.statusKey, event.statusText)
    end
    return
  elseif method == 'setWidget' then
    return
  end

  if method == 'select' then
    vim.ui.select(event.options or {}, { prompt = event.title or 'Pi' }, function(choice)
      if choice == nil then
        self:notify({ type = 'extension_ui_response', id = event.id, cancelled = true })
      else
        self:notify({ type = 'extension_ui_response', id = event.id, value = choice })
      end
    end)
  elseif method == 'confirm' then
    local choices = { 'Yes', 'No' }
    vim.ui.select(choices, { prompt = event.title or event.message or 'Confirm' }, function(choice)
      if choice == nil then
        self:notify({ type = 'extension_ui_response', id = event.id, cancelled = true })
      else
        self:notify({ type = 'extension_ui_response', id = event.id, confirmed = choice == 'Yes' })
      end
    end)
  elseif method == 'input' then
    vim.ui.input({ prompt = event.title or 'Input', default = event.default or '', completion = event.completion }, function(value)
      if value == nil then
        self:notify({ type = 'extension_ui_response', id = event.id, cancelled = true })
      else
        self:notify({ type = 'extension_ui_response', id = event.id, value = value })
      end
    end)
  elseif method == 'editor' then
    vim.ui.input({ prompt = event.title or 'Edit', default = event.prefill or '' }, function(value)
      if value == nil then
        self:notify({ type = 'extension_ui_response', id = event.id, cancelled = true })
      else
        self:notify({ type = 'extension_ui_response', id = event.id, value = value })
      end
    end)
  end
end

function RpcClient:_handle_event(event)
  if event.type == 'response' and event.id and self.pending[event.id] then
    local promise = self.pending[event.id]
    self.pending[event.id] = nil
    if event.success == false then
      promise:reject(event.error or event)
    else
      promise:resolve(event.data ~= nil and event.data or event)
    end
    return
  end

  if event.type == 'extension_ui_request' then
    self:_handle_extension_ui_request(event)
    event_adapter.handle_event(event)
    return
  end

  if event.type == 'agent_start' then
    self.streaming = true
  elseif event.type == 'agent_settled' then
    self.streaming = false
    self:_refresh_session_stats()
  elseif event.type == 'message_end' and event.message and event.message.usage then
    local usage = event.message.usage
    local ok, state = pcall(require, 'pi.state')
    if ok and state.renderer then
      local total = usage.totalTokens
        or ((usage.input or 0) + (usage.output or 0) + (usage.cacheRead or 0) + (usage.cacheWrite or 0))
      state.renderer.set_stats(total, usage.cost and usage.cost.total or nil)
    end
  end

  event_adapter.handle_event(event)
end

function RpcClient:request(command)
  local id = command.id or next_request_id()
  command.id = id
  local promise = Promise.new()
  self.pending[id] = promise
  self.process:send(command):catch(function(err)
    self.pending[id] = nil
    promise:reject(err)
  end)
  return promise
end

function RpcClient:notify(command)
  return self.process:send(command)
end

function RpcClient:prompt(message, opts)
  opts = opts or {}
  local command = {
    type = 'prompt',
    message = message,
    images = opts.images,
  }
  if opts.streamingBehavior then
    command.streamingBehavior = opts.streamingBehavior
  elseif self.streaming then
    command.streamingBehavior = 'steer'
  end
  return self:request(command)
end

function RpcClient:abort()
  return self:request({ type = 'abort' })
end

local function sync_state_from_pi(pi_state)
  if not pi_state then
    return pi_state
  end
  local ok, state = pcall(require, 'pi.state')
  if ok and pi_state.model and pi_state.model.provider and pi_state.model.id then
    state.model.set_model(pi_state.model.provider .. '/' .. pi_state.model.id)
    state.model.set_model_info(pi_state.model)
  end
  if ok and pi_state.thinkingLevel then
    state.model.set_variant(pi_state.thinkingLevel)
  end
  return pi_state
end

function RpcClient:get_state()
  return self:request({ type = 'get_state' }):and_then(sync_state_from_pi)
end

function RpcClient:get_messages()
  return self:request({ type = 'get_messages' })
end

function RpcClient:new_session(parent_session)
  return self:request({ type = 'new_session', parentSession = parent_session })
end

function RpcClient:switch_session(path)
  return self:request({ type = 'switch_session', sessionPath = path })
end

function RpcClient:get_available_models()
  return self:request({ type = 'get_available_models' })
end

function RpcClient:set_model(provider, model_id)
  return self:request({ type = 'set_model', provider = provider, modelId = model_id }):and_then(function(model)
    sync_state_from_pi({ model = model })
    return model
  end)
end

function RpcClient:cycle_model()
  return self:request({ type = 'cycle_model' }):and_then(function(data)
    if data then
      sync_state_from_pi(data)
    end
    return data
  end)
end

function RpcClient:set_thinking_level(level)
  return self:request({ type = 'set_thinking_level', level = level })
end

function RpcClient:cycle_thinking_level()
  return self:request({ type = 'cycle_thinking_level' })
end

function RpcClient:get_commands()
  return self:request({ type = 'get_commands' })
end

function RpcClient:get_session_stats()
  return self:request({ type = 'get_session_stats' })
end

function RpcClient:get_last_assistant_text()
  return self:request({ type = 'get_last_assistant_text' }):and_then(function(data)
    return data and data.text or nil
  end)
end

function RpcClient:set_session_name(name)
  return self:request({ type = 'set_session_name', name = name })
end

function RpcClient:compact(custom_instructions)
  return self:request({ type = 'compact', customInstructions = custom_instructions })
end

function RpcClient:get_entries(since)
  return self:request({ type = 'get_entries', since = since })
end

function RpcClient:get_tree()
  return self:request({ type = 'get_tree' })
end

function RpcClient:fork(entry_id)
  return self:request({ type = 'fork', entryId = entry_id })
end

function RpcClient:clone()
  return self:request({ type = 'clone' })
end

return RpcClient
