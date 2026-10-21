local stub = require('luassert.stub')
local Promise = require('pi.promise')
local state = require('pi.state')
local event_adapter = require('pi.event_adapter')
local tab_runtimes = require('pi.tab_runtimes')
local RpcClient = require('pi.rpc_client')

local function match_fork_name(title)
  return require('luassert.match').matches('^FORK %d+ ' .. vim.pesc(title) .. '$')
end

describe('services.tabs', function()
  local tabs
  local renderer
  local input_window
  local session_runtime
  local original_modules
  local saved_scope
  local saved_windows
  local created_sessions

  local function fake_runtime(runtime)
    runtime.process.stop = function() end
    runtime.process.is_running = function()
      return true
    end
    return runtime
  end

  local function new_runtime()
    return fake_runtime(tab_runtimes.create())
  end

  before_each(function()
    original_modules = {
      renderer = package.loaded['pi.ui.renderer'],
      input_window = package.loaded['pi.ui.input_window'],
      session_runtime = package.loaded['pi.services.session_runtime'],
    }

    renderer = { callbacks = {}, full_renders = 0 }
    function renderer.after_session_render(session_id, callback)
      renderer.callbacks[session_id] = renderer.callbacks[session_id] or {}
      table.insert(renderer.callbacks[session_id], callback)
    end
    function renderer.render_full_session()
      renderer.full_renders = renderer.full_renders + 1
      return Promise.new():resolve(nil)
    end
    function renderer.fire(session_id)
      for _, callback in ipairs(renderer.callbacks[session_id] or {}) do
        callback()
      end
      renderer.callbacks[session_id] = nil
    end

    input_window = { contents = {} }
    function input_window.set_content(text)
      table.insert(input_window.contents, text)
    end

    created_sessions = 0
    session_runtime = {
      create_new_session = function()
        created_sessions = created_sessions + 1
        return Promise.new():resolve({ id = 'ses_new_' .. created_sessions })
      end,
    }

    package.loaded['pi.ui.renderer'] = renderer
    package.loaded['pi.ui.input_window'] = input_window
    package.loaded['pi.services.session_runtime'] = session_runtime
    package.loaded['pi.services.tabs'] = nil
    tabs = require('pi.services.tabs')

    tab_runtimes._reset()
    saved_scope = state.tab_scope.swap(nil)
    saved_windows = state.windows
  end)

  after_each(function()
    tabs._reset()
    tab_runtimes._reset()
    state.tab_scope.swap(saved_scope)
    state.ui.set_windows(saved_windows)
    package.loaded['pi.ui.renderer'] = original_modules.renderer
    package.loaded['pi.ui.input_window'] = original_modules.input_window
    package.loaded['pi.services.session_runtime'] = original_modules.session_runtime
    package.loaded['pi.services.tabs'] = nil
  end)

  describe('switch', function()
    it('saves the outgoing tab state and starts the new tab from defaults', function()
      local a = new_runtime()
      local b = new_runtime()
      state.session.set_active({ id = 'ses_a' })
      state.renderer.set_cost(2)

      assert.is_true(tabs.switch(b.id))

      assert.equal(b.id, tabs.active_id())
      assert.equal(b.rpc_client, RpcClient.get())
      assert.is_nil(state.active_session)
      assert.equal(0, state.cost)

      state.session.set_active({ id = 'ses_b' })
      tabs.switch(a.id)

      assert.equal('ses_a', state.active_session.id)
      assert.equal(2, state.cost)

      tabs.switch(b.id)
      assert.equal('ses_b', state.active_session.id)
    end)

    it('is a no-op for the active tab and fails for unknown tabs', function()
      local a = new_runtime()
      state.session.set_active({ id = 'ses_a' })

      assert.is_true(tabs.switch(a.id))
      assert.equal('ses_a', state.active_session.id)

      assert.is_false(tabs.switch(999))
      assert.equal(a.id, tabs.active_id())
    end)

    it('keeps a separate input draft per tab', function()
      local a = new_runtime()
      local b = new_runtime()
      state.ui.set_windows({ input_buf = 1 })
      state.ui.set_input_content({ 'draft for a' })

      tabs.switch(b.id)
      assert.same(state.tab_scope.defaults().input_content, input_window.contents[#input_window.contents])

      state.ui.set_input_content({ 'draft for b' })
      tabs.switch(a.id)

      assert.same({ 'draft for a' }, input_window.contents[#input_window.contents])
      assert.same({ 'draft for a' }, state.input_content)
    end)

    it('replays the in-progress message after the session re-renders', function()
      local a = new_runtime()
      local b = new_runtime()
      state.session.set_active({ id = 'ses_a' })
      tabs.switch(b.id)
      state.session.set_active({ id = 'ses_b' })
      local stream = {
        { type = 'message_start', message = { role = 'assistant' } },
        { type = 'message_update', assistantMessageEvent = { type = 'text_delta', delta = 'x' } },
      }
      a.rpc_client.stream_events = stream
      local handle_event = stub(event_adapter, 'handle_event')

      tabs.switch(a.id)
      assert.stub(handle_event).was_not_called()

      renderer.fire('ses_a')
      handle_event:revert()

      assert.stub(handle_event).was_called(2)
      assert.stub(handle_event).was_called_with(stream[1])
      assert.stub(handle_event).was_called_with(stream[2])
    end)

    it('skips the replay if the tab is no longer active when the render finishes', function()
      local a = new_runtime()
      local b = new_runtime()
      state.session.set_active({ id = 'ses_a' })
      tabs.switch(b.id)
      state.session.set_active({ id = 'ses_b' })
      a.rpc_client.stream_events = { { type = 'message_start', message = { role = 'assistant' } } }

      tabs.switch(a.id)
      tabs.switch(b.id)
      local handle_event = stub(event_adapter, 'handle_event')
      renderer.fire('ses_a')
      handle_event:revert()

      assert.stub(handle_event).was_not_called()
    end)

    it('re-renders a tab switched into mid-run once it settles', function()
      local a = new_runtime()
      local b = new_runtime()
      b.rpc_client.streaming = true

      tabs.switch(b.id)
      b.process:_emit({ type = 'agent_settled' })
      b.process:_emit({ type = 'agent_settled' })

      assert.equal(1, renderer.full_renders)
      assert.equal(b.id, tabs.active_id())
      assert.is_truthy(a)
    end)

    it('does not re-render a mid-run tab that was switched away from', function()
      local a = new_runtime()
      local b = new_runtime()
      b.rpc_client.streaming = true

      tabs.switch(b.id)
      tabs.switch(a.id)
      b.process:_emit({ type = 'agent_settled' })

      assert.equal(0, renderer.full_renders)
    end)
  end)

  describe('new', function()
    it('creates a tab with a fresh session and switches to it', function()
      local a = new_runtime()
      state.session.set_active({ id = 'ses_a' })

      local runtime = tabs.new():wait(100)

      assert.are_not.equal(a.id, runtime.id)
      assert.equal(runtime.id, tabs.active_id())
      assert.equal('ses_new_1', state.active_session.id)

      tabs.switch(a.id)
      assert.equal('ses_a', state.active_session.id)
    end)

    it('passes runtime options through to the new process', function()
      new_runtime()

      local runtime = tabs.new({ extra_args = { '--fork', '/tmp/s.jsonl' } }):wait(100)

      assert.same({ '--fork', '/tmp/s.jsonl' }, runtime.process.extra_args)
    end)
  end)

  describe('close', function()
    it('switches to the neighbor and loads its state when closing the active tab', function()
      local a = new_runtime()
      local b = new_runtime()
      state.session.set_active({ id = 'ses_a' })
      tabs.switch(b.id)
      state.session.set_active({ id = 'ses_b' })

      assert.is_true(tabs.close(b.id):wait(100))

      assert.equal(a.id, tabs.active_id())
      assert.equal('ses_a', state.active_session.id)
      assert.is_nil(tab_runtimes.get(b.id))
    end)

    it('keeps the active tab when closing a background one', function()
      local a = new_runtime()
      local b = new_runtime()
      state.session.set_active({ id = 'ses_a' })

      tabs.close(b.id):wait(100)

      assert.equal(a.id, tabs.active_id())
      assert.equal('ses_a', state.active_session.id)
      assert.equal(1, #tabs.list())
    end)

    it('replaces the last tab with a new empty one', function()
      local a = new_runtime()
      state.session.set_active({ id = 'ses_a' })
      state.renderer.set_cost(5)
      stub(tab_runtimes, 'create').invokes(function(opts)
        tab_runtimes.create:revert()
        return fake_runtime(tab_runtimes.create(opts))
      end)

      assert.is_true(tabs.close(a.id):wait(100))

      assert.equal(1, #tabs.list())
      assert.are_not.equal(a.id, tabs.active_id())
      assert.equal('ses_new_1', state.active_session.id)
      assert.equal(0, state.cost)
    end)

    it('returns false for an unknown tab', function()
      new_runtime()
      assert.is_false(tabs.close(42):wait(100))
    end)
  end)

  describe('navigation', function()
    it('cycles forward and backward with wrap-around', function()
      local a = new_runtime()
      local b = new_runtime()
      local c = new_runtime()

      tabs.cycle(1)
      assert.equal(b.id, tabs.active_id())
      tabs.cycle(1)
      assert.equal(c.id, tabs.active_id())
      tabs.cycle(1)
      assert.equal(a.id, tabs.active_id())
      tabs.cycle(-1)
      assert.equal(c.id, tabs.active_id())
    end)

    it('does nothing with a single tab', function()
      local a = new_runtime()

      assert.is_false(tabs.cycle(1))
      assert.equal(a.id, tabs.active_id())
    end)

    it('goes to a tab by its position', function()
      new_runtime()
      local b = new_runtime()

      assert.is_true(tabs.go_to(2))
      assert.equal(b.id, tabs.active_id())
      assert.is_false(tabs.go_to(5))
      assert.equal(b.id, tabs.active_id())
    end)
  end)

  describe('list_view', function()
    it('lists tabs in order with titles, activity, and running status', function()
      local a = new_runtime()
      local b = new_runtime()
      state.session.set_active({ id = 'ses_a', title = 'Long task' })
      tabs.switch(b.id)
      a.rpc_client.streaming = true

      local views = tabs.list_view()

      assert.same({
        { id = a.id, index = 1, title = 'Long task', running = true, active = false },
        { id = b.id, index = 2, title = 'New session', running = false, active = true },
      }, views)
    end)

    it('publishes the view to the store on switch', function()
      new_runtime()
      local b = new_runtime()

      tabs.switch(b.id)

      assert.equal(2, #state.tabs)
      assert.is_true(state.tabs[2].active)
    end)

    it('republishes when a background tab starts or settles', function()
      local a = new_runtime()
      local b = new_runtime()
      tabs.publish()
      tabs.switch(b.id)

      a.process:_emit({ type = 'agent_start' })
      assert.is_true(state.tabs[1].running)

      a.process:_emit({ type = 'agent_settled' })
      assert.is_false(state.tabs[1].running)
    end)

    it('keeps background session renames', function()
      local a = new_runtime()
      local b = new_runtime()
      state.session.set_active({ id = 'ses_a', title = 'Old' })
      tabs.publish()
      tabs.switch(b.id)

      a.process:_emit({ type = 'session_info_changed', name = 'Renamed in background' })

      assert.equal('Renamed in background', state.tabs[1].title)
      tabs.switch(a.id)
      assert.equal('Renamed in background', state.active_session.title)
    end)
  end)

  describe('find_by_session', function()
    it('finds active and background owners', function()
      local a = new_runtime()
      local b = new_runtime()
      state.session.set_active({ id = '/s/a.jsonl' })
      tabs.switch(b.id)
      state.session.set_active({ id = '/s/b.jsonl' })

      assert.equal(a.id, tabs.find_by_session('/s/a.jsonl'))
      assert.equal(b.id, tabs.find_by_session('/s/b.jsonl'))
      assert.is_nil(tabs.find_by_session('/s/other.jsonl'))
      assert.is_nil(tabs.find_by_session(nil))
    end)
  end)

  describe('fork_into_tab', function()
    local session_module
    local source_file
    local new_tab_rpc

    local function stub_new_tab(rpc_overrides)
      stub(tab_runtimes, 'create').invokes(function(opts)
        tab_runtimes.create:revert()
        local runtime = fake_runtime(tab_runtimes.create(opts))
        for name, value in pairs(rpc_overrides) do
          runtime.rpc_client[name] = value
        end
        new_tab_rpc = runtime.rpc_client
        return runtime
      end)
    end

    local function resolved(value)
      return function()
        return Promise.new():resolve(value)
      end
    end

    local function sequence(...)
      local values = { ... }
      local i = 0
      return function()
        i = i + 1
        return Promise.new():resolve(values[math.min(i, #values)])
      end
    end

    before_each(function()
      source_file = vim.fn.tempname() .. '.jsonl'
      vim.fn.writefile({ '{}' }, source_file)
      session_module = package.loaded['pi.session']
      package.loaded['pi.session'] = {
        get_by_id = function(id)
          return Promise.new():resolve({ id = id, title = 'Forked' })
        end,
      }
      new_tab_rpc = nil
    end)

    after_each(function()
      package.loaded['pi.session'] = session_module
      vim.fn.delete(source_file)
    end)

    it('forks the active session at its current position via --fork', function()
      local source = new_runtime()
      state.session.set_active({ id = source_file, title = 'Long task' })
      stub(source.rpc_client, 'get_state').returns(Promise.new():resolve({ sessionFile = source_file }))
      stub_new_tab({
        get_state = resolved({ sessionFile = '/forked.jsonl' }),
        set_session_name = stub.new().returns(Promise.new():resolve(true)),
        fork = stub.new(),
      })

      local runtime = tabs.fork_current():wait(1000)

      assert.same({ '--fork', source_file }, runtime.process.extra_args)
      assert.equal(runtime.id, tabs.active_id())
      assert.equal('/forked.jsonl', state.active_session.id)
      assert.stub(new_tab_rpc.fork).was_not_called()
      assert.stub(new_tab_rpc.set_session_name).was_called_with(new_tab_rpc, match_fork_name('Long task'))
      assert.equal(0, created_sessions)
    end)

    it('forks from an earlier entry in the new process and deletes the intermediate copy', function()
      local copy = vim.fn.tempname() .. '.jsonl'
      vim.fn.writefile({ '{}' }, copy)
      local source = new_runtime()
      stub(source.rpc_client, 'get_state').returns(Promise.new():resolve({ sessionFile = source_file }))
      stub(source.rpc_client, 'fork')
      stub_new_tab({
        get_state = sequence({ sessionFile = copy }, { sessionFile = '/entry-fork.jsonl' }),
        fork = stub.new().returns(Promise.new():resolve({ text = 'first prompt\nsecond line', cancelled = false })),
        set_session_name = stub.new().returns(Promise.new():resolve(true)),
      })

      tabs.fork_into_tab({ entry_id = 'entry_42' }):wait(1000)

      assert.stub(new_tab_rpc.fork).was_called_with(new_tab_rpc, 'entry_42')
      assert.stub(source.rpc_client.fork).was_not_called()
      assert.equal(0, vim.fn.filereadable(copy))
      assert.equal(1, vim.fn.filereadable(source_file))
      assert.equal('/entry-fork.jsonl', state.active_session.id)
      assert.same({ 'first prompt', 'second line' }, state.input_content)
    end)

    it('keeps the intermediate copy when the entry fork is cancelled', function()
      local copy = vim.fn.tempname() .. '.jsonl'
      vim.fn.writefile({ '{}' }, copy)
      local source = new_runtime()
      stub(source.rpc_client, 'get_state').returns(Promise.new():resolve({ sessionFile = source_file }))
      stub_new_tab({
        get_state = resolved({ sessionFile = copy }),
        fork = stub.new().returns(Promise.new():resolve({ cancelled = true })),
        set_session_name = stub.new().returns(Promise.new():resolve(true)),
      })

      tabs.fork_into_tab({ entry_id = 'entry_42' }):wait(1000)

      assert.equal(1, vim.fn.filereadable(copy))
      assert.equal(copy, state.active_session.id)
      vim.fn.delete(copy)
    end)

    it('falls back to the current-position fork when the entry fork fails', function()
      local copy = vim.fn.tempname() .. '.jsonl'
      vim.fn.writefile({ '{}' }, copy)
      local source = new_runtime()
      stub(source.rpc_client, 'get_state').returns(Promise.new():resolve({ sessionFile = source_file }))
      stub_new_tab({
        get_state = resolved({ sessionFile = copy }),
        fork = stub.new().returns(Promise.new():reject('bad entry')),
        set_session_name = stub.new().returns(Promise.new():resolve(true)),
      })
      local notify = stub(vim, 'notify')

      tabs.fork_into_tab({ entry_id = 'entry_42' }):wait(1000)
      notify:revert()

      assert.equal(copy, state.active_session.id)
      assert.equal(1, vim.fn.filereadable(copy))
      assert.stub(notify).was_called()
      vim.fn.delete(copy)
    end)

    it('forks a given session file instead of the active one', function()
      local source = new_runtime()
      stub(source.rpc_client, 'get_state')
      stub_new_tab({
        get_state = resolved({ sessionFile = '/forked.jsonl' }),
        set_session_name = stub.new().returns(Promise.new():resolve(true)),
      })

      local runtime = tabs.fork_into_tab({ source_path = source_file }):wait(1000)

      assert.same({ '--fork', source_file }, runtime.process.extra_args)
      assert.stub(source.rpc_client.get_state).was_not_called()
    end)

    it('refuses when the source session has not been written yet', function()
      local source = new_runtime()
      stub(source.rpc_client, 'get_state').returns(Promise.new():resolve({ sessionFile = '/does/not/exist.jsonl' }))

      local ok, err = pcall(function()
        return tabs.fork_current():wait(1000)
      end)

      assert.is_false(ok)
      assert.matches('Nothing to fork yet', tostring(err))
      assert.equal(1, #tabs.list())
      assert.equal(source.id, tabs.active_id())
    end)
  end)

  describe('choose_fork_target', function()
    local config = require('pi.config')
    local original_target
    local calls

    local function handlers()
      return {
        tab = function()
          table.insert(calls, 'tab')
        end,
        current = function()
          table.insert(calls, 'current')
        end,
        cancel = function()
          table.insert(calls, 'cancel')
        end,
      }
    end

    before_each(function()
      original_target = config.ui.tabs.fork_target
      calls = {}
    end)

    after_each(function()
      config.ui.tabs.fork_target = original_target
    end)

    it('defaults to asking', function()
      assert.equal('ask', config.defaults.ui.tabs.fork_target)
    end)

    it('goes straight to the configured target without asking', function()
      local select = stub(vim.ui, 'select')

      config.ui.tabs.fork_target = 'tab'
      tabs.choose_fork_target(handlers())
      config.ui.tabs.fork_target = 'current'
      tabs.choose_fork_target(handlers())
      select:revert()

      assert.same({ 'tab', 'current' }, calls)
      assert.stub(select).was_not_called()
    end)

    for _, case in ipairs({
      { choice = 'New tab', expected = 'tab' },
      { choice = 'Replace current session', expected = 'current' },
      { choice = nil, expected = 'cancel' },
    }) do
      it('asks and follows the answer: ' .. tostring(case.choice), function()
        config.ui.tabs.fork_target = 'ask'
        local offered
        local select = stub(vim.ui, 'select').invokes(function(items, _, on_choice)
          offered = items
          on_choice(case.choice)
        end)

        tabs.choose_fork_target(handlers())
        select:revert()

        assert.same({ 'New tab', 'Replace current session' }, offered)
        assert.same({ case.expected }, calls)
      end)
    end
  end)
end)
