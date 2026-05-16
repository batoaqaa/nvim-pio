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
  local pio = require('nvimpio.pioCheck')
  -- 1. Detect environment details
  local python = OS.is_win and 'python' or 'python3'

  local script_name = 'get-platformio.py'

  -- 2. Build isolated execution file paths using your OS cache directory
  --    This prevents cluttering the user's workspace
  local script_path = vim.fs.joinpath(OS.cache_dir, script_name)

  -- 3. CORRECTED URL: Added 'raw.' prefix
  local script_url = 'https://raw.githubusercontent.com/platformio/platformio-core-installer/master/'

  -- 4. Construction of the cross-platform commands string
  local download_cmd = string.format("%s -c \"import urllib.request; urllib.request.urlretrieve('%s%s', '%s')\"", python, script_url, script_name, script_path)
  -- Run the installer script out of the safe cache target space
  local install_cmd
  local custom_penv_dir = pio.clean(runtime_dir .. OS.folder_sep .. 'penv')
  -- if OS.is_win then
  --   install_cmd = string.format('$env:PLATFORMIO_PENV_DIR="%s"; %s %s --no-modify-path', custom_penv_dir, python, script_path)
  -- else
  install_cmd = string.format('%sPLATFORMIO_PENV_DIR="%s" %s %s --no-modify-path', OS.is_win and '$env:' or '', custom_penv_dir, python, script_path)
  -- end

  -- 5. Establish downstream update pipeline connections
  -- local pio = require('nvimpio.pio.upkeep')
  local cb = function(status)
    pio.handlePioInstall(status, on_done)
  end

  -- 6. open toggleterm and install platformio
  pio.run_sequence({ cmnds = { download_cmd, install_cmd }, cb = cb })
end

return {
  pioInstall = pioInstall,
}
