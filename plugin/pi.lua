-- Plugin loader for pi.nvim
if vim.g.loaded_pi_nvim == 1 then
  return
end
vim.g.loaded_pi_nvim = 1

vim.api.nvim_create_user_command('Pi', function(opts)
  local pi = require('pi')
  pi.setup()
  require('pi.commands').execute_command_opts(opts)
end, {
  desc = 'pi.nvim main command with nested subcommands',
  nargs = '*',
  range = true,
})
