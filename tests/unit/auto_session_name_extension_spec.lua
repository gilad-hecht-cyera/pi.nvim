describe('auto session name extension', function()
  it('passes its backend lifecycle tests', function()
    local output = vim.fn.system({ 'node', '--test', 'tests/auto-session-name.test.mjs' })

    assert.equal(0, vim.v.shell_error, output)
  end)
end)
