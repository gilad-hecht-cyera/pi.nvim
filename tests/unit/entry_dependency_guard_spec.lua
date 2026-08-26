local assert = require('luassert')

describe('entry contracts', function()
  it('keeps default keymap string actions command-routable', function()
    local config = require('pi.config')
    local commands = require('pi.commands')
    local defs = commands.get_commands()

    local checked = 0
    for _, section in ipairs({ 'editor', 'input_window', 'output_window' }) do
      for key, keymap_entry in pairs(config.defaults.keymap[section] or {}) do
        local action = keymap_entry and keymap_entry[1]
        if type(action) == 'string' then
          checked = checked + 1
          assert.is_not_nil(
            defs[action],
            string.format('Unroutable keymap action %s -> %s in %s', key, action, section)
          )
        end
      end
    end

    assert.is_true(checked > 0, 'Expected to validate at least one keymap action')
  end)

  it('keeps builtin slash commands loadable', function()
    local slash = require('pi.commands.slash')
    local slash_commands = slash.get_commands():wait()

    assert.is_true(#slash_commands > 0, 'Expected built-in slash commands')
    assert.truthy(vim.tbl_filter(function(command)
      return command.slash_cmd == '/help' and type(command.fn) == 'function'
    end, slash_commands)[1])
  end)
end)
