local tabs = require('pi.services.tabs')
local session_runtime = require('pi.services.session_runtime')
local Promise = require('pi.promise')

local M = {
  actions = {},
}

---@param message string
local function invalid_arguments(message)
  error({
    code = 'invalid_arguments',
    message = message,
  }, 0)
end

local function notify_error(err)
  vim.notify('[pi.nvim] ' .. tostring(err), vim.log.levels.ERROR)
end

local function focus_input()
  return session_runtime.open({ new_session = false, focus = 'input', start_insert = true })
end

function M.actions.tab_new()
  return tabs.new():and_then(focus_input):catch(notify_error)
end

function M.actions.tab_fork()
  return tabs.fork_current():and_then(focus_input):catch(notify_error)
end

local function fork_choice_label(message)
  local text = (message.text or ''):gsub('%s+', ' ')
  return vim.fn.strcharpart(text, 0, 80)
end

---Pick an earlier user message of the active tab and fork from it into a new tab.
function M.actions.tab_fork_pick()
  return require('pi.rpc_client')
    .get()
    :get_fork_messages()
    :and_then(function(data)
      local messages = data and data.messages or {}
      if #messages == 0 then
        vim.notify('[pi.nvim] No user message to fork from', vim.log.levels.WARN)
        return
      end
      local picked = Promise.new()
      vim.ui.select(messages, { prompt = 'Fork from message:', format_item = fork_choice_label }, function(choice)
        picked:resolve(choice)
      end)
      return picked:and_then(function(choice)
        if not choice then
          return
        end
        return tabs.fork_into_tab({ entry_id = choice.entryId }):and_then(focus_input)
      end)
    end)
    :catch(notify_error)
end

---Pi's own `/fork` replaces the session in the current process; offer a new tab instead.
---@param args string[]|nil
function M.actions.fork_routed(args)
  return tabs.choose_fork_target({
    tab = M.actions.tab_fork_pick,
    current = function()
      require('pi.commands.handlers.vanilla').actions.send_pi_command('fork', args)
    end,
  })
end

function M.actions.tab_next()
  return Promise.new():resolve(tabs.cycle(1))
end

function M.actions.tab_prev()
  return Promise.new():resolve(tabs.cycle(-1))
end

function M.actions.tab_close()
  return tabs.close_active():catch(notify_error)
end

---@param index integer
function M.actions.tab_goto(index)
  if not tabs.go_to(index) then
    vim.notify('[pi.nvim] No tab ' .. tostring(index), vim.log.levels.WARN)
    return Promise.new():resolve(false)
  end
  return Promise.new():resolve(true)
end

local tab_subcommands = { 'new', 'fork', 'next', 'prev', 'close', 'goto' }

---@type table<string, fun(args: string[]): any>
local tab_subcommand_calls = {
  new = M.actions.tab_new,
  fork = M.actions.tab_fork,
  next = M.actions.tab_next,
  prev = M.actions.tab_prev,
  close = M.actions.tab_close,
  ['goto'] = function(args)
    local index = tonumber(args[2])
    if not index then
      invalid_arguments('Usage: tab goto <number>')
    end
    return M.actions.tab_goto(index)
  end,
}

M.command_defs = {
  tab = {
    desc = 'Manage sidebar tabs (new/fork/next/prev/close/goto)',
    completions = tab_subcommands,
    nested_subcommand = { allow_empty = false },
    execute = function(args)
      local action = tab_subcommand_calls[args[1]]
      if not action then
        invalid_arguments('Invalid tab subcommand. Use: ' .. table.concat(tab_subcommands, ', '))
      end
      return action(args)
    end,
  },
}

return M
