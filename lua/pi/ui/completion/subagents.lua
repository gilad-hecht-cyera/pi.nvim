local icons = require('pi.ui.icons')
local Promise = require('pi.promise')

local M = {}

local custom_kind = require('pi.ui.completion.kind')

---@type CompletionSource
local subagent_source = {
  name = 'subagents',
  priority = 1,
  custom_kind = custom_kind.register('subagents', icons.get('agent')),
  complete = Promise.async(function(context)
    local subagents = require('pi.config_file').get_subagents():await()
    local config = require('pi.config')
    local expected_trigger = config.get_key_for_function('input_window', 'mention') or '@'
    if context.trigger_char ~= expected_trigger then
      return {}
    end

    local items = {}
    local input_lower = context.input:lower()

    for _, subagent in ipairs(subagents) do
      local name_lower = subagent:lower()

      if context.input == '' or name_lower:find(input_lower, 1, true) then
        local item = {
          label = subagent .. ' (agent)',
          kind = 'subagent',
          kind_icon = icons.get('agent'),
          detail = 'Subagent',
          documentation = 'Use the "' .. subagent .. '" subagent for this task.',
          insert_text = subagent,
          source_name = 'subagents',
          data = {
            name = subagent,
          },
        }

        table.insert(items, item)
      end
    end

    local sort_util = require('pi.ui.completion.sort')
    sort_util.sort_by_relevance(items, context.input)

    return items
  end),
  on_complete = function(item)
    local state = require('pi.state')
    local context = require('pi.context')
    local mention = require('pi.ui.mention')
    mention.highlight_all_mentions(state.windows.input_buf)
    context.add_subagent(item.data.name)
  end,
  get_trigger_character = function()
    local config = require('pi.config')
    return config.get_key_for_function('input_window', 'mention')
  end,
}

---Get the subagent completion source
---@return CompletionSource
function M.get_source()
  return subagent_source
end

return M
