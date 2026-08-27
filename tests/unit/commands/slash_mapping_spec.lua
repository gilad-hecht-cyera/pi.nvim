local assert = require('luassert')
local Promise = require('pi.promise')

describe('slash command mapping', function()
  local slash
  local original_notify
  local captured_parsed
  local captured_ctx
  local prompts
  local rpc_commands

  before_each(function()
    original_notify = vim.notify
    captured_parsed = {}
    captured_ctx = {}
    prompts = {}
    rpc_commands = nil

    package.loaded['pi.commands'] = {
      get_commands = function()
        return {
          agent = { desc = 'Agent', nargs = '*' },
          review = { desc = 'Review', nargs = '*' },
          command = { desc = 'Command', nargs = '*' },
        }
      end,
      build_parsed_intent = function(name, args)
        local argv = { name }
        for _, arg in ipairs(args or {}) do
          table.insert(argv, tostring(arg))
        end
        return {
          ok = true,
          intent = {
            name = name,
            args = args or {},
            range = nil,
            source = {
              raw_args = table.concat(argv, ' '),
              argv = argv,
            },
          },
        }
      end,
      execute_parsed_intent = function(parsed)
        table.insert(captured_parsed, vim.deepcopy(parsed))
        local ctx = {
          parsed = parsed,
          intent = parsed.intent,
          args = parsed.intent.args,
          range = parsed.intent.range,
          execute = function() end,
        }
        table.insert(captured_ctx, ctx)
        return 'ok'
      end,
    }

    package.loaded['pi.rpc_client'] = {
      get = function()
        return {
          get_commands = function()
            return Promise.new():resolve({ commands = rpc_commands or {} })
          end,
          prompt = function(_, message)
            table.insert(prompts, message)
            return Promise.new():resolve({})
          end,
        }
      end,
    }

    package.loaded['pi.services.session_runtime'] = {
      open = function()
        return Promise.new():resolve({})
      end,
    }

    package.loaded['pi.log'] = {
      notify = function() end,
    }

    vim.notify = function() end

    package.loaded['pi.commands.slash'] = nil
    slash = require('pi.commands.slash')
  end)

  after_each(function()
    vim.notify = original_notify

    package.loaded['pi.commands'] = nil
    package.loaded['pi.commands.slash'] = nil
    package.loaded['pi.rpc_client'] = nil
    package.loaded['pi.services.session_runtime'] = nil
    package.loaded['pi.log'] = nil
  end)

  it('maps builtin local /help to ParsedIntent and dispatches', function()
    local slash_commands = slash.get_commands():wait()
    local cmd
    for _, entry in ipairs(slash_commands) do
      if entry.slash_cmd == '/help' then
        cmd = entry
        break
      end
    end

    assert.truthy(cmd)
    cmd.fn({})

    assert.equal(1, #captured_parsed)
    assert.same('help', captured_parsed[1].intent.name)
    assert.same({}, captured_parsed[1].intent.args)
    assert.equal(1, #captured_ctx)
  end)

  it('maps RPC slash command to Pi prompt', function()
    rpc_commands = {
      { name = 'build', description = 'Build project' },
    }

    local slash_commands = slash.get_commands():wait()
    local cmd
    for _, entry in ipairs(slash_commands) do
      if entry.slash_cmd == '/build' then
        cmd = entry
        break
      end
    end

    assert.truthy(cmd)
    cmd.fn({ '--fast' }):wait()

    assert.same({ '/build --fast' }, prompts)
  end)

  it('does not expose /session even when Pi RPC reports it', function()
    rpc_commands = {
      { name = 'session', description = 'Show session info' },
    }

    local slash_commands = slash.get_commands():wait()
    local cmd
    for _, entry in ipairs(slash_commands) do
      if entry.slash_cmd == '/session' then
        cmd = entry
        break
      end
    end

    assert.is_nil(cmd)
  end)
end)
