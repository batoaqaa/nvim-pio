local M = {
  queue = {},
  is_running = false,
  isActivated = false, -- Tracks if commands/features are loaded
  isInstalled = false,
}

local function finalize(success)
  M.is_running = false
  while #M.queue > 0 do
    local cb = table.remove(M.queue, 1)
    if type(cb) == 'function' then
      pcall(cb, success)
    end
  end
end

function M.pioStatus(on_complete, is_autocmd)
  -- Uses the cached, robust global check
  if OS.pioReady() then
    if type(on_complete) == 'function' then
      on_complete(true)
    end
    return
  end

  if is_autocmd then
    if type(on_complete) == 'function' then
      on_complete(false)
    end
    return
  end

  if on_complete then
    table.insert(M.queue, on_complete)
  end
  if M.is_running then
    return
  end

  M.is_running = true
  if vim.fn.confirm('PlatformIO not found. Install?', '&Yes\n&No', 1) == 1 then
    local ok, installer = pcall(require, 'nvimpio.pio.ui.pioInstall')
    if ok then
      installer.pioInstall(finalize)
    else
      OS.notify('Installer missing', 'error')
      finalize(false)
    end
  else
    finalize(false)
  end
end

return M
