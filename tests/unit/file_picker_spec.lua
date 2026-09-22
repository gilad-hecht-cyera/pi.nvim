local assert = require('luassert')

describe('pi.ui.file_picker', function()
  local original_schedule
  local original_picker
  local original_snacks

  before_each(function()
    original_schedule = vim.schedule
    original_picker = package.loaded['pi.ui.picker']
    original_snacks = package.loaded.snacks

    vim.schedule = function(callback)
      callback()
    end
    package.loaded['pi.ui.picker'] = {
      get_best_picker = function()
        return 'snacks'
      end,
    }
    package.loaded['pi.ui.file_picker'] = nil
  end)

  after_each(function()
    vim.schedule = original_schedule
    package.loaded['pi.ui.picker'] = original_picker
    package.loaded.snacks = original_snacks
    package.loaded['pi.ui.file_picker'] = nil
  end)

  it('prefilters Snacks with the referenced path', function()
    local picker_opts
    package.loaded.snacks = {
      picker = {
        files = function(opts)
          picker_opts = opts
        end,
      },
    }

    require('pi.ui.file_picker').pick(function() end, nil, 'partial/main.rs')

    assert.equal('partial/main.rs', picker_opts.pattern)
  end)

  it('returns the selected file while using a query', function()
    local picker_opts
    local selected
    package.loaded.snacks = {
      picker = {
        files = function(opts)
          picker_opts = opts
        end,
      },
    }

    require('pi.ui.file_picker').pick(function(file)
      selected = file
    end, nil, 'main.rs')
    picker_opts.confirm({
      selected = function()
        return { { file = 'crates/server/src/main.rs' } }
      end,
      close = function() end,
    })

    assert.equal('crates/server/src/main.rs', selected.path)
    assert.equal('main.rs', selected.name)
  end)
end)
