local M = {}

_G.pio_status = ''

local is_win = vim.fn.has('win32') == 1
local home = os.getenv('HOME') or os.getenv('USERPROFILE')

-- 1. Check for custom environment variable first
local core_dir = os.getenv('PLATFORMIO_CORE_DIR')
-- 2. Fallback to default if not set
if not core_dir then
  core_dir = home .. '/.platformio'
end

function M.install()
  -- 1. Detect environment details
  local python = is_win and 'python' or 'python3'
  local shell = is_win and { 'cmd', '/c' } or { 'sh', '-c' }

  -- 2. CORRECTED URL: Added 'raw.' prefix
  local url = 'https://raw.githubusercontent.com/platformio/platformio-core-installer/master/get-platformio.py'

  -- 3. Construction of the cross-platform command string
  -- We use double quotes for Python's internal string to ensure compatibility with Windows cmd
  local download_py = string.format("%s -c \"import urllib.request; urllib.request.urlretrieve('%s', 'get-platformio.py')\"", python, url)
  local install_py = python .. ' get-platformio.py'
  local full_cmd = download_py .. ' && ' .. install_py

  -- Update UI status
  _G.pio_status = '⏳ Installing PIO...'
  vim.cmd('redrawstatus')

  vim.pio.run_sequence({
    cmnds = { full_cmd },
    cb = vim.pio.handlePioInstall,
  })
  -- local term = require('nvimpio.utils.term')
  -- term.ToggleTerminal(full_cmd, 'float')
  -- vim.misc.closeMessage(win_id)
  -- 4. Execute asynchronously
  -- vim.system(shell, { args = { full_cmd }, text = true }, function(obj)
  --   vim.schedule(function()
  --     if obj.code == 0 then
  --       _G.pio_status = '✅ PIO Ready'
  --       -- Cleanup installer script
  --       os.remove('get-platformio.py')
  --       print('PlatformIO installation complete!')
  --     else
  --       _G.pio_status = '❌ PIO Failed'
  --       local err_msg = obj.stderr or 'Unknown error'
  --       print('Installation failed. Error code: ' .. obj.code)
  --       -- Log specifically if it's a DNS/Socket error
  --       if err_msg:find('gaierror') or err_msg:find('11001') then
  --         print('Tip: Check your internet connection and DNS settings.')
  --       end
  --     end
  --     vim.cmd('redrawstatus')
  --   end)
  -- end)
end

function M.get_pio_bin_dir()
  -- 3. Use 'Scripts' for Windows and 'bin' for Unix-like systems
  local bin_subfolder = is_win and 'penv/Scripts' or 'penv/bin'

  -- Normalize the path to handle mix of '/' and '\' on Windows
  local full_path = vim.fs.normalize(core_dir .. '/' .. bin_subfolder)
  return full_path
end

function M.verify_version()
  vim.system({ 'pio', '--version' }, { text = true }, function(obj)
    vim.schedule(function()
      if obj.code == 0 then
        print('PlatformIO Version: ' .. vim.trim(obj.stdout))
      else
        print('❌ PlatformIO execution error: ' .. (obj.stderr or 'Unknown error'))
      end
    end)
  end)
end

return M
