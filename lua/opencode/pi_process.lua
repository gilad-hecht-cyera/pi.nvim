local Promise = require('opencode.promise')
local config = require('opencode.config')
local log = require('opencode.log')

local PiProcess = {}
PiProcess.__index = PiProcess

local instance

local function notify_error(message)
  log.notify('[pi.nvim] ' .. message, vim.log.levels.ERROR)
end

function PiProcess.new(opts)
  opts = opts or {}
  return setmetatable({
    job_id = nil,
    stdout_buffer = '',
    stderr_buffer = '',
    listeners = {},
    cwd = opts.cwd or vim.fn.getcwd(),
    exited = false,
    stopping = false,
  }, PiProcess)
end

function PiProcess.get()
  if not instance then
    instance = PiProcess.new()
  end
  return instance
end

function PiProcess:is_running()
  return self.job_id ~= nil and self.exited == false
end

function PiProcess:on_event(callback)
  table.insert(self.listeners, callback)
  return function()
    for i = #self.listeners, 1, -1 do
      if self.listeners[i] == callback then
        table.remove(self.listeners, i)
      end
    end
  end
end

function PiProcess:_emit(event)
  for _, callback in ipairs(self.listeners) do
    local ok, err = pcall(callback, event)
    if not ok then
      notify_error('event listener failed: ' .. tostring(err))
    end
  end
end

function PiProcess:_handle_stdout_line(line)
  if line == '' then
    return
  end
  if line:sub(-1) == '\r' then
    line = line:sub(1, -2)
  end
  local ok, decoded = pcall(vim.json.decode, line)
  if not ok then
    notify_error('failed to decode RPC JSON: ' .. tostring(decoded))
    log.debug('Bad pi RPC line: %s', line)
    return
  end
  self:_emit(decoded)
end

function PiProcess:_handle_stdout_data(data)
  if not data then
    return
  end

  -- jobstart gives line fragments split on LF. Reconstruct the exact JSONL
  -- records so empty trailing chunks do not become records.
  for i, chunk in ipairs(data) do
    if i == 1 then
      self.stdout_buffer = self.stdout_buffer .. chunk
    else
      self:_handle_stdout_line(self.stdout_buffer)
      self.stdout_buffer = chunk
    end
  end
end

function PiProcess:start()
  if self:is_running() then
    return Promise.new():resolve(self)
  end

  if vim.fn.executable(config.pi_executable) == 0 then
    return Promise.new():reject(config.pi_executable .. ' command not found')
  end

  local promise = Promise.new()
  local args = { config.pi_executable, '--mode', 'rpc' }
  for _, arg in ipairs(config.pi_args or {}) do
    table.insert(args, arg)
  end

  self.exited = false
  self.stopping = false
  self.cwd = vim.fn.getcwd()
  self.job_id = vim.fn.jobstart(args, {
    cwd = self.cwd,
    stdin = 'pipe',
    stdout_buffered = false,
    stderr_buffered = false,
    on_stdout = function(_, data)
      vim.schedule(function()
        self:_handle_stdout_data(data)
      end)
    end,
    on_stderr = function(_, data)
      if not data then
        return
      end
      local text = table.concat(data, '\n')
      if text ~= '' then
        self.stderr_buffer = self.stderr_buffer .. text
        log.warn('[pi.nvim] stderr: %s', text)
      end
    end,
    on_exit = function(_, code, signal)
      vim.schedule(function()
        self.exited = true
        local old_job_id = self.job_id
        self.job_id = nil
        self:_emit({ type = 'process_exit', code = code, signal = signal, jobId = old_job_id })
        if code ~= 0 and not self.stopping then
          notify_error('pi RPC process exited with code ' .. tostring(code))
        end
      end)
    end,
  })

  if self.job_id <= 0 then
    self.job_id = nil
    promise:reject('failed to start pi RPC process')
    return promise
  end

  vim.api.nvim_create_autocmd('VimLeavePre', {
    group = vim.api.nvim_create_augroup('PiNvimRpcProcess', { clear = true }),
    callback = function()
      self:stop()
    end,
  })

  promise:resolve(self)
  return promise
end

function PiProcess:send(command)
  local promise = self:start()
  return promise:and_then(function()
    local line = vim.json.encode(command) .. '\n'
    local ok = pcall(vim.fn.chansend, self.job_id, line)
    if not ok then
      return Promise.new():reject('failed to write to pi RPC process')
    end
    return true
  end)
end

function PiProcess:stop()
  if self.job_id then
    self.stopping = true
    pcall(vim.fn.chanclose, self.job_id, 'stdin')
    pcall(vim.fn.jobstop, self.job_id)
    self.job_id = nil
  end
  self.exited = true
end

return PiProcess
