local function pioRepair()
  local ok_main, main = pcall(require, 'nvimpio')
  if not ok_main then
    return
  end

  local current_pio_opts = (main.options and main.options.pio) or (main.defaults and main.defaults.pio) or {}
  local raw_runtime_dir = require('nvimpio.core').resolve_user_path(current_pio_opts.pio_runtime_dir)

  if not raw_runtime_dir or raw_runtime_dir == '' then
    raw_runtime_dir = OS.is_win and vim.fs.joinpath(vim.env.USERPROFILE, '.platformio') or vim.fs.joinpath(OS.home, '.platformio')
  end

  local base_runtime = raw_runtime_dir
  local bin_subfolder = OS.is_win and 'Scripts' or 'bin'
  local target_bin = vim.fs.joinpath(base_runtime, 'penv', bin_subfolder)
  -- local runtime_dir = require('nvimpio').config.pio_runtime_dir

  local pioRepair_cmd, penvRestore_cmd --, pioEnv
  if OS.is_win then
    pioRepair_cmd = string.format('%s/python.exe -m pip install -U platformio', target_bin)
    penvRestore_cmd = string.format('%s/python.exe -m ensurepip --default-pip', target_bin)
    -- pioEnv = string.format('$env:PATH = "%s;" + $env:PATH', runtime_dir)
  else
    pioRepair_cmd = string.format('%s/python3 -m pip install -U platformio', target_bin)
    penvRestore_cmd = string.format('%s/python3 -m ensurepip --default-pip', target_bin)
    -- pioEnv = string.format('export PATH="%s:$PATH"', runtime_dir)
  end

  -- 6. Establish downstream update pipeline connections
  -- local pio = require('nvimpio.pio.upkeep')
  local cb = function(status)
    require('nvimpio.device.parser').handlePioRepair(status, function(success)
      if success then
        do
        end
      end
    end)
  end
  require('nvimpio.device.parser').run_sequence({ cmnds = { pioRepair_cmd, penvRestore_cmd }, cb = cb, from = 'pioRepair:' })
end

return {
  pioRepair = pioRepair,
}
-- Create a user command so you can trigger it via `:InstallPIO`
-- vim.api.nvim_create_user_command("InstallPIO", install_platformio_in_venv, {})
