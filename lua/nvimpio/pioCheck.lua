local M = {}

-- stylua: ignore
function M.get_bin_dir()
  local is_win = vim.fn.has('win32') == 1
  local bin_subfolder = is_win and 'penv/Scripts' or 'penv/bin'
  local core_dir = os.getenv('PLATFORMIO_CORE_DIR')
  local home = (os.getenv('HOME') or os.getenv('USERPROFILE') or '')
  if not core_dir then core_dir = vim.fs.joinpath(home, '.platformio') end
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
-- stylua: ignore
local function is_pio_functional()
  -- 1. Quick check: Is it in the PATH?
  if vim.fn.executable('pio') == 0 then return false end

  -- 2. Deep check: Does it actually run?
  -- We use 'pio --version' because it's fast and doesn't change settings.
  local output = vim.fn.system('pio --version')

  -- Check if the output contains the keyword "PlatformIO"
  -- and that the exit code (v:shell_error) was 0
  return vim.v.shell_error == 0 and output:find('PlatformIO') ~= nil
end


-- INFO: 2. Internal helper to notify all waiting processes
-- stylua: ignore
local function flush_queue(success)
  -- If successful, we are READY. If not, we mark as FAILED.
  M.state.status = success and "READY" or "FAILED"

  for _, callback in ipairs(M.state.queue) do
    if callback then callback(success) end
  end
  M.state.queue = {}
end

-- INFO: 3. The Floating Installer with Immediate Cleanup
local function start_floating_installer(on_done)
  local buf = vim.api.nvim_create_buf(false, true)
  local width = math.ceil(vim.o.columns * 0.7)
  local height = math.ceil(vim.o.lines * 0.7)

  local win = vim.api.nvim_open_win(buf, true, {
    relative = 'editor',
    width = width,
    height = height,
    row = math.ceil((vim.o.lines - height) / 2),
    col = math.ceil((vim.o.columns - width) / 2),
    border = 'rounded',
    title = { { ' PlatformIO Core Installer ', 'FloatTitle' } },
    title_pos = 'center',
  })

  -- Use a specific filename for the installer
  local installer_script = 'get-platformio.py'
  local cmd = string.format(
    "python -c \"import urllib.request; urllib.request.urlretrieve('https://raw.githubusercontent.com/platformio/platformio-core-installer/master/%s', '%s')\" && python %s",
    installer_script,
    installer_script,
    installer_script
  )
  -- local cmd = "python -c \"import urllib.request; urllib.request.urlretrieve('https://raw.githubusercontent.com/platformio/platformio-core-installer/master/get-platformio.py', 'get-platformio.py')\" && python get-platformio.py"
  vim.cmd.term(cmd)

  vim.api.nvim_create_autocmd('TermClose', {
    buffer = buf,
    once = true,
    callback = function()
      -- 1. Determine success status
      local success = (vim.v.event.status == 0)

      -- 2. IMMEDIATE CLEANUP
      -- Delete the script the moment the process finishes, regardless of success
      if vim.fn.filereadable(installer_script) == 1 then
        os.remove(installer_script)

        local temp_patterns = { '.piocore-installer-*', 'platformio-core-installer-*' }
        for _, pattern in ipairs(temp_patterns) do
          local matches = vim.fn.glob(pattern, true, true)
          for _, path in ipairs(matches) do
            if vim.fn.isdirectory(path) == 1 then
              vim.fn.delete(path, 'rf')
            end
          end
        end
      end

      -- 3. UI Handling
      if success then
        if vim.api.nvim_win_is_valid(win) then
          vim.api.nvim_win_close(win, true)
        end
        vim.notify('PlatformIO installed successfully!', vim.log.levels.INFO)
      else
        vim.notify('Installation failed! Check logs and press :q to close.', vim.log.levels.ERROR)
      end
      on_done(success)
    end,
  })
end

-- 4. The Primary Entry Point
-- stylua: ignore
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

  start_floating_installer(function(success)
    M.state.isInstalled = success
    flush_queue(success) -- FIRE HERE (via flush_queue)
  end)
end

return M
