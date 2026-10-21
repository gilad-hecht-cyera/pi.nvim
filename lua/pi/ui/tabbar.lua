local state = require('pi.state')

local M = {}

local CLICK_HANDLER = 'PiTabbarClick'
local MIN_TITLE_WIDTH = 6
local LABEL_PADDING = 4

---@type table<PiTabStatus, string>
local STATUS_MARKS = {
  running = '●',
  waiting = '?',
  done = '✓',
}

---@param minwid integer Tab id encoded in the click label
_G[CLICK_HANDLER] = function(minwid)
  vim.schedule(function()
    require('pi.services.tabs').switch(minwid)
  end)
end

local function escape(text)
  return (text:gsub('%%', '%%%%'))
end

local function truncate(text, max_width)
  if vim.fn.strdisplaywidth(text) <= max_width then
    return text
  end
  if max_width <= 1 then
    return '…'
  end
  return vim.fn.strcharpart(text, 0, max_width - 1) .. '…'
end

---@param tab PiTabView
---@param title_width integer
local function label(tab, title_width)
  local text = string.format(' %d%s %s ', tab.index, STATUS_MARKS[tab.status] or '', truncate(tab.title, title_width))
  local group = tab.active and 'PiTabActive' or (tab.status == 'waiting' and 'PiTabWaiting' or 'PiTabInactive')
  return string.format('%%%d@v:lua.%s@%%#%s#%s%%*%%X', tab.id, CLICK_HANDLER, group, escape(text))
end

---Format the tab strip for a winbar, or nil when there is at most one tab.
---@param tabs PiTabView[]
---@param available_width integer Columns the strip may use
---@return string|nil
function M.format(tabs, available_width)
  if #tabs < 2 then
    return nil
  end

  local active_title = state.active_session and state.active_session.title
  local per_tab = math.floor(available_width / #tabs) - LABEL_PADDING - #tostring(#tabs)
  local title_width = math.max(MIN_TITLE_WIDTH, per_tab)

  local parts = {}
  for _, tab in ipairs(tabs) do
    if tab.active and type(active_title) == 'string' and active_title ~= '' then
      tab = vim.tbl_extend('force', tab, { title = active_title })
    end
    table.insert(parts, label(tab, title_width))
  end
  return table.concat(parts, '')
end

return M
