local highlight = require('pi.ui.highlight')

describe('pi.ui.highlight', function()
  after_each(function()
    pcall(vim.api.nvim_del_augroup_by_name, 'PiHighlights')
    highlight.setup()
  end)

  it('styles reasoning text as italic', function()
    vim.cmd('highlight clear PiReasoningText')
    highlight.setup()

    local hl = vim.api.nvim_get_hl(0, { name = 'PiReasoningText' })
    assert.is_true(hl.italic)
    assert.is_nil(hl.link)
  end)

  it('restores attribute-only groups after a colorscheme clears highlights', function()
    highlight.setup()
    highlight.reapply_on_colorscheme()

    vim.cmd('highlight clear')
    assert.is_nil(vim.api.nvim_get_hl(0, { name = 'PiReasoningText' }).italic)

    vim.api.nvim_exec_autocmds('ColorScheme', {})

    assert.is_true(vim.api.nvim_get_hl(0, { name = 'PiReasoningText' }).italic)
    assert.is_not_nil(vim.api.nvim_get_hl(0, { name = 'PiToolBorder' }).fg)
  end)

  it('does not reapply highlights on colorscheme without the autocmd', function()
    highlight.setup()

    vim.cmd('highlight clear')
    vim.api.nvim_exec_autocmds('ColorScheme', {})

    assert.is_nil(vim.api.nvim_get_hl(0, { name = 'PiReasoningText' }).italic)
  end)
end)
