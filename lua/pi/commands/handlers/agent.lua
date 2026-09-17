local config = require('pi.config')
local config_file = require('pi.config_file')
---@type PiState
local state = require('pi.state')
local util = require('pi.util')
local Promise = require('pi.promise')
local agent_model = require('pi.services.agent_model')

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

function M.actions.configure_provider()
  agent_model.configure_provider()
end

function M.actions.configure_variant()
  agent_model.configure_variant()
end

function M.actions.cycle_variant()
  agent_model.cycle_variant()
end

function M.actions.agent_plan()
  agent_model.switch_to_mode('plan')
end

function M.actions.agent_build()
  agent_model.switch_to_mode('build')
end

M.actions.select_agent = Promise.async(function()
  local modes = config_file.get_pi_agents():await()
  local picker = require('pi.ui.picker')
  picker.select(modes, {
    prompt = 'Select mode:',
  }, function(selection)
    if not selection then
      return
    end

    agent_model.switch_to_mode(selection)
  end)
end)

local function has_command(commands, name)
  for _, command in ipairs(commands and commands.commands or {}) do
    if command.name == name then
      return true
    end
  end
  return false
end

local function toggle_pi_plan_mode()
  local rpc_client = require('pi.rpc_client').get()
  local commands = rpc_client:get_commands():await()
  if not has_command(commands, 'plan') then
    vim.notify('Plan mode extension command /plan is not available', vim.log.levels.WARN)
    return false
  end

  rpc_client:prompt('/plan'):await()
  return true
end

M.actions.switch_mode = Promise.async(function()
  if config.backend == 'pi' then
    return toggle_pi_plan_mode()
  end

  local modes = config_file.get_pi_agents():await() --[[@as string[] ]]
  local current_index = util.index_of(modes, state.store.get('current_mode'))

  if current_index == nil then
    current_index = 0
  end

  local next_index = (current_index % #modes) + 1
  agent_model.switch_to_mode(modes[next_index])
end)

M.actions.current_model = Promise.async(function()
  return agent_model.initialize_current_model()
end)

local agent_subcommands = { 'plan', 'build', 'select' }

---@type table<string, fun(): any>
local agent_subcommand_calls = {
  plan = M.actions.agent_plan,
  build = M.actions.agent_build,
  select = M.actions.select_agent,
}

M.command_defs = {
  agent = {
    desc = 'Manage agents (plan/build/select)',
    completions = agent_subcommands,
    nested_subcommand = { allow_empty = false },
    execute = function(args)
      local action = agent_subcommand_calls[args[1]]
      if not action then
        invalid_arguments('Invalid agent subcommand. Use: ' .. table.concat(agent_subcommands, ', '))
      end
      return action()
    end,
  },
  models = {
    desc = 'Switch provider/model',
    execute = M.actions.configure_provider,
  },
  -- action name aliases for keymap compatibility
  configure_provider = { desc = 'Configure provider',     execute = M.actions.configure_provider },
  configure_variant  = { desc = 'Configure model variant', execute = M.actions.configure_variant },
  variant = {
    desc = 'Switch model variant',
    execute = M.actions.configure_variant,
  },
  cycle_variant = {
    desc = 'Cycle model variant',
    execute = M.actions.cycle_variant,
  },
  switch_mode = {
    desc = 'Cycle agent mode',
    execute = M.actions.switch_mode,
  },
}

return M
