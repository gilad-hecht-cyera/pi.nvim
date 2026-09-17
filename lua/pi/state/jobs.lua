local store = require('pi.state.store')

---@class PiJobStateMutations
local M = {}

---@param delta integer|nil
function M.increment_count(delta)
  return store.update('job_count', function(current)
    return (current or 0) + (delta or 1)
  end)
end

---@param delta integer|nil
function M.decrement_count(delta)
  return store.update('job_count', function(current)
    return math.max(0, (current or 0) - (delta or 1))
  end)
end

---@param count integer
function M.set_count(count)
  return store.set('job_count', count)
end

---@param server PiServer|nil
function M.set_server(server)
  return store.set('pi_server', server)
end

function M.clear_server()
  return store.set('pi_server', nil)
end

---@param port integer
function M.set_server_port(port)
  local server = store.get('pi_server')
  if not server then
    error('Pi server is not set; cannot set port')
  end

  store.mutate('pi_server', function(s)
    s.port = port
  end)
end

---@param client PiApiClient|nil
function M.set_api_client(client)
  return store.set('api_client', client)
end

---@param manager EventManager|nil
function M.set_event_manager(manager)
  return store.set('event_manager', manager)
end

---@param version Promise<string>|nil
function M.set_pi_cli_version(version)
  return store.set('pi_cli_version', version)
end

function M.is_running()
  return (store.get('job_count') or 0) > 0
end

return M
