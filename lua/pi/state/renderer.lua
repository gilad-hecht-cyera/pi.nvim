local store = require('pi.state.store')

---@class PiRendererStateMutations
local M = {}

---@param messages PiMessage[]|nil
function M.set_messages(messages)
  return store.set('messages', messages)
end

---@param message PiMessage|nil
function M.set_current_message(message)
  return store.set('current_message', message)
end

---@param permissions PiPermission[]
function M.set_pending_permissions(permissions)
  return store.set('pending_permissions', permissions)
end

---@param mutator fun(current_permissions: PiPermission[]): nil
function M.update_pending_permissions(mutator)
  return store.mutate('pending_permissions', mutator)
end

---@param cost number
function M.set_cost(cost)
  if not cost or cost <= 0 then
    return
  end
  return store.set('cost', cost)
end

---@param count number
function M.set_tokens_count(count)
  return store.set('tokens_count', count)
end

---@param tokens_count number
---@param cost number
function M.set_stats(tokens_count, cost)
  return store.batch(function()
    store.set('tokens_count', tokens_count)
    if cost and cost > 0 then
      store.set('cost', cost)
    end
  end)
end

---@param stats table|nil
function M.set_session_stats(stats)
  return store.batch(function()
    store.set('session_stats', stats)
    if stats then
      local tokens = stats.tokens or {}
      local token_count = tokens.total
        or ((tokens.input or 0) + (tokens.output or 0) + (tokens.cacheRead or 0) + (tokens.cacheWrite or 0))
      store.set('tokens_count', token_count or 0)
      if stats.cost and stats.cost > 0 then
        store.set('cost', stats.cost)
      end
    end
  end)
end

function M.reset()
  return store.batch(function()
    store.set('messages', {})
    store.set('current_message', nil)
    store.set('tokens_count', 0)
    store.set('cost', 0)
    store.set('session_stats', nil)
    store.set('pending_permissions', {})
  end)
end

return M
