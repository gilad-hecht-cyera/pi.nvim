local icons = require('pi.ui.icons')
local utils = require('pi.ui.formatter.utils')

local M = {}

---@param output Output
---@param part PiMessagePart
function M.format(output, part)
  local input = part.state and part.state.input or {}
  utils.format_action(output, icons.get('skill'), 'skill', input.name or '', utils.get_duration_text(part))
end

---@param _ PiMessagePart
---@param input table
---@return string, string, string
function M.summary(_, input)
  return icons.get('skill'), 'skill', input.name or ''
end

return M
