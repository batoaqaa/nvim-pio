local function pioRepair()
  local runtime_dir = require('nvimpio').config.pio_runtime_dir

  local pioUpgrade_cmd --, pioEnv
  if OS.is_win then
    pioUpgrade_cmd = string.format('%s/pip.exe install -U platformio', runtime_dir)
    -- pioEnv = string.format('$env:PATH = "%s;" + $env:PATH', runtime_dir)
  else
    pioUpgrade_cmd = string.format('%s/pip install -U platformio', runtime_dir)
    -- pioEnv = string.format('export PATH="%s:$PATH"', runtime_dir)
  end

  -- 6. Establish downstream update pipeline connections
  -- local pio = require('nvimpio.pio.upkeep')
  local cb = function(status)
    require('nvimpio.device.parser').handlePioUpgrade(status, function(success)
      if success then
        do
        end
      end
    end)
  end
  require('nvimpio.device.parser').run_sequence({ cmnds = { pioUpgrade_cmd }, cb = cb, from = 'pioUpgrade:' })
end

return {
  pioRepair = pioRepair,
}
-- Create a user command so you can trigger it via `:InstallPIO`
-- vim.api.nvim_create_user_command("InstallPIO", install_platformio_in_venv, {})
