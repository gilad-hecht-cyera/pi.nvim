local state = require('pi.state')
local tabbar = require('pi.ui.tabbar')

local function view(id, index, title, opts)
  opts = opts or {}
  return { id = id, index = index, title = title, running = opts.running == true, active = opts.active == true }
end

local function visible_text(winbar)
  return (winbar:gsub('%%%d+@[^@]+@', ''):gsub('%%#[^#]+#', ''):gsub('%%%*', ''):gsub('%%X', ''))
end

describe('ui.tabbar', function()
  local saved_session

  before_each(function()
    saved_session = state.active_session
    state.session.update_silently(nil)
  end)

  after_each(function()
    state.session.update_silently(saved_session)
  end)

  it('renders nothing for zero or one tab', function()
    assert.is_nil(tabbar.format({}, 80))
    assert.is_nil(tabbar.format({ view(1, 1, 'Only', { active = true }) }, 80))
  end)

  it('renders numbered, clickable labels with active and inactive highlights', function()
    local winbar = tabbar.format({
      view(3, 1, 'First', { active = true }),
      view(7, 2, 'Second'),
    }, 80)

    assert.matches('%%3@v:lua%.PiTabbarClick@%%#PiTabActive# 1 First %%%*%%X', winbar)
    assert.matches('%%7@v:lua%.PiTabbarClick@%%#PiTabInactive# 2 Second %%%*%%X', winbar)
    assert.equal(' 1 First  2 Second ', visible_text(winbar))
  end)

  it('marks running tabs', function()
    local winbar = tabbar.format({ view(1, 1, 'Busy', { running = true }), view(2, 2, 'Idle', { active = true }) }, 80)

    assert.equal(' 1● Busy  2 Idle ', visible_text(winbar))
  end)

  it('uses the live active session title for the active tab', function()
    state.session.update_silently({ id = 'ses', title = 'Live title' })

    local winbar = tabbar.format({ view(1, 1, 'Stale', { active = true }), view(2, 2, 'Other') }, 80)

    assert.matches('Live title', winbar)
    assert.is_nil(winbar:find('Stale', 1, true))
  end)

  it('truncates titles to fit the available width, keeping a minimum', function()
    local long = string.rep('x', 50)
    local winbar = tabbar.format({ view(1, 1, long, { active = true }), view(2, 2, long) }, 30)

    local text = visible_text(winbar)
    assert.matches('…', text)
    assert.is_true(vim.fn.strdisplaywidth(text) <= 30)

    local narrow = visible_text(tabbar.format({ view(1, 1, long, { active = true }), view(2, 2, long) }, 4))
    assert.matches(' 1 xxxxx… ', narrow)
  end)

  it('escapes percent signs in titles', function()
    local winbar = tabbar.format({ view(1, 1, '100% done', { active = true }), view(2, 2, 'b') }, 80)

    assert.matches('100%%%% done', winbar)
  end)

  it('switches tabs from the click handler', function()
    local tabs = require('pi.services.tabs')
    local original = tabs.switch
    local switched
    tabs.switch = function(id)
      switched = id
    end

    _G.PiTabbarClick(42, 1, 'l', '    ')
    vim.wait(100, function()
      return switched ~= nil
    end)
    tabs.switch = original

    assert.equal(42, switched)
  end)
end)
