local M = {}

---@class PiSavedTabs
---@field sessions string[] Session file paths in tab order
---@field active integer 1-based index of the active tab

local function store_path()
  local data_dir = vim.fn.stdpath('data') .. '/pi'
  if vim.fn.isdirectory(data_dir) ~= 1 then
    vim.fn.mkdir(data_dir, 'p')
  end
  return data_dir .. '/tabs.json'
end

local function read_all()
  local file = io.open(store_path(), 'r')
  if not file then
    return {}
  end
  local content = file:read('*a')
  file:close()
  local ok, decoded = pcall(vim.json.decode, content)
  if not ok or type(decoded) ~= 'table' then
    return {}
  end
  return decoded
end

---@param cwd string
---@return PiSavedTabs|nil
function M.read(cwd)
  local entry = read_all()[vim.fs.normalize(cwd)]
  if type(entry) ~= 'table' or type(entry.sessions) ~= 'table' then
    return nil
  end
  return { sessions = entry.sessions, active = tonumber(entry.active) or 1 }
end

---@param cwd string
---@param saved PiSavedTabs|nil nil removes the entry
function M.write(cwd, saved)
  local all = read_all()
  all[vim.fs.normalize(cwd)] = saved
  local path = store_path()
  local tmp = path .. '.tmp'
  local file = io.open(tmp, 'w')
  if not file then
    return
  end
  file:write(vim.json.encode(all))
  file:close()
  os.rename(tmp, path)
end

return M
