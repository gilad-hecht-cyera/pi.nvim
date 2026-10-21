local PiProcess = require('pi.pi_process')
local RpcClient = require('pi.rpc_client')

---@class PiTabRuntime
---@field id integer
---@field process table
---@field rpc_client table

---@class PiTabRuntimeOpts
---@field extra_args? string[] Extra `pi` CLI args for this tab, e.g. `{ '--fork', path }`
---@field cwd? string

local M = {}

local CLOSE_ABORT_TIMEOUT_MS = 2000

---@type table<integer, PiTabRuntime>
local runtimes = {}
---@type integer[]
local order = {}
local next_id = 0
local active_id = nil
local vim_leave_registered = false

local function ensure_vim_leave_autocmd()
  if vim_leave_registered then
    return
  end
  vim_leave_registered = true
  vim.api.nvim_create_autocmd('VimLeavePre', {
    group = vim.api.nvim_create_augroup('PiTabRuntimes', { clear = true }),
    callback = function()
      M.stop_all()
    end,
  })
end

---@param opts? PiTabRuntimeOpts
---@return PiTabRuntime
function M.create(opts)
  opts = opts or {}
  ensure_vim_leave_autocmd()
  next_id = next_id + 1
  local id = next_id
  local process = PiProcess.new({ cwd = opts.cwd, extra_args = opts.extra_args })
  local runtime = {
    id = id,
    process = process,
    rpc_client = RpcClient.new(process, { tab_id = id }),
  }
  runtimes[id] = runtime
  table.insert(order, id)
  if active_id == nil then
    active_id = id
  end
  return runtime
end

---@param id integer
---@return PiTabRuntime|nil
function M.get(id)
  return runtimes[id]
end

---@return integer|nil
function M.active_id()
  return active_id
end

---Returns the active tab runtime, creating the first one on demand.
---@return PiTabRuntime
function M.active()
  if active_id == nil then
    return M.create()
  end
  return runtimes[active_id]
end

---@param id integer
---@return boolean
function M.is_active(id)
  return id == active_id
end

---@param id integer
---@return boolean
function M.set_active(id)
  if not runtimes[id] then
    return false
  end
  active_id = id
  return true
end

---@return PiTabRuntime[]
function M.list()
  return vim.tbl_map(function(id)
    return runtimes[id]
  end, order)
end

---Reorder tabs. `ids` must contain exactly the current tab ids.
---@param ids integer[]
---@return boolean reordered
function M.set_order(ids)
  if #ids ~= #order then
    return false
  end
  local seen = {}
  for _, id in ipairs(ids) do
    if not runtimes[id] or seen[id] then
      return false
    end
    seen[id] = true
  end
  order = vim.list_extend({}, ids)
  return true
end

local function remove(id)
  runtimes[id] = nil
  for i, value in ipairs(order) do
    if value == id then
      table.remove(order, i)
      if active_id == id then
        active_id = order[i] or order[i - 1]
      end
      break
    end
  end
end

---Close a tab runtime. A streaming tab is aborted before its process is stopped.
---@param id integer
---@return boolean closed
function M.close(id)
  local runtime = runtimes[id]
  if not runtime then
    return false
  end
  remove(id)

  if not (runtime.rpc_client.streaming and runtime.process:is_running()) then
    runtime.process:stop()
    return true
  end

  local stopped = false
  local function stop()
    if not stopped then
      stopped = true
      runtime.process:stop()
    end
  end
  runtime.rpc_client:abort():finally(stop)
  vim.defer_fn(stop, CLOSE_ABORT_TIMEOUT_MS)
  return true
end

function M.stop_all()
  for _, runtime in pairs(runtimes) do
    runtime.process:stop()
  end
end

function M._reset()
  M.stop_all()
  runtimes = {}
  order = {}
  next_id = 0
  active_id = nil
end

return M
