local Promise = require('pi.promise')
local log = require('pi.log')

local M = {}

local function join_args(args)
  return table.concat(args or {}, ' ')
end

local function focus_input()
  local ok, ui = pcall(require, 'pi.ui.ui')
  if ok and require('pi.state').ui.is_visible() then
    ui.focus_input()
  end
end

function M.send_pi_command(name, args)
  local message = '/' .. name
  local arg_text = join_args(args)
  if arg_text ~= '' then
    message = message .. ' ' .. arg_text
  end

  return require('pi.services.session_runtime').open({ new_session = false, focus = 'output' }):and_then(function()
    return require('pi.rpc_client').get():prompt(message)
  end)
end

local function restart_pi_rpc()
  local process = require('pi.pi_process').get()
  process:stop()
  return require('pi.server_job').ensure_server():and_then(function()
    vim.notify('Pi RPC restarted', vim.log.levels.INFO)
  end)
end

local function local_command(slash_cmd, desc, fn, takes_args)
  return {
    slash_cmd = slash_cmd,
    desc = desc,
    fn = fn,
    args = takes_args == true,
  }
end

local function pi_command(slash_cmd, desc, name, takes_args)
  return local_command(slash_cmd, desc, function(args)
    return M.send_pi_command(name or slash_cmd:gsub('^/', ''), args)
  end, takes_args)
end

local function builtin_commands()
  return {
    local_command('/help', 'Show pi.nvim help', function()
      return require('pi.commands').execute_parsed_intent(require('pi.commands').build_parsed_intent('help', {}))
    end),
    local_command('/model', 'Select Pi model', function()
      return require('pi.services.agent_model').configure_provider()
    end),
    local_command('/thinking', 'Select Pi thinking level', function()
      return require('pi.services.agent_model').configure_variant()
    end),
    local_command('/new', 'Start a new Pi session', function()
      return require('pi.services.session_runtime').open({ new_session = true, focus = 'input' })
    end),
    local_command('/resume', 'Select Pi session', function()
      return require('pi.services.session_runtime').select_session()
    end),
    local_command('/sessions', 'Select Pi session', function()
      return require('pi.services.session_runtime').select_session()
    end),
    local_command('/compact', 'Compact current Pi session', function(args)
      local custom = join_args(args)
      return require('pi.rpc_client').get():compact(custom ~= '' and custom or nil):and_then(function()
        vim.notify('Pi session compacted', vim.log.levels.INFO)
      end)
    end, true),
    local_command('/reload', 'Restart Pi RPC process to reload Pi resources', function()
      return restart_pi_rpc()
    end),
    local_command('/clear_files', 'Clear attached files from pi.nvim context', function()
      require('pi.context').clear_files()
      focus_input()
    end),
    local_command('/clear_selections', 'Clear selections from pi.nvim context', function()
      require('pi.context').clear_selections()
      focus_input()
    end),
    local_command('/rename', 'Rename Pi session (or ask Pi to choose with no args)', function(args)
      local title = join_args(args)
      if title ~= '' then
        return require('pi.commands.handlers.session').actions.rename_session(nil, title)
      end
      return require('pi.commands.handlers.session').actions.autoname_session()
    end, true),
    local_command('/autoname', 'Ask Pi to choose a concise session name', function()
      return require('pi.commands.handlers.session').actions.autoname_session()
    end),
    pi_command('/name', 'Set Pi session display name', 'name', true),
    pi_command('/session', 'Show Pi session info', 'session', false),
    pi_command('/tree', 'Open Pi session tree in Pi', 'tree', false),
    pi_command('/fork', 'Fork current Pi session in Pi', 'fork', true),
    pi_command('/clone', 'Clone current Pi branch in Pi', 'clone', false),
    pi_command('/copy', 'Copy last assistant message in Pi', 'copy', false),
    pi_command('/export', 'Export Pi session in Pi', 'export', true),
    pi_command('/share', 'Share Pi session in Pi', 'share', false),
    pi_command('/import', 'Import Pi session in Pi', 'import', true),
    pi_command('/trust', 'Trust project in Pi', 'trust', false),
  }
end

local function add_unique(result, seen, command)
  if not command or not command.slash_cmd or seen[command.slash_cmd] then
    return
  end
  seen[command.slash_cmd] = true
  table.insert(result, command)
end

M.get_commands = Promise.async(function()
  ---@type PiSlashCommand[]
  local result = {}
  local seen = {}

  for _, command in ipairs(builtin_commands()) do
    add_unique(result, seen, command)
  end

  local ok, data = pcall(function()
    return require('pi.rpc_client').get():get_commands():await()
  end)
  if ok and data and data.commands then
    for _, command in ipairs(data.commands) do
      local name = command.name
      if name and name ~= '' then
        add_unique(
          result,
          seen,
          pi_command('/' .. name, command.description or ('Pi ' .. tostring(command.source or 'command')), name, true)
        )
      end
    end
  elseif not ok then
    log.debug('Failed to load Pi RPC commands: %s', vim.inspect(data))
  end

  table.sort(result, function(a, b)
    return a.slash_cmd < b.slash_cmd
  end)

  return result
end)

return M
