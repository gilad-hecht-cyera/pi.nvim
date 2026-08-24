local store = require('pi.state.store')
local session = require('pi.state.session')
local jobs = require('pi.state.jobs')
local ui = require('pi.state.ui')
local model = require('pi.state.model')
local renderer = require('pi.state.renderer')
local context = require('pi.state.context')

---@class PiState : PiStateData
---@field store PiStateStore
---@field session PiSessionStateMutations
---@field jobs PiJobStateMutations
---@field ui PiUiStateMutations
---@field model PiModelStateMutations
---@field renderer PiRendererStateMutations
---@field context PiContextStateMutations
---@field active_session Session|nil
---@field current_model string|nil
---@field api_client PiApiClient|nil

---@type PiState
local M = {
  store = store,
  session = session,
  jobs = jobs,
  ui = ui,
  model = model,
  renderer = renderer,
  context = context,
}

return setmetatable(M, {
  __index = function(_, key)
    return store.get(key)
  end,
  __newindex = function(_, key, _value)
    error(string.format('Direct write to state key `%s` is not allowed; use a state domain setter', key), 2)
  end,
  __pairs = function()
    return pairs(store.state())
  end,
  __ipairs = function()
    return ipairs(store.state())
  end,
}) --[[@as PiState]]
