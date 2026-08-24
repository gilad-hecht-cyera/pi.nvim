local M = {}

local function session_root()
  local env = vim.uv.os_getenv('PI_CODING_AGENT_SESSION_DIR')
  if env and env ~= '' then
    return vim.fs.normalize(vim.fn.expand(env))
  end
  return vim.fs.normalize(vim.fs.joinpath(vim.uv.os_homedir(), '.pi', 'agent', 'sessions'))
end

local function content_to_text(content)
  if type(content) == 'string' then
    return content
  end
  if type(content) ~= 'table' then
    return ''
  end
  local chunks = {}
  for _, item in ipairs(content) do
    if type(item) == 'string' then
      table.insert(chunks, item)
    elseif item.type == 'text' then
      table.insert(chunks, item.text or '')
    end
  end
  return table.concat(chunks, ' ')
end

local function truncate(text, max_len)
  text = (text or ''):gsub('%s+', ' '):gsub('^%s+', ''):gsub('%s+$', '')
  if text == '' then
    return nil
  end
  if #text <= max_len then
    return text
  end
  return text:sub(1, max_len - 1) .. '…'
end

local function read_session_file(path, cwd)
  local stat = vim.uv.fs_stat(path)
  if not stat or stat.type ~= 'file' then
    return nil
  end

  local header
  local first_user_text
  local last_timestamp
  local last_model
  local message_count = 0

  for line in io.lines(path) do
    local ok, entry = pcall(vim.json.decode, line)
    if ok and type(entry) == 'table' then
      if not header and entry.type == 'session' then
        header = entry
        if cwd and entry.cwd ~= cwd then
          return nil
        end
      end

      last_timestamp = entry.timestamp or last_timestamp

      if entry.type == 'model_change' and entry.provider and entry.modelId then
        last_model = entry.provider .. '/' .. entry.modelId
      elseif entry.type == 'message' and entry.message then
        message_count = message_count + 1
        if entry.message.role == 'assistant' and entry.message.provider and entry.message.model then
          last_model = entry.message.provider .. '/' .. entry.message.model
        end
        if not first_user_text and entry.message.role == 'user' then
          first_user_text = truncate(content_to_text(entry.message.content), 70)
        end
      end
    end
  end

  if not header then
    return nil
  end

  local title = first_user_text or header.name or header.id or vim.fn.fnamemodify(path, ':t:r')
  local updated = math.floor((stat.mtime and stat.mtime.sec or os.time()) * 1000)
  local created = math.floor((stat.birthtime and stat.birthtime.sec or stat.ctime and stat.ctime.sec or stat.mtime.sec) * 1000)

  return {
    id = path,
    title = title,
    description = title,
    directory = header.cwd,
    path = path,
    sessionFile = path,
    sessionID = header.id,
    messageCount = message_count,
    model = last_model,
    time = { created = created, updated = updated },
    _pi_last_timestamp = last_timestamp,
  }
end

function M.list_workspace_sessions(cwd)
  cwd = vim.fs.normalize(cwd or vim.fn.getcwd())
  local root = session_root()
  if vim.fn.isdirectory(root) == 0 then
    return {}
  end

  local sessions = {}
  local files = vim.fn.glob(vim.fs.joinpath(root, '**', '*.jsonl'), false, true)
  for _, path in ipairs(files or {}) do
    local session = read_session_file(vim.fs.normalize(path), cwd)
    if session then
      table.insert(sessions, session)
    end
  end

  table.sort(sessions, function(a, b)
    return (a.time and a.time.updated or 0) > (b.time and b.time.updated or 0)
  end)

  return sessions
end

function M.get_by_path(path)
  if not path or path == '' then
    return nil
  end
  return read_session_file(vim.fs.normalize(path), nil)
end

return M
