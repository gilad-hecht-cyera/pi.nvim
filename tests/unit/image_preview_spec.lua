local image_preview = require('pi.ui.image_preview')
local config = require('pi.config')
local state = require('pi.state')

describe('image_preview', function()
  local original_snacks
  local original_windows
  local original_options

  before_each(function()
    original_snacks = package.loaded.snacks
    original_windows = state.windows
    original_options = config.ui.input.image_preview
    config.ui.input.image_preview = {
      enabled = true,
      width = 20,
      height = 5,
      border = 'rounded',
    }
  end)

  after_each(function()
    image_preview.close()
    package.loaded.snacks = original_snacks
    config.ui.input.image_preview = original_options
    if original_windows then
      state.ui.set_windows(original_windows)
    else
      state.ui.clear_windows()
    end
  end)

  it('opens a bounded Snacks image preview', function()
    local input_buf = vim.api.nvim_create_buf(false, true)
    local input_win = vim.api.nvim_open_win(input_buf, true, {
      relative = 'editor',
      width = 40,
      height = 4,
      row = 8,
      col = 5,
    })
    state.ui.set_windows({ input_buf = input_buf, input_win = input_win })

    local attached
    package.loaded.snacks = {
      image = {
        buf = {
          attach = function(buf, opts)
            attached = { buf = buf, opts = opts }
            return { close = function() end }
          end,
        },
      },
    }

    assert.is_true(image_preview.show('/tmp/screenshot.png'))
    assert.equals('/tmp/screenshot.png', attached.opts.src)
    assert.equals(20, attached.opts.max_width)
    assert.equals(5, attached.opts.max_height)
    assert.is_true(vim.api.nvim_buf_is_valid(attached.buf))

    image_preview.close()
    assert.is_false(vim.api.nvim_buf_is_valid(attached.buf))
    vim.api.nvim_win_close(input_win, true)
    vim.api.nvim_buf_delete(input_buf, { force = true })
  end)

  it('does nothing when Snacks is unavailable', function()
    local input_buf = vim.api.nvim_create_buf(false, true)
    local input_win = vim.api.nvim_open_win(input_buf, true, {
      relative = 'editor',
      width = 40,
      height = 4,
      row = 8,
      col = 5,
    })
    state.ui.set_windows({ input_buf = input_buf, input_win = input_win })
    package.loaded.snacks = nil
    package.preload.snacks = function()
      error('missing')
    end

    assert.is_false(image_preview.show('/tmp/screenshot.png'))

    package.preload.snacks = nil
    vim.api.nvim_win_close(input_win, true)
    vim.api.nvim_buf_delete(input_buf, { force = true })
  end)
end)
