local M = {}

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

function M.validateMenu(menu)
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
        if not M.validateMenu(child_node) then
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

function M.buildUsserMenu(config)
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

function M.validate(user_config)
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
    if not M.validateMenu(user_config.menu_bindings) then
      user_config.menu_bindings = nil
    end
  end
end

return M
