local M = {}

M.config = {
  pio = {
    auto_update_path = true,
  },
  clangd = {
    support = false,
    install = false,
  },
  menu_key = '<leader>\\', -- replace this menu key  to your convenience
  menu_name = 'PlatformIO', -- replace this menu name to your convenience
  debug = false,

  menu_bindings = {
    { node = 'item', desc = '[I]nitiate project', shortcut = 'i', command = 'Pioinit' },
    { node = 'item', desc = '[L]ist terminals', shortcut = 'l', command = 'PioTermList' },
    { node = 'item', desc = 're[S]art clangd', shortcut = 's', command = 'Pioclangdrestart' },
    { node = 'item', desc = '[T]erminal Core CLI', shortcut = 't', command = 'Piocmdf' },
    {
      node = 'menu',
      desc = '[G]eneral',
      shortcut = 'g',
      items = {
        { node = 'item', desc = '[B]uild', shortcut = 'b', command = 'Piocmdf run' },
        { node = 'item', desc = '[C]lean', shortcut = 'c', command = 'Piocmdf run -t clean' },
        { node = 'item', desc = '[D]evice list', shortcut = 'd', command = 'Piocmdf device list' },
        { node = 'item', desc = '[F]ull clean', shortcut = 'f', command = 'Piocmdf run -t fullclean' },
        { node = 'item', desc = 'git [I]gnore', shortcut = 'i', command = 'GitIgnore' },
        { node = 'item', desc = '[M]onitor', shortcut = 'm', command = 'Piocmdh run -t monitor' },
        { node = 'item', desc = '[U]pload', shortcut = 'u', command = 'Piocmdf run -t upload' },
      },
    },
    {
      node = 'menu',
      desc = '[P]latform',
      shortcut = 'p',
      items = {
        { node = 'item', desc = '[B]uild file system', shortcut = 'b', command = 'Piocmdf run -t buildfs' },
        { node = 'item', desc = 'Program [S]ize', shortcut = 's', command = 'Piocmdf run -t size' },
        { node = 'item', desc = '[U]pload file system', shortcut = 'u', command = 'Piocmdf run -t uploadfs' },
        { node = 'item', desc = '[E]rase Flash', shortcut = 'e', command = 'Piocmdf run -t erase' },
      },
    },
    {
      node = 'menu',
      desc = '[D]ependencies',
      shortcut = 'd',
      items = {
        { node = 'item', desc = '[L]ist packages', shortcut = 'l', command = 'Piocmdf pkg list' },
        { node = 'item', desc = '[O]utdated packages', shortcut = 'o', command = 'Piocmdf pkg outdated' },
        { node = 'item', desc = '[U]pdate packages', shortcut = 'u', command = 'Piocmdf pkg update' },
      },
    },
    {
      node = 'menu',
      desc = '[A]dvanced',
      shortcut = 'a',
      items = {
        { node = 'item', desc = '[T]est', shortcut = 't', command = 'Piocmdf test' },
        { node = 'item', desc = '[C]heck', shortcut = 'c', command = 'Piocmdf check' },
        { node = 'item', desc = '[D]ebug', shortcut = 'd', command = 'Piocmdf debug' },
        { node = 'item', desc = 'Compilation Data[b]ase', shortcut = 'b', command = 'Piocmdf run -t compiledb' },
        {
          node = 'menu',
          desc = '[V]erbose',
          shortcut = 'v',
          items = {
            { node = 'item', desc = 'Verbose [B]uild', shortcut = 'b', command = 'Piocmdf run -v' },
            { node = 'item', desc = 'Verbose [U]pload', shortcut = 'u', command = 'Piocmdf run -v -t upload' },
            { node = 'item', desc = 'Verbose [T]est', shortcut = 't', command = 'Piocmdf test -v' },
            { node = 'item', desc = 'Verbose [C]heck', shortcut = 'c', command = 'Piocmdf check -v' },
            { node = 'item', desc = 'Verbose [D]ebug', shortcut = 'd', command = 'Piocmdf debug -v' },
          },
        },
      },
    },
    {
      node = 'menu',
      desc = '[R]emote',
      shortcut = 'r',
      items = {
        { node = 'item', desc = 'Remote [U]pload', shortcut = 'u', command = 'Piocmdf remote run -t upload' },
        { node = 'item', desc = 'Remote [T]est', shortcut = 't', command = 'Piocmdf remote test' },
        { node = 'item', desc = 'Remote [M]onitor', shortcut = 'm', command = 'Piocmdh remote run -t monitor' },
        { node = 'item', desc = 'Remote [D]evices', shortcut = 'd', command = 'Piocmdf remote device list' },
      },
    },
    {
      node = 'menu',
      desc = '[M]iscellaneous',
      shortcut = 'm',
      items = {
        { node = 'item', desc = '[U]pgrade PlatformIO Core', shortcut = 'u', command = 'Piocmdf upgrade' },
        { node = 'item', desc = 'PlatformIO Core [I]nstall', shortcut = 'u', command = ':PioInstall' },
      },
    },
  },
}

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

local user_config = {}
-- INFO:
---stylua: ignore
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
    if not validateMenu(user_config.menu_bindings) then
      user_config.menu_bindings = nil -- if validation error, cancel merging menu_bindings with M.config
      -- else
      --   print('good validation')
    end
  end
  M.config = vim.tbl_deep_extend('force', M.config, user_config or {})

  M.piomenu(M.config)

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


  -- stylua: ignore
  local function pioCheck(on_complete)
    if vim.fn.executable('pio') == 1 then
      if on_complete then on_complete(true) end
      vim.notify('✅ PlatformIO detected in PATH', vim.log.levels.INFO, { title = 'nvim-pio Plugin' })
      return
    end

    -- 1. If missing, ask the user
    local choice = vim.fn.confirm('PlatformIO not found. Install it now?', '&Yes\n&No', 2)
    if choice ~= 1 then
      if on_complete then on_complete(false) end
      vim.notify('Plugin load cancelled: PlatformIO Core required.', vim.log.levels.WARN)
      return
    end

    -- 2. Create the Floating Terminal
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
      title = ' PlatformIO Installer (Review Logs Before Closing) ',
      title_pos = 'center',
    })

    local cmd =
      "python -c \"import urllib.request; urllib.request.urlretrieve('https://raw.githubusercontent.com/platformio/platformio-core-installer/master/get-platformio.py', 'get-platformio.py')\" && python get-platformio.py"
    -- "python -c \"import urllib.request; urllib.request.urlretrieve('https://githubusercontent.com', 'get-platformio.py')\" && python get-platformio.py"
    vim.cmd.term(cmd)
    vim.api.nvim_create_autocmd('TermClose', {
      buffer = buf,
      once = true,
      callback = function()
        local success = (vim.v.event.status == 0)

        if success then
          -- CLOSE ONLY ON SUCCESS
          if vim.api.nvim_win_is_valid(win) then
            vim.api.nvim_win_close(win, true)
          end
          vim.notify('✅ Installation success! Loading plugin...', vim.log.levels.INFO)
        else
          -- STAY OPEN ON FAILURE
          vim.notify('🚫 Installation failed! Review the logs above, then press :q to close.', vim.log.levels.ERROR)
        end

        if on_complete then
          on_complete(success)
        end
      end,
    })
  end


  -- stylua: ignore
  -- INFO: Pioini
  vim.api.nvim_create_user_command('Pioinit', function()
    pioCheck(function(success)
      if success then
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
      if M.config.pio.auto_update_path then
        local pio_bin = get_pio_bin_dir()
        if vim.fn.isdirectory(pio_bin) == 1 then vim.env.PATH = pio_bin .. sep .. vim.env.PATH end
      end
      require('nvimpio.pio.control').init(M.config.clangd)
    end
  end
  pioCheck(startPluginInternals)
end

return M
