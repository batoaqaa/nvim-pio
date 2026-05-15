-- stylua: ignore start
local M = { queue = {}, is_running = false, }

function M.get_bin_dir()
  local core_dir = os.getenv('PLATFORMIO_CORE_DIR') or vim.fs.joinpath(OS.home, '.platformio')
  local bin_subfolder = OS.is_win and 'penv/Scripts' or 'penv/bin'
  local pio_bin = vim.fs.joinpath(core_dir, bin_subfolder)
  return pio_bin
end

--INFO:
-- stylua: ignore start
-------------------------------------------------------------------------------
function M.removeFromPath(path_to_remove)
  local sep = OS.path_sep
  -- Split the path by the separator
  local paths = vim.split(vim.env.PATH, sep, { trimempty = true })

  -- Filter out the path we want to remove
  local new_paths = vim.tbl_filter(function(p) return p ~= path_to_remove end, paths)

  -- Rejoin and update the environment
  vim.env.PATH = table.concat(new_paths, sep)
end

function M.pioPathUpdate()
  local sep = OS.path_sep
  local binPath = M.get_bin_dir()

  -- Check if 'pio' binary is already visible to Neovim
  local has_pio = vim.fn.executable("pio") == 1

  if not has_pio then
    -- vim.env.PLATFORMIO_CORE_DIR = "/root/.platformio"
    vim.env.PATH = binPath .. sep .. vim.env.PATH
    OS.notify('PIO env: ' .. binPath .. ' added to path', 'info')
  end
end

local function finalize(success)
  M.is_running = false
  while #M.queue > 0 do
    local cb = table.remove(M.queue, 1)
    if type(cb) == 'function' then pcall(cb, success) end
  end
end

function M.pioStatus(on_complete, is_autocmd)
  -- Uses the cached, robust global check
  if OS.pioReady() then
    if type(on_complete) == 'function' then on_complete(true) end
    return
  end

  if is_autocmd then
    if type(on_complete) == 'function' then on_complete(false) end
    return
  end

  if on_complete then table.insert(M.queue, on_complete) end
  if M.is_running then return end

  M.is_running = true
  if vim.fn.confirm('PlatformIO not found. Install?', '&Yes\n&No', 1) == 1 then
    local ok, installer = pcall(require, 'nvimpio.pio.ui.pioInstall')
    if ok then
      M.pioPathUpdate()
      installer.pioInstall(finalize)
    else
      OS.notify('Installer missing', 'error')
      finalize(false)
    end
  else finalize(false) end
end

return M
