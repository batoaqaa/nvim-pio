_G.pio_status = ''

-- local is_win = vim.fn.has('win32') == 1

--INFO: Install platformio
-- stylua: ignore start
------------------------------------------------------
local function pioInstall(on_done)
  -- 1. Detect environment details
  local python = OS.is_win and 'python' or 'python3'

  local script = 'get-platformio.py'

  -- 2. CORRECTED URL: Added 'raw.' prefix
  local script_url = 'https://raw.githubusercontent.com/platformio/platformio-core-installer/master/'

  -- 3. Construction of the cross-platform commands string
  local downloald_cmd = string.format(
                           "%s -c \"import urllib.request; urllib.request.urlretrieve('%s%s', '%s')\"",
                           python, script_url, script, script)
  local install_cmd = python .. ' ' .. script

  local pio = require('nvimpio.pio.upkeep')
  local cb = function(status) pio.handlePioInstall(status, on_done) end

  -- 4. open toggleterm and install platformio
  pio.run_sequence({ cmnds = { downloald_cmd, install_cmd }, cb = cb })
end

return {
  pioInstall = pioInstall,
}
