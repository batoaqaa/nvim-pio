_G.pio_status = ''

-- local is_win = vim.fn.has('win32') == 1

local function get_download_command(url, target_file)
  if vim.fn.executable('curl') == 1 then
    return { 'curl', '-fsSL', '-o', target_file, url }
  elseif vim.fn.executable('wget') == 1 then
    return { 'wget', '-q', '-O', target_file, url }
  end
  return nil
end

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
  local core = require('nvimpio.core')
  local custom_penv_dir = core.clean(runtime_dir .. OS.folder_sep .. 'penv')

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
  local install_cmd
  if OS.is_win then
    install_cmd = string.format('$env:PLATFORMIO_PENV_DIR=%q; %s %s', custom_penv_dir, python, script_path)
  else
    install_cmd = string.format('PLATFORMIO_PENV_DIR=%q %s %s', custom_penv_dir, python, script_path)
  end

  -- 6. Establish downstream update pipeline connections
  local pio = require('nvimpio.pio.upkeep')
  local cb = function(status)
    pio.handlePioInstall(status, on_done)
  end

  -- 7. open toggleterm and install platformio
  pio.run_sequence({ cmnds = { download_cmd, install_cmd }, cb = cb, from = 'PioInstall:' })
end

return {
  pioInstall = pioInstall,
}
