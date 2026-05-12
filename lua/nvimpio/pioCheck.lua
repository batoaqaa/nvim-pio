local M = {}

-- stylua: ignore start
function M.get_bin_dir()
  -- local is_win = vim.fn.has('win32') == 1
  local bin_subfolder = OS.is_win and 'penv/Scripts' or 'penv/bin'
  local core_dir = os.getenv('PLATFORMIO_CORE_DIR')
  -- local home = (os.getenv('HOME') or os.getenv('USERPROFILE') or '')
  -- local home = vim.fn.expand("~")
  -- local home = vim.uv.os_homedir()
  if not core_dir then core_dir = vim.fs.joinpath(OS.home, '.platformio') end
  local pio_bin = vim.fs.joinpath(core_dir, bin_subfolder)
  return pio_bin
end

-- INFO: Plugin State Machine
M.state = {
  status = 'IDLE', -- IDLE, INSTALLING, READY, FAILED
  queue = {}, -- Queued callbacks waiting for installation
  isActivated = false, -- Tracks if commands/features are loaded
  isInstalled = false,
}

-- INFO: 1. Functional Check
local function is_pio_functional()
  -- 1. Quick check: Is it in the PATH?
  if vim.fn.executable('pio') == 0 then return false end

  -- 2. Deep check: Does it actually run?
  local obj = vim.system({ 'pio', '--version' }):wait()

  -- Check if the output contains the keyword "PlatformIO"
  return obj.code == 0 and obj.stdout:find('PlatformIO') ~= nil
end

--------------------------------------------------------------------------
function M.check_pio_async(callback)
  if vim.fn.executable('pio') == 0 then
    callback(false)
    return
  end

  vim.system({ 'pio', '--version' }, { text = true }, function(obj)
    -- This code runs in the background
    local is_functional = obj.code == 0 and obj.stdout:find('PlatformIO') ~= nil

    -- We use vim.schedule to ensure the callback runs on the main Neovim thread
    -- (This prevents crashes if the callback interacts with the UI)
    vim.schedule(function()
      callback(is_functional)
    end)
  end)
end
-- check_pio_async(function(functional)
--   if functional then
--     OS.notify("PlatformIO is ready!", "info")
--   else
--     OS.notify("PlatformIO check failed", "error")
--   end
-- end)

-- INFO: 2. Internal helper to notify all waiting processes
local function flush_queue(success)
  -- If successful, we are READY. If not, we mark as FAILED.
  M.state.status = success and "READY" or "FAILED"

  for _, callback in ipairs(M.state.queue) do
    if callback then callback(success) end
  end
  M.state.queue = {}
end

-- 3. The Primary Entry Point
function M.pioStatus(on_complete, is_autocmd)
  -- 1. If currently installing, just wait, just join the queue.
  if M.state.status == 'INSTALLING' then
    table.insert(M.state.queue, on_complete)
    return
  end

  -- 2. If already successful, proceed.
  if M.state.status == 'READY' or is_pio_functional() then
    M.state.status = 'READY'
    if on_complete then on_complete(true) end -- FIRE HERE
    return
  end

  -- 3. USE OF 'FAILED' STATE:
  -- If an autocmd triggered this but we previously failed, DON'T bother the user.
  -- Only proceed if the user manually ran a command (is_autocmd will be false).
  if M.state.status == "FAILED" and is_autocmd then
    if on_complete then on_complete(false) end -- FIRE HERE
    return
  end

  -- 4. Proceed with installation
  M.state.status = 'INSTALLING'
  table.insert(M.state.queue, on_complete)

  local choice = vim.fn.confirm('PlatformIO Core not found. Install now?', '&Yes\n&No', 2)
  if choice ~= 1 then
    flush_queue(false) -- FIRE HERE (via flush_queue)
    return
  end

  -- local installer_script = 'get-platformio.py'
  -- local cmd = string.format(
  --   "python -c \"import urllib.request; urllib.request.urlretrieve('https://raw.githubusercontent.com/platformio/platformio-core-installer/master/%s', '%s')\" && python %s",
  --   installer_script,
  --   installer_script,
  --   installer_script
  -- )

  -- local python = OS.is_win and 'python' or 'python3'
  -- local script = 'get-platformio.py'
  -- local script_url = 'https://raw.githubusercontent.com/platformio/platformio-core-installer/master/'
  -- local downloald_cmd = string.format(
  --                          "%s -c \"import urllib.request; urllib.request.urlretrieve('%s%s', '%s')\"",
  --                          python,
  --                          script_url,
  --                          script,
  --                          script)
  -- local install_cmd = python .. ' get-platformio.py'
  -- -- local function on_done(success)
  -- --   M.state.isInstalled = success
  -- --   flush_queue(success) -- FIRE HERE (via flush_queue)
  -- -- end
  --
  -- local pio = require('nvimpio.pio.upkeep')
  -- local cb = function(status)
  --   -- pio.handlePioInstall(status, on_done)
  --   pio.handlePioInstall(status, function(success)
  --     M.state.isInstalled = success
  --     flush_queue(success) -- FIRE HERE (via flush_queue)
  --   end)
  -- end
  --
  -- -- open toggleterm and install platformio
  -- pio.run_sequence({ cmnds = { downloald_cmd, install_cmd() }, cb = cb })

  local pioInstall = require('nvimpio.pio.ui.pioInstal').pioInstall
  pioInstall(function(success)
    M.state.isInstalled = success
    flush_queue(success) -- FIRE HERE (via flush_queue)
  end)
end

return M
