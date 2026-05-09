local M = {}

M.config = require('nvimpio.defConfig')
local userConfig = require('nvimpio.userConfig')

-- stylua: ignore
local function get_pio_bin_dir()
  local is_win = vim.fn.has('win32') == 1
  local bin_subfolder = is_win and 'penv/Scripts' or 'penv/bin'
  local core_dir = os.getenv('PLATFORMIO_CORE_DIR')
  local home = (os.getenv('HOME') or os.getenv('USERPROFILE') or '')
  if not core_dir then core_dir = vim.fs.joinpath(home, '.platformio') end
  local pio_bin = vim.fs.joinpath(core_dir, bin_subfolder)
  return pio_bin
end

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

local state = {
  status = 'IDLE', -- IDLE, INSTALLING, READY
  queue = {}, -- Queued callbacks waiting for installation
}

-- Internal helper to notify all waiting processes
-- stylua: ignore
local function flush_queue(success)
  state.status = success and 'READY' or 'IDLE'
  for _, callback in ipairs(state.queue) do
    if callback then callback(success) end
  end
  state.queue = {}
end

-- The Floating Installer
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

  -- Set terminal options
  vim.api.nvim_set_option_value('number', true, { win = win })

  -- local cmd = 'python -c "import urllib.request; urllib.request.urlretrieve(\'https://githubusercontent.com\', \'get-platformio.py\')" && python get-platformio.py'
  local cmd =
    "python -c \"import urllib.request; urllib.request.urlretrieve('https://raw.githubusercontent.com/platformio/platformio-core-installer/master/get-platformio.py', 'get-platformio.py')\" && python get-platformio.py"
  vim.cmd.term(cmd)

  vim.api.nvim_create_autocmd('TermClose', {
    buffer = buf,
    once = true,
    callback = function()
      -- 1. Determine success status
      local success = (vim.v.event.status == 0)

      -- 2. IMMEDIATE CLEANUP
      -- Delete the script the moment the process finishes, regardless of success
      local installer_script = 'get-platformio.py'
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
        -- Refresh PATH immediately so Neovim sees the new install
        local sep = vim.fn.has('win32') == 1 and ';' or ':'
        local pio_path = vim.fn.expand('~/.platformio/penv/' .. (vim.fn.has('win32') == 1 and 'Scripts' or 'bin'))
        vim.env.PATH = pio_path .. sep .. vim.env.PATH

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
function M.pioCheck(on_complete)
  -- If an install is already in progress, just join the queue
  if state.status == 'INSTALLING' then
    table.insert(state.queue, on_complete)
    return
  end

  -- If already working, run now
  if state.status == 'READY' or is_pio_functional() then
    state.status = 'READY'
    if on_complete then
      on_complete(true)
    end
    return
  end

  -- Start new installation process
  state.status = 'INSTALLING'
  table.insert(state.queue, on_complete)

  local choice = vim.fn.confirm('PlatformIO Core not found. Install now?', '&Yes\n&No', 2)
  if choice ~= 1 then
    flush_queue(false)
    return
  end

  start_floating_installer(function(success)
    flush_queue(success)
  end)
end

-- INFO: Pioini
vim.api.nvim_create_user_command('Pioinit', function()
  M.pioCheck(function(success)
    if success then
      vim.g.platformioRootDir = vim.uv.cwd()
      vim.pio = require('nvimpio.pio.upkeep')
      vim.misc = require('nvimpio.utils.misc')
      vim.clangd = require('nvimpio.clangd.control')
      require('nvimpio.pio.ui.pioInit').pioInit()
    end
  end)
end, {
  force = true,
  desc = 'Start the PlatformIO guided setup wizard',
})

local user_config = {}
-- INFO:
--stylua: ignore
-------------------------------------------------------------------------------
function M.setup(opts)
  if opts then user_config = opts end
  userConfig.validate(user_config)
  -- M.config = vim.tbl_deep_extend('force', M.config, user_config or {})
  --
  -- menu.buildMenu(M.config)

  -- stylua: ignore
  -- stylua: ignore
  local function startPluginInternals(success)
    local sep = vim.fn.has('win32') == 1 and ';' or ':'
    if success then
      vim.g.platformioRootDir = vim.fn.getcwd()

      vim.pio = require('nvimpio.pio.upkeep')
      vim.misc = require('nvimpio.utils.misc')
      vim.clangd = require('nvimpio.clangd.control')
      if M.config.pio.auto_update_path then
        local pio_bin = get_pio_bin_dir()
        if vim.fn.isdirectory(pio_bin) == 1 then vim.env.PATH = pio_bin .. sep .. vim.env.PATH end
      end
      M.config = vim.tbl_deep_extend('force', M.config, user_config or {})
      userConfig.buildUsserMenu(M.config)
      require('nvimpio.pio.control').init(M.config.clangd)
    end
  end
  M.pioCheck(startPluginInternals)
end

return M
