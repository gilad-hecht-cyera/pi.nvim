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

  it('derives context tag colours from the colour scheme', function()
    vim.api.nvim_set_hl(0, 'CursorLine', { bg = '#123456' })
    vim.api.nvim_set_hl(0, 'Comment', { fg = '#abcdef' })
    vim.cmd('highlight clear PiContextTag')
    highlight.setup()

    local hl = vim.api.nvim_get_hl(0, { name = 'PiContextTag' })
    assert.are.equal(0x123456, hl.bg)
    assert.are.equal(0xabcdef, hl.fg)
  end)

  it('follows the colour scheme again after it changes', function()
    highlight.setup()
    highlight.reapply_on_colorscheme()

    vim.cmd('highlight clear')
    vim.api.nvim_set_hl(0, 'CursorLine', { bg = '#654321' })
    vim.api.nvim_exec_autocmds('ColorScheme', {})

    assert.are.equal(0x654321, vim.api.nvim_get_hl(0, { name = 'PiContextTag' }).bg)
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
