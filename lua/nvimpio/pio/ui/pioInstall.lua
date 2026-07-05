_G.pio_status = ''

--INFO: Install platformio
--- stylua: ignore start
------------------------------------------------------
local function pioInstall(runtime_dir, on_done)
  -- 1. Detect environment details
  local python = OS.is_win and 'python' or 'python3'

  local script_name = 'get-platformio.py'

  -- 2. Build isolated execution file paths using your OS cache directory
  --    This prevents cluttering the user's workspace
  local script_path = vim.fs.joinpath(OS.cache_dir, script_name)

  -- 3. CORRECTED URL: Added 'raw.' prefix
  local script_url = 'https://raw.githubusercontent.com/platformio/platformio-core-installer/master/'

  -- 4. Calculate the targeting penv directory cleanly
  -- local core = require('nvimpio.core')
  local custom_penv_dir = require('nvimpio.core').clean(runtime_dir .. OS.folder_sep .. 'penv')

  -- If an old penv folder exists, wipe it completely down to the hard drive
  if type(custom_penv_dir) == 'string' and custom_penv_dir ~= '' then
    if vim.fn.isdirectory(custom_penv_dir) == 1 then
      pcall(function()
        -- vim.fs.rm requires { recursive = true } to clear multi-level folders safely
        vim.fs.rm(custom_penv_dir, { recursive = true })
      end)
    end
  end

  -- 5. Construction of the cross-platform commands string
  local download_cmd = string.format("%s -c \"import urllib.request; urllib.request.urlretrieve('%s%s', '%s')\"", python, script_url, script_name, script_path)
  local install_cmd, pioUpgrade_cmd, pipUpgrade_cmd, pioEnv, penvRestore_cmd, pioYaml_cmd
  if OS.is_win then
    install_cmd = string.format('$env:PLATFORMIO_PENV_DIR=%q; %s %s', custom_penv_dir, python, script_path)
    pipUpgrade_cmd = string.format('$env:PLATFORMIO_PENV_DIR=%q; %s/Scripts/python.exe -m pip install -U pip', custom_penv_dir, custom_penv_dir)
    pioUpgrade_cmd = string.format('$env:PLATFORMIO_PENV_DIR=%q; %s/Scripts/python.exe -m pip install -U platformio', custom_penv_dir, custom_penv_dir)
    pioYaml_cmd =
      string.format('$env:PLATFORMIO_PENV_DIR=%q; %s/Scripts/python.exe -m pip install --upgrade --force-reinstall PyYAML', custom_penv_dir, custom_penv_dir)
    penvRestore_cmd = string.format('$env:PLATFORMIO_PENV_DIR=%q; %s/Scripts/python.exe -m ensurepip --default-pip', custom_penv_dir, custom_penv_dir)
    -- pipUpgrade_cmd = string.format('%s/Scripts/python.exe -m pip install -U pip', custom_penv_dir)
    -- pioUpgrade_cmd = string.format('%s/Scripts/pip.exe install -U platformio', custom_penv_dir)
    pioEnv = string.format('$env:PATH="%s/Scripts;$env:PATH"', custom_penv_dir)
  else
    install_cmd = string.format('PLATFORMIO_PENV_DIR=%q %s %s', custom_penv_dir, python, script_path)
    pipUpgrade_cmd = string.format('PLATFORMIO_PENV_DIR=%q %s/bin/python3 -m pip install -U pip', custom_penv_dir, custom_penv_dir)
    pioUpgrade_cmd = string.format('PLATFORMIO_PENV_DIR=%q %s/bin/python3 -m pip install -U platformio', custom_penv_dir, custom_penv_dir)
    pioYaml_cmd = string.format('PLATFORMIO_PENV_DIR=%q %s/bin/python3 -m pip install --upgrade --force-reinstall PyYAML', custom_penv_dir, custom_penv_dir)
    penvRestore_cmd = string.format('PLATFORMIO_PENV_DIR=%q %s/bin/python3 -m ensurepip --default-pip', custom_penv_dir, custom_penv_dir)
    -- pipUpgrade_cmd = string.format('%s/bin/python3 -m pip install -U pip', custom_penv_dir)
    -- pioUpgrade_cmd = string.format('%s/bin/pip install -U platformio', custom_penv_dir)
    pioEnv = string.format('export PATH="%s/bin:$PATH"', custom_penv_dir)
  end

  -- 6. Establish downstream update pipeline connections
  -- local pio = require('nvimpio.pio.upkeep')
  local cb = function(status)
    -- require('nvimpio.pio.upkeep').handlePioInstall(status, on_done)
    require('nvimpio.device.parser').handlePioInstall(status, on_done)
  end

  -- 7. open toggleterm and install platformio
  -- require('nvimpio.pio.upkeep').run_sequence({ cmnds = { download_cmd, install_cmd }, cb = cb, from = 'PioInstall:' })
  require('nvimpio.device.parser').run_sequence({
    -- cmnds = { download_cmd, install_cmd, pipUpgrade_cmd, pioUpgrade_cmd, penvRestore_cmd, pioEnv },
    cmnds = { download_cmd, install_cmd, pioUpgrade_cmd, pioYaml_cmd, pipUpgrade_cmd, pioEnv .. ' ; ' .. penvRestore_cmd },
    cb = cb,
    from = 'PioInstall:',
  })
end

return {
  pioInstall = pioInstall,
}
