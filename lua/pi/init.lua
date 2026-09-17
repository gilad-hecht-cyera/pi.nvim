local M = {}

local setup_done = false
local state

local session_runtime = require('pi.services.session_runtime')

local function on_pi_server()
  require('pi.ui.permission_window').clear_all()
end

local function on_current_model_change(_key, new_val, old_val)
  if new_val ~= old_val then
    state.model.clear_variant()

    if new_val then
      local provider, model = new_val:match('^(.-)/(.+)$')
      if provider and model then
        local model_state = require('pi.model_state')
        local saved_variant = model_state.get_variant(provider, model)
        if saved_variant then
          state.model.set_variant(saved_variant)
        end
      end
    end
  end
end

function M.setup(opts)
  if setup_done then
    return
  end
  setup_done = true

  -- Have to setup config first, especially before state as
  -- it initializes at least one value (current_mode) from config.
  -- If state is require'd first then it will not get what may
  -- be set by the user
  local config = require('pi.config')
  config.setup(opts)

  require('pi.ui.highlight').setup()

  state = require('pi.state')
  state.store.subscribe('pi_server', on_pi_server)
  state.store.subscribe('user_message_count', session_runtime._on_user_message_count_change)
  state.store.subscribe('pending_permissions', session_runtime._on_current_permission_change)
  state.store.subscribe('current_model', on_current_model_change)

  vim.schedule(function()
    session_runtime.pi_ok()
  end)
  local PiApiClient = require('pi.api_client')
  state.jobs.set_api_client(PiApiClient.create())

  require('pi.commands').setup()
  require('pi.ui.completion').setup()
  require('pi.keymap').setup(config.keymap)
  require('pi.event_manager').setup()
  require('pi.context').setup()
  require('pi.ui.context_bar').setup()
end

return M
