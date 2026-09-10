local config = require('pi.config')
local PiProcess = require('pi.pi_process')

describe('pi_process', function()
  local original_args
  local original_executable

  before_each(function()
    original_args = config.pi_args
    original_executable = config.pi_executable
  end)

  after_each(function()
    config.pi_args = original_args
    config.pi_executable = original_executable
  end)

  it('loads the bundled session naming extension before configured arguments', function()
    config.pi_executable = 'custom-pi'
    config.pi_args = { '--no-session' }

    local args = PiProcess.build_args()

    assert.equal('custom-pi', args[1])
    assert.equal('--mode', args[2])
    assert.equal('rpc', args[3])
    assert.equal('--extension', args[4])
    assert.match('extensions/auto%-session%-name%.ts$', args[5])
    assert.equal('--no-session', args[6])
  end)
end)
