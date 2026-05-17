local M = {}

-- stylua: ignore
function M.merge_menu_tree(defaults, overrides, path)
  -- 1. Fast fallback return if no valid overrides are provided
  if type(overrides) ~= 'table' then
    return vim.deepcopy(defaults)
  end

  -- 2. Create a clean deep copy of defaults so we never mutate the factory settings
  local res = vim.deepcopy(defaults)

  -- 3. Sequentially process every single node item the user passed in
  for _, u_node in ipairs(overrides) do
    if type(u_node) == 'table' and u_node.shortcut then
      -- DYNAMIC LOOKUP LAYER: Re-index shortcuts on every pass to track newly appended items!
      local matched_node = nil
      for _, existing_item in ipairs(res) do
        if existing_item.shortcut == u_node.shortcut then
          matched_node = existing_item
          break
        end
      end

      if matched_node then
        -- SCENARIO A: The item exists in our defaults. Carefully patch allowed properties.
        if u_node.node and u_node.node ~= matched_node.node then
          error(string.format("Structure Error at %s: Cannot mutate structural node type from '%s' to '%s'", path, matched_node.node, u_node.node), 0)
        end

        if u_node.desc then matched_node.desc = u_node.desc end
        if u_node.command then matched_node.command = u_node.command end

        -- Recursive call to process nested submenu list items safely
        if matched_node.node == 'menu' and u_node.items then
          matched_node.items = M.merge_menu_tree(matched_node.items or {}, u_node.items, path .. '.items')
        end
      else
        -- SCENARIO B: Brand new item! Deep copy it to prevent reference tracking memory leakage bugs
        local new_node = vim.deepcopy(u_node)
        new_node.node = new_node.node or 'item'

        -- If they appended a brand new menu shell block, recursively build its internal array items
        if new_node.node == 'menu' then
          new_node.items = M.merge_menu_tree({}, u_node.items or {}, path .. '.items')
        end

        -- Safely append to the main list array. It will now collect EVERY appended item perfectly!
        table.insert(res, new_node)
      end
    end
  end

  return res
end

function M.buildUserMenu(config)
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

  wk.setup({ preset = 'helix' }) --'modern', --'classic'
  local wkConfig = require('which-key.config')
  wkConfig.sort = { 'order', 'group', 'manual', 'mod' }

  table.insert(wk_table, { config.menu_key, group = config.menu_name, icon = icon })

  traverseMenu(config.menu_bindings, config.menu_key)

  wk.add(wk_table)
end

return M
