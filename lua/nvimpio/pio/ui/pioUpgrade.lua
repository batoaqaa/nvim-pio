local function pioUpgrade()
  local runtime_dir = require('nvimpio').config.pio_runtime_dir
  local custom_penv_dir = require('nvimpio.core').clean(runtime_dir .. OS.folder_sep .. 'penv')

  local pioUpgrade_cmd, pioEnv
  if OS.is_win then
    pioUpgrade_cmd = string.format('%s/Scripts/pip.exe install -U platformio', custom_penv_dir)
    pioEnv = string.format('$env:PATH = "%s/Scripts;" + $env:PATH', custom_penv_dir)
  else
    pioUpgrade_cmd = string.format('%s/bin/pip install -U platformio', custom_penv_dir)
    pioEnv = string.format('export PATH="%s/bin:$PATH"', custom_penv_dir)
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
  require('nvimpio.device.parser').run_sequence({ cmnds = { pioUpgrade_cmd, pioEnv }, cb = cb, from = 'pioUpgrade:' })
end

return {
  pioUpgrade = pioUpgrade,
}
-- Create a user command so you can trigger it via `:InstallPIO`
-- vim.api.nvim_create_user_command("InstallPIO", install_platformio_in_venv, {})
