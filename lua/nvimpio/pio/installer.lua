local M = {}

local win_id
_G.pio_status = ''

local is_win = vim.fn.has('win32') == 1
local home = os.getenv('HOME') or os.getenv('USERPROFILE')
local pio_dir = home .. '/.platformio'
local python_dir = pio_dir .. '/python3'
local python_exe = is_win and (python_dir .. '/python.exe') or (python_dir .. '/bin/python3')

-- URLs for Portable Python (Official PIO binaries)
local python_urls = {
  win = 'https://platformio.org',
  mac = 'https://platformio.org',
}

function M.install()
  local url = is_win and python_urls.win or python_urls.mac

  local install_script_url = 'https://githubusercontent.com'

  vim.fn.mkdir(python_dir, 'p')

  -- Build the combined command
  local cmd_python = string.format('curl -f -L %s | tar -xz -C %s --strip-components=1', url, python_dir)
  local cmd_pio = string.format(
    "%s -c \"import urllib.request; urllib.request.urlretrieve('%s', 'get-platformio.py')\" && %s get-platformio.py",
    python_exe,
    install_script_url,
    python_exe
  )

  local full_command = cmd_python .. ' && ' .. cmd_pio

  -- 1. Create a split and a new buffer
  vim.cmd('split')
  local buf = vim.api.nvim_create_buf(false, true) -- No file, scratch buffer
  vim.api.nvim_set_current_buf(buf)

  -- 2. Use the modern terminal command
  -- We wrap it in the OS-specific shell
  local final_cmd = is_win and ('cmd /c ' .. full_command) or ('sh -c ' .. full_command)

  -- Launch terminal
  vim.fn.jobstart(final_cmd, {
    term = true, -- Tells jobstart to open a terminal in the current buffer
    on_exit = function(_, code)
      if code == 0 then
        print('✅ PlatformIO Installation Success!')
        if vim.fn.filereadable('get-platformio.py') == 1 then
          os.remove('get-platformio.py')
        end
      else
        print('❌ Installation failed.')
      end
    end,
  })

  -- Optional: Set buffer name and start in insert mode
  vim.api.nvim_buf_set_name(buf, 'PlatformIO Installer')
  vim.cmd('startinsert')
end








-- -- Determine paths based on OS
-- local is_win = vim.fn.has('win32') == 1
-- local home = os.getenv('HOME') or os.getenv('USERPROFILE')
-- local pio_dir = home .. '/.platformio'
-- local python_dir = pio_dir .. '/python3'
-- local python_exe = is_win and (python_dir .. '/python.exe') or (python_dir .. '/bin/python3')
-- local penv_bin = is_win and (pio_dir .. '/penv/Scripts') or (pio_dir .. '/penv/bin')
--
-- -- URLs for Portable Python (Official PIO binaries)
-- local python_urls = {
--   win = 'https://platformio.org',
--   mac = 'https://platformio.org',
-- }
--
-- function M.get_bin_dir()
--   return penv_bin
-- end
--
-- function M.install()
--   _G.pio_status = '⏳ Step 1/2: Python...'
--   vim.cmd('redrawstatus')
--
--   -- Create directory
--   vim.fn.mkdir(python_dir, 'p')
--
--   -- Step 1: Download & Extract Portable Python
--   local url = is_win and python_urls.win or python_urls.mac
--   if not url then
--     print('Portable Python not supported on this OS. Install python3-venv manually.')
--     return
--   end
--
--   -- Using tar -xz (standard on Win10+, macOS, Linux)
--   local download_cmd = string.format('curl -L %s | tar -xz -C %s --strip-components=1', url, python_dir)
--   local shell = is_win and { 'cmd', '/c' } or { 'sh', '-c' }
--
--   vim.system(shell, { args = { download_cmd } }, function(obj)
--     if obj.code ~= 0 then
--       _G.pio_status = '❌ Python Error'
--       return
--     end
--
--     -- Step 2: Download & Run PIO Installer using the new Portable Python
--     vim.schedule(function()
--       _G.pio_status = '⏳ Step 2/2: PlatformIO...'
--       vim.cmd('redrawstatus')
--
--       local install_script_url = 'https://githubusercontent.com'
--       local install_cmd = string.format(
--         "%s -c \"import urllib.request; urllib.request.urlretrieve('%s', 'get-platformio.py')\" && %s get-platformio.py",
--         python_exe,
--         install_script_url,
--         python_exe
--       )
--
--       vim.system(shell, { args = { install_cmd } }, function(obj2)
--         vim.schedule(function()
--           os.remove('get-platformio.py')
--           if obj2.code == 0 then
--             _G.pio_status = '✅ PIO Ready'
--             print('PlatformIO and Portable Python installed successfully!')
--           else
--             _G.pio_status = '❌ PIO Error'
--           end
--           vim.cmd('redrawstatus')
--         end)
--       end)
--     end)
--   end)
-- end



-- function M.install()
--   -- 1. Detect environment details
--   local is_windows = vim.fn.has('win32') == 1
--   local python = is_windows and 'python' or 'python3'
--   local shell = is_windows and { 'cmd', '/c' } or { 'sh', '-c' }
--
--   -- 2. CORRECTED URL: Added 'raw.' prefix
--   local url = 'https://raw.githubusercontent.com/platformio/platformio-core-installer/master/get-platformio.py'
--
--   -- 3. Construction of the cross-platform command string
--   -- We use double quotes for Python's internal string to ensure compatibility with Windows cmd
--   local download_py = string.format("%s -c \"import urllib.request; urllib.request.urlretrieve('%s', 'get-platformio.py')\"", python, url)
--   local install_py = python .. ' get-platformio.py'
--   local full_cmd = download_py .. ' && ' .. install_py
--
--   -- Update UI status
--   _G.pio_status = '⏳ Installing PIO...'
--   vim.cmd('redrawstatus')
--
--   local term = require('nvimpio.utils.term')
--   term.ToggleTerminal(full_cmd, 'float')
--   -- 4. Execute asynchronously
--   -- vim.system(shell, { args = { full_cmd }, text = true }, function(obj)
--   --   vim.schedule(function()
--   --     if obj.code == 0 then
--   --       _G.pio_status = '✅ PIO Ready'
--   --       -- Cleanup installer script
--   --       os.remove('get-platformio.py')
--   --       print('PlatformIO installation complete!')
--   --     else
--   --       _G.pio_status = '❌ PIO Failed'
--   --       local err_msg = obj.stderr or 'Unknown error'
--   --       print('Installation failed. Error code: ' .. obj.code)
--   --       -- Log specifically if it's a DNS/Socket error
--   --       if err_msg:find('gaierror') or err_msg:find('11001') then
--   --         print('Tip: Check your internet connection and DNS settings.')
--   --       end
--   --     end
--   --     vim.cmd('redrawstatus')
--   --   end)
--   -- end)
-- end




-- stylua: ignore
-- function M.install()
--   win_id = vim.misc.showMessage('************ PlatfromIO python env setup ************')
--   local is_windows = vim.fn.has('win32') == 1
--   local python = is_windows and 'python' or 'python3'
--   local shell = is_windows and { 'cmd', '/c' } or { 'sh', '-c' }
--
--   -- Cross-platform download/install command
--   local cmd = string.format(
--     "%s -c \"import urllib.request; urllib.request.urlretrieve('https://githubusercontent.com', 'get-platformio.py')\" && %s get-platformio.py",
--     python,
--     python
--   )
--
--   _G.pio_status = '⏳ Installing PIO...'
--   vim.cmd('redrawstatus')
--
-- local term = require('nvimpio.utils.term')
--        term.ToggleTerminal(cmd, 'float')
--   -- vim.system(shell, { args = { cmd }, text = true }, function(obj)
--   --   vim.schedule(function()
--   --     if obj.code == 0 then
--   --       _G.pio_status = '✅ PIO Ready'
--   --       os.remove('get-platformio.py')
--   --       if win_id then
--   --         vim.misc.closeMessage(win_id)
--   --       end
--   --     else
--   --       _G.pio_status = '❌ PIO Failed'
--   --       if win_id then
--   --         vim.misc.closeMessage(win_id)
--   --       end
--   --     end
--   --     vim.cmd('redrawstatus')
--   --   end)
--   -- end)
-- end

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
