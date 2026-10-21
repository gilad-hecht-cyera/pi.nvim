local state = require('pi.state')
local store = require('pi.state.store')

describe('tab_scope', function()
  local saved

  before_each(function()
    saved = state.tab_scope.swap(nil)
  end)

  after_each(function()
    state.tab_scope.swap(saved)
  end)

  it('returns defaults that are independent copies', function()
    local a = state.tab_scope.defaults()
    local b = state.tab_scope.defaults()

    assert.same({}, a.restore_points)
    assert.equal(0, a.cost)
    assert.is_nil(a.active_session)
    assert.are_not.equal(a.restore_points, b.restore_points)
  end)

  it('swaps tab-scoped keys and returns the replaced values', function()
    state.session.set_active({ id = 'ses_a' })
    state.renderer.set_cost(1.5)
    state.ui.set_input_content({ 'draft a' })

    local tab_a = state.tab_scope.swap({ active_session = { id = 'ses_b' }, cost = 3, input_content = { 'draft b' } })

    assert.equal('ses_a', tab_a.active_session.id)
    assert.equal(1.5, tab_a.cost)
    assert.same({ 'draft a' }, tab_a.input_content)
    assert.equal('ses_b', state.active_session.id)
    assert.equal(3, state.cost)
    assert.same({ 'draft b' }, state.input_content)

    local tab_b = state.tab_scope.swap(tab_a)

    assert.equal('ses_a', state.active_session.id)
    assert.same({ 'draft a' }, state.input_content)
    assert.equal('ses_b', tab_b.active_session.id)
  end)

  it('loads defaults when swapping in nil', function()
    state.session.set_active({ id = 'ses_a' })
    state.renderer.set_cost(2)

    state.tab_scope.swap(nil)

    assert.is_nil(state.active_session)
    assert.equal(0, state.cost)
    assert.same({}, state.restore_points)
  end)

  it('leaves shared keys untouched', function()
    local windows = state.windows
    local cwd = state.current_cwd
    local mode = state.current_mode

    state.tab_scope.swap({ active_session = { id = 'ses_x' } })

    assert.equal(windows, state.windows)
    assert.equal(cwd, state.current_cwd)
    assert.equal(mode, state.current_mode)
  end)

  it('notifies subscribers of every changed key after the swap completes', function()
    state.session.set_active({ id = 'ses_a' })
    state.renderer.set_cost(1)
    local seen = {}
    local observed_cost_at_session_event
    local function on_change(key, new_val)
      seen[key] = new_val
      if key == 'active_session' then
        observed_cost_at_session_event = state.cost
      end
    end
    store.subscribe({ 'active_session', 'cost', 'tokens_count' }, on_change)

    state.tab_scope.swap({ active_session = { id = 'ses_b' }, cost = 7 })
    vim.wait(100, function()
      return seen.active_session ~= nil and seen.cost ~= nil
    end)
    store.unsubscribe('active_session', on_change)
    store.unsubscribe('cost', on_change)
    store.unsubscribe('tokens_count', on_change)

    assert.equal('ses_b', seen.active_session.id)
    assert.equal(7, seen.cost)
    assert.equal(7, observed_cost_at_session_event)
    assert.is_nil(seen.tokens_count)
  end)
end)
