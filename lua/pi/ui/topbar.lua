local config = require('pi.config')
local util = require('pi.util')
local winbar = require('pi.ui.winbar')

local M = {}

local state = require('pi.state')
local config_file = require('pi.config_file')

local LABELS = {
  NEW_SESSION_TITLE = 'New session',
}

local function model_context_limit()
  local model_info = state.current_model_info
  if model_info then
    if model_info.contextWindow then
      return model_info.contextWindow
    end
    if model_info.limit and model_info.limit.context then
      return model_info.limit.context
    end
  end

  if state.current_model then
    local provider, model = state.current_model:match('^(.-)/(.+)$')
    local ok, info = pcall(config_file.get_model_info, provider, model)
    if ok and info then
      if info.contextWindow then
        return info.contextWindow
      end
      if info.limit and info.limit.context then
        return info.limit.context
      end
    end
  end

  return 0
end

local function format_token_info()
  local parts = {}

  if config.ui.display_context_size then
    local token_count = state.tokens_count or 0
    local formatted_count = util.format_number(token_count)
    if formatted_count then
      table.insert(parts, formatted_count)
    end

    local stats = state.session_stats or {}
    if stats.contextUsage and stats.contextUsage.percent then
      table.insert(parts, string.format('%.1f%%%', stats.contextUsage.percent))
    else
      local limit = model_context_limit()
      if limit and limit > 0 then
        local formatted_pct = util.format_percentage(token_count / limit)
        if formatted_pct then
          table.insert(parts, formatted_pct)
        end
      end
    end
  end

  if config.ui.display_cost and state.cost and state.cost > 0 then
    local formatted_cost = util.format_cost(state.cost)
    if formatted_cost then
      table.insert(parts, formatted_cost)
    end
  end

  local result = table.concat(parts, ' | ')
  result = result:gsub('%%', '%%%%')
  return result
end

local function create_winbar_text(description, token_info, _)
  return description .. '%=' .. token_info
end

local function get_session_desc()
  if state.is_opening then
    return 'Loading...'
  end

  local session_title = LABELS.NEW_SESSION_TITLE

  if state.active_session and state.active_session.title ~= '' then
    session_title = state.active_session.title
  end

  if not session_title or type(session_title) ~= 'string' then
    session_title = ''
  end
  return session_title
end

function M.render()
  vim.schedule(function()
    if not state.windows then
      return
    end
    local win = state.windows.output_win
    if not win or not vim.api.nvim_win_is_valid(win) then
      return
    end

    vim.wo[win].winbar = ' '

    local desc = get_session_desc():gsub('%%', '%%%%')
    local token_info = format_token_info()
    local winbar_str = create_winbar_text(desc, token_info, vim.api.nvim_win_get_width(win))
    vim.wo[win].winbar = winbar_str

    winbar.update_highlights(win, 'PiSessionDescription')
  end)
end

local function on_change(_, _, _)
  M.render()
end

function M.setup()
  state.store.subscribe('current_mode', on_change)
  state.store.subscribe('current_model', on_change)
  state.store.subscribe('active_session', on_change)
  state.store.subscribe('is_pi_focused', on_change)
  state.store.subscribe('tokens_count', on_change)
  state.store.subscribe('cost', on_change)
  state.store.subscribe('session_stats', on_change)
  state.store.subscribe('current_model_info', on_change)
  state.store.subscribe('is_opening', on_change)
  M.render()
end

function M.close()
  state.store.unsubscribe('current_mode', on_change)
  state.store.unsubscribe('current_model', on_change)
  state.store.unsubscribe('active_session', on_change)
  state.store.unsubscribe('is_pi_focused', on_change)
  state.store.unsubscribe('tokens_count', on_change)
  state.store.unsubscribe('cost', on_change)
  state.store.unsubscribe('session_stats', on_change)
  state.store.unsubscribe('current_model_info', on_change)
end
return M
