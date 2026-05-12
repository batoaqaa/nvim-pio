_G.pio_status = ''

-- local is_win = vim.fn.has('win32') == 1

--INFO: Install platformio
-- stylua: ignore start
------------------------------------------------------
local function pioInstall(on_done)
  -- 1. Detect environment details
  -- local python = OS.is_win and 'python' or 'python3'
  --
  -- -- 2. CORRECTED URL: Added 'raw.' prefix
  -- local url = 'https://raw.githubusercontent.com/platformio/platformio-core-installer/master/get-platformio.py'
  --
  -- -- 3. Construction of the cross-platform command string
  -- -- We use double quotes for Python's internal string to ensure compatibility with Windows cmd
  -- local download_py = string.format("%s -c \"import urllib.request; urllib.request.urlretrieve('%s', 'get-platformio.py')\"", python, url)
  -- local install_py = python .. ' get-platformio.py'
  -- local full_cmd = download_py .. ' && ' .. install_py
  --
  -- -- Update UI status
  -- _G.pio_status = '⏳ Installing PIO...'
  -- vim.cmd('redrawstatus')
  --
  -- local pio = require('nvimpio.pio.upkeep')
  -- pio.run_sequence({ cmnds = { full_cmd }, cb = vim.pio.handlePioInstall })
  local python = OS.is_win and 'python' or 'python3'
  local script = 'get-platformio.py'
  local script_url = 'https://raw.githubusercontent.com/platformio/platformio-core-installer/master/'
  local downloald_cmd = string.format(
                           "%s -c \"import urllib.request; urllib.request.urlretrieve('%s%s', '%s')\"",
                           python, script_url, script, script)
  local install_cmd = python .. ' get-platformio.py'

  local pio = require('nvimpio.pio.upkeep')
  local cb = function(status) pio.handlePioInstall(status, on_done) end

  -- open toggleterm and install platformio
  pio.run_sequence({ cmnds = { downloald_cmd, install_cmd }, cb = cb })
end

return {
  pioInstall = pioInstall,
}
