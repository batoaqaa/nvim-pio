local M = {}

local win_id
_G.pio_status = ''

-- stylua: ignore
function M.install()
  win_id = vim.misc.showMessage('************ PlatfromIO python env setup ************')
  local is_windows = vim.fn.has('win32') == 1
  local python = is_windows and 'python' or 'python3'
  local shell = is_windows and { 'cmd', '/c' } or { 'sh', '-c' }

  -- Cross-platform download/install command
  local cmd = string.format(
    "%s -c \"import urllib.request; urllib.request.urlretrieve('https://githubusercontent.com', 'get-platformio.py')\" && %s get-platformio.py",
    python,
    python
  )

  _G.pio_status = '⏳ Installing PIO...'
  vim.cmd('redrawstatus')

  vim.system(shell, { args = { cmd }, text = true }, function(obj)
    vim.schedule(function()
      if obj.code == 0 then
        _G.pio_status = '✅ PIO Ready'
        os.remove('get-platformio.py')
        if win_id then
          vim.misc.closeMessage(win_id)
        end
      else
        _G.pio_status = '❌ PIO Failed'
        if win_id then
          vim.misc.closeMessage(win_id)
        end
      end
      vim.cmd('redrawstatus')
    end)
  end)
end

function M.get_pio_bin_dir()
  -- 1. Check for custom environment variable first
  local pio_core = os.getenv('PLATFORMIO_CORE_DIR')

  -- 2. Fallback to default if not set
  if not pio_core then
    local home = os.getenv('HOME') or os.getenv('USERPROFILE')
    pio_core = home .. '/.platformio'
  end

  local is_windows = vim.fn.has('win32') == 1
  -- 3. Use 'Scripts' for Windows and 'bin' for Unix-like systems
  local bin_subfolder = is_windows and 'penv/Scripts' or 'penv/bin'

  -- Normalize the path to handle mix of '/' and '\' on Windows
  local full_path = vim.fs.normalize(pio_core .. '/' .. bin_subfolder)
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
