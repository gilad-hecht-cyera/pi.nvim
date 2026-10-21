local store = require('pi.state.store')

---State keys owned by a sidebar tab. Everything else in the store is shared across tabs.
---@class PiTabScopeStateMutations
local M = {}

M.KEYS = {
  'active_session',
  'messages',
  'current_message',
  'pending_permissions',
  'restore_points',
  'user_message_count',
  'last_sent_context',
  'cost',
  'tokens_count',
  'session_stats',
  'extension_statuses',
  'current_model',
  'current_model_info',
  'current_variant',
  'session_locked',
  'input_content',
}

---@return table
function M.defaults()
  return store.defaults(M.KEYS)
end

---Load a tab's saved values and return the values it replaced.
---@param incoming? table Defaults when nil
---@return table outgoing
function M.swap(incoming)
  return store.swap(M.KEYS, incoming or M.defaults())
end

return M
