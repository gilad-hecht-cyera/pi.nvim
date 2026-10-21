local stub = require('luassert.stub')
local Promise = require('pi.promise')
local config = require('pi.config')
local state = require('pi.state')
local tabs = require('pi.services.tabs')
local session_runtime = require('pi.services.session_runtime')
local session_handler = require('pi.commands.handlers.session')
local tab_handler = require('pi.commands.handlers.tab')
local vanilla = require('pi.commands.handlers.vanilla')

local function user_message(id, text)
  return {
    info = { id = id, role = 'user', sessionID = 'ses' },
    parts = { { id = id .. '_p', type = 'text', text = text } },
  }
end

describe('fork routing', function()
  local stubs
  local original_target
  local saved_scope
  local saved_api_client
  local api_client

  local function add_stub(...)
    local s = stub(...)
    table.insert(stubs, s)
    return s
  end

  before_each(function()
    stubs = {}
    original_target = config.ui.tabs.fork_target
    saved_scope = state.tab_scope.swap(nil)
    saved_api_client = state.api_client
    api_client = {
      resolve_fork_entry_id = stub.new().returns(Promise.new():resolve('entry_7')),
      fork_session = stub.new().returns(Promise.new():resolve({ cancelled = true })),
    }
    state.jobs.set_api_client(api_client)
    state.session.set_active({ id = '/s/main.jsonl', title = 'Main' })
    state.renderer.set_messages({ user_message('msg_1', 'first'), user_message('msg_2', 'second') })

    add_stub(tabs, 'fork_into_tab').returns(Promise.new():resolve({ id = 2 }))
    add_stub(session_runtime, 'open').returns(Promise.new():resolve('ok'))
    add_stub(vanilla.actions, 'send_pi_command').returns(Promise.new():resolve(true))
  end)

  after_each(function()
    for _, s in ipairs(stubs) do
      s:revert()
    end
    config.ui.tabs.fork_target = original_target
    state.tab_scope.swap(saved_scope)
    state.jobs.set_api_client(saved_api_client)
  end)

  local function settle()
    vim.wait(100, function()
      return false
    end)
  end

  describe('fork_session action ([F]ork, timeline picker)', function()
    it('forks the chosen message into a new tab', function()
      config.ui.tabs.fork_target = 'tab'

      session_handler.actions.fork_session('msg_1')
      settle()

      assert.stub(api_client.resolve_fork_entry_id).was_called_with(api_client, 'msg_1')
      assert.stub(tabs.fork_into_tab).was_called_with({ entry_id = 'entry_7' })
      assert.stub(api_client.fork_session).was_not_called()
      assert.stub(session_runtime.open).was_called()
    end)

    it('defaults to the last user message', function()
      config.ui.tabs.fork_target = 'tab'

      session_handler.actions.fork_session()
      settle()

      assert.stub(api_client.resolve_fork_entry_id).was_called_with(api_client, 'msg_2')
    end)

    it('keeps the in-place fork when replacing the current session', function()
      config.ui.tabs.fork_target = 'current'

      session_handler.actions.fork_session('msg_1')
      settle()

      assert.stub(api_client.fork_session).was_called_with(api_client, '/s/main.jsonl', { messageID = 'msg_1' })
      assert.stub(tabs.fork_into_tab).was_not_called()
    end)

    it('asks by default and does nothing when dismissed', function()
      config.ui.tabs.fork_target = 'ask'
      add_stub(vim.ui, 'select').invokes(function(_, _, on_choice)
        on_choice(nil)
      end)

      session_handler.actions.fork_session('msg_1')
      settle()

      assert.stub(vim.ui.select).was_called(1)
      assert.stub(tabs.fork_into_tab).was_not_called()
      assert.stub(api_client.fork_session).was_not_called()
    end)
  end)

  describe(':Pi fork and /fork', function()
    local rpc
    local fork_messages

    before_each(function()
      fork_messages = {
        { entryId = 'e1', text = 'first prompt' },
        { entryId = 'e2', text = 'second\nprompt' },
      }
      rpc = {
        get_fork_messages = function()
          return Promise.new():resolve({ messages = fork_messages })
        end,
      }
      add_stub(require('pi.rpc_client'), 'get').returns(rpc)
    end)

    it('forwards to Pi when replacing the current session', function()
      config.ui.tabs.fork_target = 'current'

      tab_handler.actions.fork_routed({ 'arg' })

      assert.stub(vanilla.actions.send_pi_command).was_called_with('fork', { 'arg' })
      assert.stub(tabs.fork_into_tab).was_not_called()
    end)

    it('picks a message and forks it into a new tab', function()
      config.ui.tabs.fork_target = 'tab'
      local labels
      add_stub(vim.ui, 'select').invokes(function(items, opts, on_choice)
        labels = vim.tbl_map(opts.format_item, items)
        on_choice(items[2])
      end)

      tab_handler.actions.fork_routed({})
      settle()

      assert.same({ 'first prompt', 'second prompt' }, labels)
      assert.stub(tabs.fork_into_tab).was_called_with({ entry_id = 'e2' })
      assert.stub(vanilla.actions.send_pi_command).was_not_called()
    end)

    it('does nothing when the message pick is dismissed', function()
      config.ui.tabs.fork_target = 'tab'
      add_stub(vim.ui, 'select').invokes(function(_, _, on_choice)
        on_choice(nil)
      end)

      tab_handler.actions.fork_routed({})
      settle()

      assert.stub(tabs.fork_into_tab).was_not_called()
    end)

    it('warns when there is nothing to fork from', function()
      config.ui.tabs.fork_target = 'tab'
      fork_messages = {}
      add_stub(vim, 'notify')

      tab_handler.actions.fork_routed({})
      settle()

      assert.stub(vim.notify).was_called_with('[pi.nvim] No user message to fork from', vim.log.levels.WARN)
      assert.stub(tabs.fork_into_tab).was_not_called()
    end)

    it('routes both the :Pi fork command and the /fork slash command', function()
      local routed = add_stub(tab_handler.actions, 'fork_routed')
      local commands = require('pi.commands')

      commands.get_commands().fork.execute({ 'x' })
      local slash = require('pi.commands.slash').get_commands():wait()
      for _, command in ipairs(slash) do
        if command.slash_cmd == '/fork' then
          command.fn({ 'y' })
        end
      end

      assert.stub(routed).was_called_with({ 'x' })
      assert.stub(routed).was_called_with({ 'y' })
    end)
  end)
end)
