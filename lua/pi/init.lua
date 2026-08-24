local M = {}

function M.setup(opts)
  opts = opts or {}
  opts.backend = 'pi'
  return require('opencode').setup(opts)
end

return M
