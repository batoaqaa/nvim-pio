local M = {}

function M.merge_menu_tree(defaults, overrides, path)
  if type(overrides) ~= 'table' then
    return defaults
  end
  local res = vim.deepcopy(defaults)

  local shortcuts = {}
  for _, item in ipairs(res) do
    shortcuts[item.shortcut] = item
  end

  for _, u_node in ipairs(overrides) do
    if type(u_node) == 'table' and u_node.shortcut then
      local d_node = shortcuts[u_node.shortcut]
      if d_node then
        if u_node.desc then
          d_node.desc = u_node.desc
        end
        if u_node.command then
          d_node.command = u_node.command
        end
        if d_node.node == 'menu' and u_node.items then
          d_node.items = M.merge_menu_tree(d_node.items, u_node.items, path .. '.items')
        end
      else
        u_node.node = u_node.node or 'item'
        if u_node.node == 'menu' and u_node.items then
          u_node.items = M.merge_menu_tree({}, u_node.items, path .. '.items')
        end
        table.insert(res, u_node)
      end
    end
  end
  return res
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

return M
