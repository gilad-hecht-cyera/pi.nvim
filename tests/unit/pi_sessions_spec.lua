local pi_sessions = require('pi.pi_sessions')

describe('pi_sessions', function()
  local original_agent_dir
  local original_session_dir
  local session_dir

  before_each(function()
    original_agent_dir = vim.env.PI_CODING_AGENT_DIR
    original_session_dir = vim.env.PI_CODING_AGENT_SESSION_DIR
    session_dir = vim.fn.tempname()
    vim.fn.mkdir(session_dir, 'p')
    vim.env.PI_CODING_AGENT_DIR = nil
    vim.env.PI_CODING_AGENT_SESSION_DIR = session_dir
  end)

  after_each(function()
    vim.env.PI_CODING_AGENT_DIR = original_agent_dir
    vim.env.PI_CODING_AGENT_SESSION_DIR = original_session_dir
    vim.fn.delete(session_dir, 'rf')
  end)

  it('uses the session directory under PI_CODING_AGENT_DIR', function()
    local agent_dir = vim.fn.tempname()
    local agent_session_dir = vim.fs.joinpath(agent_dir, 'sessions')
    vim.fn.mkdir(agent_session_dir, 'p')
    vim.env.PI_CODING_AGENT_DIR = agent_dir
    vim.env.PI_CODING_AGENT_SESSION_DIR = nil

    local path = vim.fs.joinpath(agent_session_dir, 'session.jsonl')
    vim.fn.writefile({
      vim.json.encode({
        type = 'session',
        id = 'agent-dir-session',
        cwd = vim.fn.getcwd(),
        timestamp = '2026-08-31T10:00:00Z',
      }),
    }, path)

    local sessions = pi_sessions.list_workspace_sessions(vim.fn.getcwd())

    assert.equal(1, #sessions)
    assert.equal('agent-dir-session', sessions[1].sessionID)
    vim.fn.delete(agent_dir, 'rf')
  end)

  it('prefers PI_CODING_AGENT_SESSION_DIR over PI_CODING_AGENT_DIR', function()
    local agent_dir = vim.fn.tempname()
    local agent_session_dir = vim.fs.joinpath(agent_dir, 'sessions')
    vim.fn.mkdir(agent_session_dir, 'p')
    vim.env.PI_CODING_AGENT_DIR = agent_dir

    local path = vim.fs.joinpath(agent_session_dir, 'ignored.jsonl')
    vim.fn.writefile({
      vim.json.encode({
        type = 'session',
        id = 'ignored-session',
        cwd = vim.fn.getcwd(),
        timestamp = '2026-08-31T10:00:00Z',
      }),
    }, path)

    local sessions = pi_sessions.list_workspace_sessions(vim.fn.getcwd())

    assert.equal(0, #sessions)
    vim.fn.delete(agent_dir, 'rf')
  end)

  it('prefers the latest persisted session name over the first prompt', function()
    local path = vim.fs.joinpath(session_dir, 'session.jsonl')
    local entries = {
      { type = 'session', id = 'session-id', cwd = vim.fn.getcwd(), timestamp = '2026-08-31T10:00:00Z' },
      {
        type = 'message',
        id = 'user-id',
        timestamp = '2026-08-31T10:00:01Z',
        message = { role = 'user', content = 'A long initial prompt that should not remain the title' },
      },
      {
        type = 'session_info',
        id = 'name-id',
        timestamp = '2026-08-31T10:00:02Z',
        name = 'Automatic session naming',
      },
    }
    local lines = vim.tbl_map(vim.json.encode, entries)
    vim.fn.writefile(lines, path)

    local sessions = pi_sessions.list_workspace_sessions(vim.fn.getcwd())

    assert.equal(1, #sessions)
    assert.equal('Automatic session naming', sessions[1].title)
  end)
end)
