local stub = require('luassert.stub')
local Promise = require('pi.promise')
local PiProcess = require('pi.pi_process')
local RpcClient = require('pi.rpc_client')
local event_adapter = require('pi.event_adapter')
local tab_runtimes = require('pi.tab_runtimes')

local function fake_process(runtime, opts)
  opts = opts or {}
  local process = runtime.process
  process.stop = stub.new()
  process.is_running = function()
    return opts.running ~= false
  end
  return process
end

describe('tab_runtimes', function()
  before_each(function()
    tab_runtimes._reset()
  end)

  after_each(function()
    tab_runtimes._reset()
  end)

  describe('registry', function()
    it('creates the first runtime lazily and reuses it', function()
      assert.is_nil(tab_runtimes.active_id())

      local first = tab_runtimes.active()

      assert.equal(first, tab_runtimes.active())
      assert.equal(first.id, tab_runtimes.active_id())
      assert.equal(1, #tab_runtimes.list())
    end)

    it('routes PiProcess.get and RpcClient.get to the active runtime', function()
      local first = tab_runtimes.create()
      local second = tab_runtimes.create()

      assert.equal(first.process, PiProcess.get())
      assert.equal(first.rpc_client, RpcClient.get())

      tab_runtimes.set_active(second.id)

      assert.equal(second.process, PiProcess.get())
      assert.equal(second.rpc_client, RpcClient.get())
    end)

    it('gives each runtime its own process and client', function()
      local first = tab_runtimes.create()
      local second = tab_runtimes.create()

      assert.are_not.equal(first.process, second.process)
      assert.are_not.equal(first.rpc_client, second.rpc_client)
      assert.equal(first.process, first.rpc_client.process)
      assert.equal(second.process, second.rpc_client.process)
    end)

    it('keeps the first runtime active when more are created', function()
      local first = tab_runtimes.create()
      tab_runtimes.create()

      assert.equal(first.id, tab_runtimes.active_id())
    end)

    it('rejects activating an unknown id', function()
      local first = tab_runtimes.create()

      assert.is_false(tab_runtimes.set_active(999))
      assert.equal(first.id, tab_runtimes.active_id())
    end)

    it('passes per-tab args and cwd to the process', function()
      local runtime = tab_runtimes.create({ cwd = '/tmp', extra_args = { '--fork', '/tmp/s.jsonl' } })

      assert.same({ '--fork', '/tmp/s.jsonl' }, runtime.process.extra_args)
      assert.equal('/tmp', runtime.process.pinned_cwd)
    end)
  end)

  describe('close', function()
    it('stops an idle runtime and removes it', function()
      local runtime = tab_runtimes.create()
      local process = fake_process(runtime)
      local abort = stub(runtime.rpc_client, 'abort')

      assert.is_true(tab_runtimes.close(runtime.id))

      assert.stub(process.stop).was_called(1)
      assert.stub(abort).was_not_called()
      assert.is_nil(tab_runtimes.get(runtime.id))
    end)

    it('returns false for an unknown id', function()
      assert.is_false(tab_runtimes.close(42))
    end)

    it('activates the next runtime, or the previous one when closing the last', function()
      local a = tab_runtimes.create()
      local b = tab_runtimes.create()
      local c = tab_runtimes.create()
      for _, runtime in ipairs({ a, b, c }) do
        fake_process(runtime)
      end

      tab_runtimes.set_active(b.id)
      tab_runtimes.close(b.id)
      assert.equal(c.id, tab_runtimes.active_id())

      tab_runtimes.close(c.id)
      assert.equal(a.id, tab_runtimes.active_id())

      tab_runtimes.close(a.id)
      assert.is_nil(tab_runtimes.active_id())
    end)

    it('does not change the active runtime when closing a background one', function()
      local a = tab_runtimes.create()
      local b = tab_runtimes.create()
      fake_process(b)

      tab_runtimes.close(b.id)

      assert.equal(a.id, tab_runtimes.active_id())
    end)

    it('aborts a streaming runtime before stopping it', function()
      local runtime = tab_runtimes.create()
      local process = fake_process(runtime)
      runtime.rpc_client.streaming = true
      local abort_promise = Promise.new()
      stub(runtime.rpc_client, 'abort').returns(abort_promise)

      tab_runtimes.close(runtime.id)

      assert.stub(runtime.rpc_client.abort).was_called(1)
      assert.stub(process.stop).was_not_called()

      abort_promise:resolve(true)
      vim.wait(100, function()
        return #process.stop.calls > 0
      end)

      assert.stub(process.stop).was_called(1)
    end)

    it('stops a streaming runtime even if abort never answers', function()
      local runtime = tab_runtimes.create()
      local process = fake_process(runtime)
      runtime.rpc_client.streaming = true
      stub(runtime.rpc_client, 'abort').returns(Promise.new())

      tab_runtimes.close(runtime.id)

      local stopped = vim.wait(3000, function()
        return #process.stop.calls > 0
      end)
      assert.is_true(stopped)
      assert.stub(process.stop).was_called(1)
    end)

    it('skips abort when the streaming process already exited', function()
      local runtime = tab_runtimes.create()
      local process = fake_process(runtime, { running = false })
      runtime.rpc_client.streaming = true
      local abort = stub(runtime.rpc_client, 'abort')

      tab_runtimes.close(runtime.id)

      assert.stub(abort).was_not_called()
      assert.stub(process.stop).was_called(1)
    end)
  end)

  describe('set_order', function()
    it('reorders tabs', function()
      local a = tab_runtimes.create()
      local b = tab_runtimes.create()
      local c = tab_runtimes.create()

      assert.is_true(tab_runtimes.set_order({ c.id, a.id, b.id }))

      assert.same({ c.id, a.id, b.id }, vim.tbl_map(function(r)
        return r.id
      end, tab_runtimes.list()))
    end)

    it('rejects missing, unknown, or duplicate ids', function()
      local a = tab_runtimes.create()
      local b = tab_runtimes.create()

      assert.is_false(tab_runtimes.set_order({ a.id }))
      assert.is_false(tab_runtimes.set_order({ a.id, 99 }))
      assert.is_false(tab_runtimes.set_order({ a.id, a.id }))
      assert.same({ a.id, b.id }, vim.tbl_map(function(r)
        return r.id
      end, tab_runtimes.list()))
    end)
  end)

  it('stop_all stops every runtime', function()
    local a = tab_runtimes.create()
    local b = tab_runtimes.create()
    local pa = fake_process(a)
    local pb = fake_process(b)

    tab_runtimes.stop_all()

    assert.stub(pa.stop).was_called(1)
    assert.stub(pb.stop).was_called(1)
  end)

  describe('background tab events', function()
    local handle_event

    before_each(function()
      handle_event = stub(event_adapter, 'handle_event')
    end)

    after_each(function()
      handle_event:revert()
    end)

    it('forwards events from the active tab to the event adapter', function()
      local active = tab_runtimes.create()

      active.process:_emit({ type = 'message_start' })

      assert.stub(handle_event).was_called(1)
    end)

    it('drops events from background tabs but still tracks streaming', function()
      tab_runtimes.create()
      local background = tab_runtimes.create()

      background.process:_emit({ type = 'agent_start' })
      assert.is_true(background.rpc_client.streaming)

      background.process:_emit({ type = 'extension_ui_request', method = 'notify', message = 'x' })
      background.process:_emit({ type = 'agent_settled' })

      assert.is_false(background.rpc_client.streaming)
      assert.stub(handle_event).was_not_called()
    end)

    it('resolves pending requests for background tabs', function()
      tab_runtimes.create()
      local background = tab_runtimes.create()
      stub(background.process, 'send').returns(Promise.new():resolve(true))

      local promise = background.rpc_client:request({ type = 'get_state', id = 'bg-1' })
      background.process:_emit({ type = 'response', id = 'bg-1', success = true, data = { ok = true } })

      assert.same({ ok = true }, promise:wait(100))
    end)
  end)

  describe('stream tracking', function()
    local handle_event

    before_each(function()
      handle_event = stub(event_adapter, 'handle_event')
    end)

    after_each(function()
      handle_event:revert()
    end)

    local function assistant_start()
      return { type = 'message_start', message = { role = 'assistant', timestamp = 1 } }
    end

    it('keeps events of the in-progress assistant message, active or not', function()
      local active = tab_runtimes.create()
      local background = tab_runtimes.create()

      for _, runtime in ipairs({ active, background }) do
        runtime.process:_emit(assistant_start())
        runtime.process:_emit({ type = 'message_update', assistantMessageEvent = { type = 'text_delta', delta = 'a' } })
        runtime.process:_emit({ type = 'message_update', assistantMessageEvent = { type = 'text_delta', delta = 'b' } })
        assert.equal(3, #runtime.rpc_client.stream_events)
      end
    end)

    it('clears the buffer when the message ends or the run stops', function()
      local runtime = tab_runtimes.create()

      for _, ending in ipairs({ 'message_end', 'agent_end', 'agent_settled' }) do
        runtime.process:_emit(assistant_start())
        runtime.process:_emit({ type = ending })
        assert.is_nil(runtime.rpc_client.stream_events, ending)
      end
    end)

    it('does not buffer user messages or updates without a start', function()
      local runtime = tab_runtimes.create()

      runtime.process:_emit({ type = 'message_update', assistantMessageEvent = { type = 'text_delta' } })
      assert.is_nil(runtime.rpc_client.stream_events)

      runtime.process:_emit(assistant_start())
      runtime.process:_emit({ type = 'message_start', message = { role = 'user' } })
      assert.is_nil(runtime.rpc_client.stream_events)
    end)
  end)

  describe('queued prompts', function()
    local state = require('pi.state')
    local saved_scope

    local function queued_prompts()
      return vim.tbl_map(function(item)
        return item.prompt
      end, (state.queued_user_messages or {}).ses_a or {})
    end

    local function queue_update(steering, follow_up)
      return { type = 'queue_update', steering = steering or {}, followUp = follow_up or {} }
    end

    before_each(function()
      saved_scope = state.tab_scope.swap({ active_session = { id = 'ses_a' } })
      state.session.clear_queued_user_messages()
    end)

    after_each(function()
      state.session.clear_queued_user_messages()
      state.tab_scope.swap(saved_scope)
    end)

    it('shows a prompt until Pi answers, and drops it when Pi starts a run with it', function()
      local client = tab_runtimes.create().rpc_client

      local id = client:queue_prompt('hello')
      assert.same({ 'hello' }, queued_prompts())

      client:settle_queued_prompt(id, true)
      assert.same({}, queued_prompts())
    end)

    it('drops a rejected prompt', function()
      local client = tab_runtimes.create().rpc_client
      local id = client:queue_prompt('rejected')

      client:settle_queued_prompt(id, false)

      assert.same({}, queued_prompts())
    end)

    it('keeps accepted prompts while Pi reports them queued and drops them in delivery order', function()
      local runtime = tab_runtimes.create()
      local client = runtime.rpc_client
      local first = client:queue_prompt('first')
      local second = client:queue_prompt('second')

      runtime.process:_emit(queue_update({ 'first' }))
      client:settle_queued_prompt(first, true)
      runtime.process:_emit(queue_update({ 'first', 'second' }))
      client:settle_queued_prompt(second, true)
      assert.same({ 'first', 'second' }, queued_prompts())

      runtime.process:_emit(queue_update({ 'second' }))
      assert.same({ 'second' }, queued_prompts())

      runtime.process:_emit(queue_update({}, {}))
      assert.same({}, queued_prompts())
    end)

    it('counts follow-up messages as queued', function()
      local runtime = tab_runtimes.create()
      local id = runtime.rpc_client:queue_prompt('later')

      runtime.process:_emit(queue_update({}, { 'later' }))
      runtime.rpc_client:settle_queued_prompt(id, true)

      assert.same({ 'later' }, queued_prompts())
    end)

    it('does not drop a prompt Pi has not answered yet when the queue drains', function()
      local runtime = tab_runtimes.create()
      local client = runtime.rpc_client
      local first = client:queue_prompt('first')
      runtime.process:_emit(queue_update({ 'first' }))
      client:settle_queued_prompt(first, true)
      local second = client:queue_prompt('second')

      runtime.process:_emit(queue_update({}))
      assert.same({ 'second' }, queued_prompts())

      runtime.process:_emit(queue_update({ 'second' }))
      client:settle_queued_prompt(second, true)
      assert.same({ 'second' }, queued_prompts())
    end)

    it('tracks a background tab queue without touching the active tab', function()
      local active = tab_runtimes.create()
      local background = tab_runtimes.create()
      active.rpc_client:queue_prompt('active prompt')

      local id = background.rpc_client:queue_prompt('background prompt')
      background.process:_emit(queue_update({ 'background prompt' }))
      background.rpc_client:settle_queued_prompt(id, true)
      assert.same({ 'active prompt' }, queued_prompts())

      background.process:_emit(queue_update({}))
      assert.same(0, #background.rpc_client.queued_prompts)
      assert.same({ 'active prompt' }, queued_prompts())
    end)

    it('clears the queue when the process exits', function()
      local runtime = tab_runtimes.create()
      runtime.rpc_client:queue_prompt('pending')

      runtime.process:_emit({ type = 'process_exit', code = 1 })

      assert.same({}, queued_prompts())
      assert.same({}, runtime.rpc_client.queued_prompts)
    end)
  end)
end)
