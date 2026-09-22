local Promise = require('pi.promise')

local M = {
  actions = {},
}

local function join_args(args)
  return table.concat(args or {}, ' ')
end

---Forward a vanilla Pi slash command to the Pi RPC runtime.
---@param name string
---@param args string[]|nil
M.actions.send_pi_command = Promise.async(function(name, args)
  local message = '/' .. name
  local arg_text = join_args(args)
  if arg_text ~= '' then
    message = message .. ' ' .. arg_text
  end

  require('pi.services.session_runtime').open({ new_session = false, focus = 'output' }):await()
  return require('pi.rpc_client').get():prompt(message):await()
end)

local function forwarded(name, desc)
  return {
    desc = desc,
    execute = function(args)
      return M.actions.send_pi_command(name, args)
    end,
  }
end

M.command_defs = {
  settings = forwarded('settings', 'Open Pi settings menu'),
  model = {
    desc = 'Select Pi model',
    execute = function(args)
      if args and #args > 0 then
        return M.actions.send_pi_command('model', args)
      end
      return require('pi.services.agent_model').configure_provider()
    end,
  },
  tree = forwarded('tree', 'Navigate Pi session tree'),
  thinking = {
    desc = 'Set/select Pi thinking level',
    execute = function(args)
      if args and #args > 0 then
        return M.actions.send_pi_command('thinking', args)
      end
      return require('pi.services.agent_model').configure_variant()
    end,
  },
  ['scoped-models'] = forwarded('scoped-models', 'Enable/disable models for Ctrl+P cycling'),
  export = forwarded('export', 'Export Pi session'),
  import = forwarded('import', 'Import and resume a Pi session'),
  share = forwarded('share', 'Share Pi session as a secret GitHub gist'),
  copy = forwarded('copy', 'Copy last Pi agent message to clipboard'),
  name = forwarded('name', 'Set Pi session display name'),
  changelog = forwarded('changelog', 'Show Pi changelog entries'),
  hotkeys = forwarded('hotkeys', 'Show Pi keyboard shortcuts'),
  fork = forwarded('fork', 'Create a new fork from a previous user message'),
  clone = forwarded('clone', 'Duplicate current Pi session at the current position'),
  trust = forwarded('trust', 'Save project trust decision for future sessions'),
  login = forwarded('login', 'Configure Pi provider authentication'),
  logout = forwarded('logout', 'Remove Pi provider authentication'),
  new = {
    desc = 'Start a new Pi session',
    execute = function()
      return require('pi.services.session_runtime').open({ new_session = true, focus = 'input' })
    end,
  },
  compact = {
    desc = 'Manually compact the Pi session context',
    execute = function(args)
      local custom = join_args(args)
      return require('pi.rpc_client').get():compact(custom ~= '' and custom or nil):and_then(function()
        vim.notify('Pi session compacted', vim.log.levels.INFO)
      end)
    end,
  },
  reload = {
    desc = 'Reload Pi resources by restarting the RPC process',
    execute = function()
      local process = require('pi.pi_process').get()
      process:stop()
      return require('pi.server_job').ensure_server():and_then(function()
        vim.notify('Pi RPC restarted', vim.log.levels.INFO)
      end)
    end,
  },
  quit = {
    desc = 'Close pi.nvim windows',
    execute = function()
      return require('pi.commands.handlers.window').actions.close()
    end,
  },
}

return M
