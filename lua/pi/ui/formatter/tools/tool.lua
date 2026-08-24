local utils = require('pi.ui.formatter.utils')
local icons = require('pi.ui.icons')
local M = {}

---@param output Output
---@param part PiMessagePart
function M.format(output, part)
  local icons = require('pi.ui.icons')
  utils.format_action(output, icons.get('tool'), 'tool', part.tool, utils.get_duration_text(part))
end

---@param _ PiMessagePart
---@param input table
---@return string, string, string
function M.summary(_, input)
  return icons.get('tool'), 'tool', input.description or ''
end

return M
