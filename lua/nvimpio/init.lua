local M = {}

M.config = require('nvimpio.defConfig').defConfig

local valid_menu_keys = {
  node = true,
  desc = true,
  shortcut = true,
  items = true,
}
local valid_item_keys = {
  node = true,
  desc = true,
  shortcut = true,
  command = true,
}
local valid_keys_value = {
  node = 'string',
  desc = 'string',
  shortcut = 'string',
  command = 'string',
  items = 'table',
}

local function dumpTable(tbl)
  local result = ''
  for key, value in pairs(tbl) do
    local isValuString = type(value) == 'string' and "'" or ''
    result = result .. (string.format('%s = %s%s%s,\n', tostring(key), isValuString, tostring(value), isValuString))
  end
  return result
end

local function validateMenu(menu)
  for _, child_node in ipairs(menu) do
    if child_node.node ~= nil then
      if child_node.node == 'menu' then
        for key, value in pairs(child_node) do
          if not valid_menu_keys[key] or type(value) ~= valid_keys_value[key] then
            local error_message = string.format('Invalid PlatformIO menu key-value: %s\n%s', tostring(key), dumpTable(child_node))
            vim.api.nvim_echo({ { error_message, 'ErrorMsg' } }, true, {})
            return false
          end
        end
        if not validateMenu(child_node) then
          return false
        end
      elseif child_node.node == 'item' then
        for key, value in pairs(child_node) do
          if not valid_item_keys[key] or type(value) ~= valid_keys_value[key] then
            local error_message = string.format('Invalid PlatformIO item key-value: %s\n%s', tostring(key), dumpTable(child_node))
            vim.api.nvim_echo({ { error_message, 'ErrorMsg' } }, true, {})
            return false
          end
        end
      end
    else
      local error_message = string.format('Invalid PlatformIO menu node value: %s', dumpTable(child_node))
      vim.api.nvim_echo({ { error_message, 'ErrorMsg' } }, true, {})
      return false
    end
  end
  return true
end

function M.piomenu(config)
  local icon = { icon = '  ', color = 'orange' } -- Assign platformio orange icon
  local wk_table = { mode = { 'n', 'v' } }

  local function traverseMenu(menu, wkey)
    for _, child_node in ipairs(menu) do
      if child_node.node == 'menu' then
        traverseMenu(child_node.items, wkey .. child_node.shortcut)
        table.insert(wk_table, { wkey .. child_node.shortcut, group = child_node.desc, icon = icon })
      elseif child_node.node == 'item' then
        table.insert(wk_table, {
          wkey .. child_node.shortcut,
          '<cmd> ' .. child_node.command .. '<CR>',
          desc = child_node.desc,
          icon = icon,
        })
      end
    end
  end
  if config.menu_key == nil then
    return
  end

  local ok, wk = pcall(require, 'which-key')
  if not ok then
    vim.api.nvim_echo({ { 'which-key plugin not found!', 'ErrorMsg' } }, true, {})
    return
  end

  wk.setup({
    preset = 'helix', --'modern', --'classic'
  })
  local wkConfig = require('which-key.config')
  wkConfig.sort = { 'order', 'group', 'manual', 'mod' }

  table.insert(wk_table, { config.menu_key, group = config.menu_name, icon = icon })

  traverseMenu(config.menu_bindings, config.menu_key)

  wk.add(wk_table)
end

local function is_pio_functional()
  -- 1. Quick check: Is it in the PATH?
  if vim.fn.executable('pio') == 0 then
    return false
  end

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
local function flush_queue(success)
  state.status = success and 'READY' or 'IDLE'
  for _, callback in ipairs(state.queue) do
    if callback then
      callback(success)
    end
  end
  state.queue = {}
end

local function get_pio_bin_dir()
  local is_win = vim.fn.has('win32') == 1
  local bin_subfolder = is_win and 'penv/Scripts' or 'penv/bin'

  local core_dir = os.getenv('PLATFORMIO_CORE_DIR')
  local home = (os.getenv('HOME') or os.getenv('USERPROFILE') or '')
  if not core_dir then
    core_dir = vim.fs.joinpath(home, '.platformio')
  end
  -- Normalize the path to handle mix of '/' and '\' on Windows
  local pio_bin = vim.fs.joinpath(core_dir, bin_subfolder)
  return pio_bin
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
      local success = (vim.v.event.status == 0)
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
  -- If already working, run now
  if state.status == 'READY' or is_pio_functional() then
    state.status = 'READY'
    if on_complete then
      on_complete(true)
    end
    return
  end

  -- If an install is already in progress, just join the queue
  if state.status == 'INSTALLING' then
    table.insert(state.queue, on_complete)
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

local user_config = {}
-- INFO:
--stylua: ignore
-------------------------------------------------------------------------------
function M.setup(opts)
  if opts then
    user_config = opts
  end
  -- 1. Merge user settings with defaults
  if user_config.clangd then
    vim.validate('clangd', user_config.clangd, 'table', true)
    vim.validate('clangdsupport', user_config.clangd.support, 'boolean', true)
    vim.validate('clangdinstall', user_config.clangd.install, 'boolean', true)
  end
  vim.validate('auto_update_path', user_config.pio.auto_update_path, 'boolean', true)
  vim.validate('notify_on_missing', user_config.pio.notify_on_missing, 'boolean', true)
  vim.validate('menu_key', user_config.menu_key, 'string', true)
  vim.validate('menu_name', user_config.menu_name, 'string', true)
  vim.validate('debug', user_config.debug, 'boolean', true)
  vim.validate('menu_bindings', user_config.menu_bindings, 'table', true)

  if user_config.menu_bindings then
    -- if validation error, cancel merging menu_bindings with M.config
    if not validateMenu(user_config.menu_bindings) then
      user_config.menu_bindings = nil
    end
  end
  -- M.config = vim.tbl_deep_extend('force', M.config, user_config or {})
  --
  -- M.piomenu(M.config)

  -- Plugin State

  -- stylua: ignore
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
      M.piomenu(M.config)
      require('nvimpio.pio.control').init(M.config.clangd)
    end
  end
  M.pioCheck(startPluginInternals)
end

return M
