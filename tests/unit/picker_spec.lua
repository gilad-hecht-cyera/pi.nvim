local assert = require('luassert')

describe('pi.ui.picker', function()
  local saved_modules

  before_each(function()
    saved_modules = {
      ['pi.config'] = package.loaded['pi.config'],
      ['pi.ui.picker'] = package.loaded['pi.ui.picker'],
    }
  end)

  after_each(function()
    for module_name, module_value in pairs(saved_modules) do
      package.loaded[module_name] = module_value
    end
  end)

  local function get_best_picker(preferred_picker)
    package.loaded['pi.config'] = {
      preferred_picker = preferred_picker,
    }
    package.loaded['pi.ui.picker'] = nil

    return require('pi.ui.picker').get_best_picker()
  end

  it('normalizes fzf-lua preferred picker to the fzf backend', function()
    assert.equal('fzf', get_best_picker('fzf-lua'))
  end)

  it('normalizes plugin-name aliases to picker backends', function()
    assert.equal('telescope', get_best_picker('telescope.nvim'))
    assert.equal('snacks', get_best_picker('snacks.nvim'))
  end)

  it('preserves canonical preferred picker names', function()
    assert.equal('fzf', get_best_picker('fzf'))
    assert.equal('telescope', get_best_picker('telescope'))
    assert.equal('snacks', get_best_picker('snacks'))
  end)

  it('keeps select as the explicit vim.ui.select fallback', function()
    assert.equal('select', get_best_picker('select'))
  end)
end)
