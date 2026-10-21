local tab_persistence = require('pi.tab_persistence')

describe('tab_persistence', function()
  local original_stdpath
  local data_dir

  before_each(function()
    data_dir = vim.fn.tempname()
    original_stdpath = vim.fn.stdpath
    vim.fn.stdpath = function(what)
      if what == 'data' then
        return data_dir
      end
      return original_stdpath(what)
    end
  end)

  after_each(function()
    vim.fn.stdpath = original_stdpath
    vim.fn.delete(data_dir, 'rf')
  end)

  it('returns nil when nothing was saved', function()
    assert.is_nil(tab_persistence.read('/work/a'))
  end)

  it('round-trips tabs per working directory', function()
    tab_persistence.write('/work/a', { sessions = { '/s/1.jsonl', '/s/2.jsonl' }, active = 2 })
    tab_persistence.write('/work/b', { sessions = { '/s/3.jsonl' }, active = 1 })

    assert.same({ sessions = { '/s/1.jsonl', '/s/2.jsonl' }, active = 2 }, tab_persistence.read('/work/a'))
    assert.same({ sessions = { '/s/3.jsonl' }, active = 1 }, tab_persistence.read('/work/b'))
  end)

  it('normalizes the working directory key', function()
    tab_persistence.write('/work/a/', { sessions = { '/s/1.jsonl' }, active = 1 })

    assert.same({ sessions = { '/s/1.jsonl' }, active = 1 }, tab_persistence.read('/work/a'))
  end)

  it('removes an entry when writing nil', function()
    tab_persistence.write('/work/a', { sessions = { '/s/1.jsonl' }, active = 1 })
    tab_persistence.write('/work/b', { sessions = { '/s/3.jsonl' }, active = 1 })

    tab_persistence.write('/work/a', nil)

    assert.is_nil(tab_persistence.read('/work/a'))
    assert.is_not_nil(tab_persistence.read('/work/b'))
  end)

  it('ignores a corrupt file', function()
    vim.fn.mkdir(data_dir .. '/pi', 'p')
    vim.fn.writefile({ '{not json' }, data_dir .. '/pi/tabs.json')

    assert.is_nil(tab_persistence.read('/work/a'))

    tab_persistence.write('/work/a', { sessions = { '/s/1.jsonl' }, active = 1 })
    assert.is_not_nil(tab_persistence.read('/work/a'))
  end)

  it('defaults a missing active index to the first tab', function()
    vim.fn.mkdir(data_dir .. '/pi', 'p')
    vim.fn.writefile({ vim.json.encode({ ['/work/a'] = { sessions = { '/s/1.jsonl' } } }) }, data_dir .. '/pi/tabs.json')

    assert.same({ sessions = { '/s/1.jsonl' }, active = 1 }, tab_persistence.read('/work/a'))
  end)
end)
