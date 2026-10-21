local stub = require('luassert.stub')
local Promise = require('pi.promise')
local commands = require('pi.commands')
local tabs = require('pi.services.tabs')
local session_runtime = require('pi.services.session_runtime')

describe('tab command', function()
  local stubs

  local function run(args)
    return commands.execute_parsed_intent(commands.build_parsed_intent('tab', args))
  end

  before_each(function()
    stubs = {
      stub(tabs, 'new').returns(Promise.new():resolve({ id = 2 })),
      stub(tabs, 'fork_current').returns(Promise.new():resolve({ id = 3 })),
      stub(tabs, 'cycle').returns(true),
      stub(tabs, 'close_active').returns(Promise.new():resolve(true)),
      stub(tabs, 'go_to').returns(true),
      stub(session_runtime, 'open').returns(Promise.new():resolve('ok')),
      stub(vim, 'notify'),
    }
  end)

  after_each(function()
    for _, s in ipairs(stubs) do
      s:revert()
    end
  end)

  it('is registered with its subcommands for completion', function()
    local def = commands.get_commands().tab

    assert.is_not_nil(def)
    assert.same({ 'new', 'fork', 'next', 'prev', 'close', 'goto' }, def.completions)
  end)

  it('opens a new tab and focuses the input', function()
    run({ 'new' })
    vim.wait(100, function()
      return #session_runtime.open.calls > 0
    end)

    assert.stub(tabs.new).was_called(1)
    assert.stub(session_runtime.open).was_called_with({ new_session = false, focus = 'input', start_insert = true })
  end)

  it('forks into a new tab', function()
    run({ 'fork' })
    vim.wait(100, function()
      return #session_runtime.open.calls > 0
    end)

    assert.stub(tabs.fork_current).was_called(1)
    assert.stub(session_runtime.open).was_called(1)
  end)

  it('reports fork failures instead of raising', function()
    tabs.fork_current:revert()
    stub(tabs, 'fork_current').returns(Promise.new():reject('Nothing to fork yet'))

    run({ 'fork' })
    vim.wait(100, function()
      return #vim.notify.calls > 0
    end)

    assert.stub(vim.notify).was_called_with('[pi.nvim] Nothing to fork yet', vim.log.levels.ERROR)
    assert.stub(session_runtime.open).was_not_called()
  end)

  it('cycles and closes tabs', function()
    run({ 'next' })
    run({ 'prev' })
    run({ 'close' })

    assert.stub(tabs.cycle).was_called_with(1)
    assert.stub(tabs.cycle).was_called_with(-1)
    assert.stub(tabs.close_active).was_called(1)
  end)

  it('goes to a tab by number and warns on a missing one', function()
    run({ 'goto', '2' })
    assert.stub(tabs.go_to).was_called_with(2)

    tabs.go_to:revert()
    stub(tabs, 'go_to').returns(false)
    run({ 'goto', '9' })

    assert.stub(vim.notify).was_called_with('[pi.nvim] No tab 9', vim.log.levels.WARN)
  end)

  it('rejects unknown subcommands and a missing goto number', function()
    run({ 'bogus' })
    run({ 'goto' })

    assert.stub(tabs.go_to).was_not_called()
    assert.is_true(#vim.notify.calls >= 2)
  end)
end)
