local assert = require('luassert')

describe('pi.ui.completion', function()
  local completion
  local mock_config

  before_each(function()
    mock_config = {
      get_key_for_function = function(category, key)
        local keys = {
          input_window = {
            mention = '@',
            slash_commands = '/',
            context_items = '#',
          },
        }
        return keys[category] and keys[category][key]
      end,
      ui = {
        completion = {
          file_sources = {
            enabled = true,
            max_files = 10,
            ignore_patterns = {},
          },
        },
      },
    }

    package.loaded['pi.config'] = mock_config
    package.loaded['pi.ui.completion'] = nil
    package.loaded['pi.ui.completion.files'] = nil
    package.loaded['pi.ui.completion.subagents'] = nil
    package.loaded['pi.ui.completion.commands'] = nil
    package.loaded['pi.ui.completion.context'] = nil
    package.loaded['pi.ui.completion.skills'] = nil

    completion = require('pi.ui.completion')
    completion._sources = {}
    completion._pending = {}
    completion._last_line = ''
    completion._last_col = 0
  end)

  after_each(function()
    package.loaded['pi.config'] = nil
    package.loaded['pi.ui.completion'] = nil
    package.loaded['pi.ui.completion.files'] = nil
    package.loaded['pi.ui.completion.subagents'] = nil
    package.loaded['pi.ui.completion.commands'] = nil
    package.loaded['pi.ui.completion.context'] = nil
    package.loaded['pi.ui.completion.skills'] = nil
  end)

  describe('setup', function()
    it('registers all built-in sources', function()
      local registered = {}

      package.loaded['pi.ui.completion.files'] = {
        get_source = function()
          return { name = 'files', priority = 10, complete = function() end }
        end,
      }
      package.loaded['pi.ui.completion.subagents'] = {
        get_source = function()
          return { name = 'subagents', priority = 5, complete = function() end }
        end,
      }
      package.loaded['pi.ui.completion.commands'] = {
        get_source = function()
          return { name = 'commands', priority = 8, complete = function() end }
        end,
      }
      package.loaded['pi.ui.completion.context'] = {
        get_source = function()
          return { name = 'context', priority = 1, complete = function() end }
        end,
      }
      package.loaded['pi.ui.completion.skills'] = {
        get_source = function()
          return { name = 'skills', priority = 1, complete = function() end }
        end,
      }

      package.loaded['pi.ui.completion'] = nil
      completion = require('pi.ui.completion')
      completion._sources = {}

      completion.setup()

      local sources = completion.get_sources()
      assert.are.equal(5, #sources)

      for _, s in ipairs(sources) do
        registered[s.name] = true
      end
      assert.is_true(registered['files'])
      assert.is_true(registered['subagents'])
      assert.is_true(registered['commands'])
      assert.is_true(registered['context'])
      assert.is_true(registered['skills'])
    end)

    it('sorts sources in descending priority order after setup', function()
      package.loaded['pi.ui.completion.files'] = {
        get_source = function()
          return { name = 'files', priority = 10, complete = function() end }
        end,
      }
      package.loaded['pi.ui.completion.subagents'] = {
        get_source = function()
          return { name = 'subagents', priority = 5, complete = function() end }
        end,
      }
      package.loaded['pi.ui.completion.commands'] = {
        get_source = function()
          return { name = 'commands', priority = 8, complete = function() end }
        end,
      }
      package.loaded['pi.ui.completion.context'] = {
        get_source = function()
          return { name = 'context', priority = 1, complete = function() end }
        end,
      }
      package.loaded['pi.ui.completion.skills'] = {
        get_source = function()
          return { name = 'skills', priority = 1, complete = function() end }
        end,
      }

      package.loaded['pi.ui.completion'] = nil
      completion = require('pi.ui.completion')
      completion._sources = {}

      completion.setup()

      local sources = completion.get_sources()
      for i = 1, #sources - 1 do
        assert.is_true((sources[i].priority or 0) >= (sources[i + 1].priority or 0))
      end
    end)

    it('sources without priority are treated as priority 0', function()
      package.loaded['pi.ui.completion.files'] = {
        get_source = function()
          return { name = 'files', complete = function() end } -- no priority
        end,
      }
      package.loaded['pi.ui.completion.subagents'] = {
        get_source = function()
          return { name = 'subagents', priority = 5, complete = function() end }
        end,
      }
      package.loaded['pi.ui.completion.commands'] = {
        get_source = function()
          return { name = 'commands', complete = function() end } -- no priority
        end,
      }
      package.loaded['pi.ui.completion.context'] = {
        get_source = function()
          return { name = 'context', complete = function() end } -- no priority
        end,
      }
      package.loaded['pi.ui.completion.skills'] = {
        get_source = function()
          return { name = 'skills', priority = 1, complete = function() end }
        end,
      }

      package.loaded['pi.ui.completion'] = nil
      completion = require('pi.ui.completion')
      completion._sources = {}

      assert.has_no.errors(function()
        completion.setup()
      end)

      local sources = completion.get_sources()
      assert.are.equal(5, #sources)
    end)
  end)
end)
