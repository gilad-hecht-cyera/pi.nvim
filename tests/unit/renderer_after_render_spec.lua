local helpers = require('tests.helpers')
local stub = require('luassert.stub')
local state = require('pi.state')
local ctx = require('pi.ui.renderer.ctx')
local Promise = require('pi.promise')
local real_render_full_session = require('pi.ui.renderer').render_full_session

describe('renderer.after_session_render', function()
  local renderer
  local get_messages
  local restore_question
  local restore_permissions

  before_each(function()
    helpers.replay_setup()
    renderer = require('pi.ui.renderer')
    renderer.render_full_session = real_render_full_session
    if not state.api_client then
      state.jobs.set_api_client({})
    end
    get_messages = stub(require('pi.session'), 'get_messages').returns(Promise.new():resolve({}))
    restore_question = stub(require('pi.ui.question_window'), 'restore_pending_question')
    restore_permissions = stub(require('pi.ui.permission_window'), 'restore_pending_permissions')
  end)

  after_each(function()
    get_messages:revert()
    restore_question:revert()
    restore_permissions:revert()
    ctx:reset()
    if state.windows then
      require('pi.ui.ui').close_windows(state.windows)
    end
  end)

  it('runs callbacks once, after the matching session renders', function()
    state.session.update_silently({ id = 'ses_hook', title = 'Hook' })
    local calls = 0
    renderer.after_session_render('ses_hook', function()
      calls = calls + 1
    end)

    renderer.render_full_session():wait(1000)
    renderer.render_full_session():wait(1000)

    assert.equal(1, calls)
  end)

  it('keeps callbacks for other sessions until they render', function()
    state.session.update_silently({ id = 'ses_one', title = 'One' })
    local called = false
    renderer.after_session_render('ses_two', function()
      called = true
    end)

    renderer.render_full_session():wait(1000)
    assert.is_false(called)

    state.session.update_silently({ id = 'ses_two', title = 'Two' })
    renderer.render_full_session():wait(1000)
    assert.is_true(called)
  end)

  it('keeps running later callbacks when one fails', function()
    state.session.update_silently({ id = 'ses_err', title = 'Err' })
    local second_ran = false
    renderer.after_session_render('ses_err', function()
      error('boom')
    end)
    renderer.after_session_render('ses_err', function()
      second_ran = true
    end)

    renderer.render_full_session():wait(1000)

    assert.is_true(second_ran)
  end)
end)
