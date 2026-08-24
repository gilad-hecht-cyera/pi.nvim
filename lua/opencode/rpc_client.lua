local Promise = require('opencode.promise')
local PiProcess = require('opencode.pi_process')
local event_adapter = require('opencode.event_adapter')

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

  if event.type == 'agent_start' then
    self.streaming = true
  elseif event.type == 'agent_settled' then
    self.streaming = false
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

function RpcClient:get_state()
  return self:request({ type = 'get_state' })
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
  return self:request({ type = 'set_model', provider = provider, modelId = model_id })
end

return RpcClient
