local M = {}
M.config = {
  lspClangd = {
    enabled = false,
    attach = {
      enabled = false,
      keymaps = false,
    },
  },
  menu_key = '<leader>\\', -- replace this menu key  to your convenience
  menu_name = 'PlatformIO', -- replace this menu name to your convenience
  debug = false,

  menu_bindings = {
    { node = 'item', desc = '[L]ist terminals', shortcut = 'l', command = 'PioTermList' },
    { node = 'item', desc = '[T]erminal Core CLI', shortcut = 't', command = 'Piocmdf' },
    {
      node = 'menu',
      desc = '[G]eneral',
      shortcut = 'g',
      items = {
        { node = 'item', desc = '[B]uild', shortcut = 'b', command = 'Piocmdf run' },
        { node = 'item', desc = '[U]pload', shortcut = 'u', command = 'Piocmdf run -t upload' },
        { node = 'item', desc = '[M]onitor', shortcut = 'm', command = 'Piocmdh run -t monitor' },
        { node = 'item', desc = '[C]lean', shortcut = 'c', command = 'Piocmdf run -t clean' },
        { node = 'item', desc = '[F]ull clean', shortcut = 'f', command = 'Piocmdf run -t fullclean' },
        { node = 'item', desc = '[D]evice list', shortcut = 'd', command = 'Piocmdf device list' },
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
  local Config = require('which-key.config')
  Config.sort = { 'order', 'group', 'manual', 'mod' }

  table.insert(wk_table, { config.menu_key, group = config.menu_name, icon = icon })

  traverseMenu(config.menu_bindings, config.menu_key)

  wk.add(wk_table)
end

function M.setup(user_config)
  if vim.g.platformioRootDir and (next(user_config) ~= nil) then
    if user_config.lspClangd then
      vim.validate('lspClangd', user_config.lspClangd, 'table', true)
      vim.validate('lspClangdEnabled', user_config.lspClangd.enabled, 'boolean', true)
      if user_config.lspClangd.attach then
        vim.validate('lspAttach', user_config.lspClangd.attach, 'table', true)
        vim.validate('lspAttachEnabled', user_config.lspClangd.attach.enabled, 'boolean', true)
        vim.validate('lspKeymaps', user_config.lspClangd.attach.keyMaps, 'boolean', true)
      end
    end

    vim.validate('menu_key', user_config.lspClangd_enable, 'string', true)
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
  end

  M.piomenu(M.config)

  vim.schedule(function()
    require('nvimpio.pio.watcher').init()
  end)
end

vim.notify('nvim-platformio.lua started', vim.log.levels.INFO)

return M
