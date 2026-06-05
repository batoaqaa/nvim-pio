local M = {}

-- stylua: ignore
---Recursively merges user-defined menus onto factory default tree definitions
---@param defaults table The factory baseline menu arrays
---@param overrides table The user custom override menu arrays
---@param path string Context indicator string for verbose error outputs
---@return table merged_tree The synthesized final array layout
function M.merge_menu_tree(defaults, overrides, path)
  if type(overrides) ~= 'table' then
    return vim.deepcopy(defaults)
  end

  local res = vim.deepcopy(defaults)

  for _, u_node in ipairs(overrides) do
    if type(u_node) == 'table' then
      local matched_node = nil
      for _, existing_item in ipairs(res) do
        if existing_item.node == u_node.node then
          if u_node.node == 'item' and u_node.command == existing_item.command then
            matched_node = existing_item
            break
          elseif u_node.node == 'menu' and u_node.desc == existing_item.desc then
            matched_node = existing_item
            break
          end
        end
      end

      if matched_node then
        if u_node.shortcut then matched_node.shortcut = u_node.shortcut end
        if u_node.desc then matched_node.desc = u_node.desc end
        if u_node.command then matched_node.command = u_node.command end

        if matched_node.node == 'menu' and u_node.items then
          matched_node.items = M.merge_menu_tree(matched_node.items or {}, u_node.items, path .. '.items')
        end
      else
        local new_node = vim.deepcopy(u_node)
        new_node.node = new_node.node or 'item'

        if new_node.node == 'menu' then
          new_node.items = M.merge_menu_tree({}, u_node.items or {}, path .. '.items')
        end

        table.insert(res, new_node)
      end
    end
  end

  return res
end

---Processes the final configuration state and maps interactive menus to Which-Key
---@param config table The fully validated runtime options table
function M.buildUserMenu(config)
  if config == nil or config.menu_key == nil then
    return
  end

  local icon = { icon = '  ', color = 'orange' }
  local wk_table = { mode = { 'n', 'v' } }

  -- Recursive menu hierarchy mapping iterator traversal flattening algorithm
  local function traverseMenu(menu, wkey)
    for _, child_node in ipairs(menu or {}) do
      if child_node.node == 'menu' then
        traverseMenu(child_node.items, wkey .. child_node.shortcut)
        table.insert(wk_table, { wkey .. child_node.shortcut, group = child_node.desc, icon = icon })
      elseif child_node.node == 'item' then
        table.insert(wk_table, {
          wkey .. child_node.shortcut,
          '<cmd>' .. child_node.command .. '<CR>', -- Fixed space bug inside execution strings
          desc = child_node.desc,
          icon = icon,
        })
      end
    end
  end

  -- Safely assert Which-Key access without crashing Neovim profiles lacking it
  local ok, wk = pcall(require, 'which-key')
  if not ok then
    return
  end

  -- Base Root Trigger Menu assignment mapping
  table.insert(wk_table, { config.menu_key, group = config.menu_name, icon = icon })

  -- Run tree flattening algorithm
  traverseMenu(config.menu_bindings, config.menu_key)

  -- =========================================================================
  -- SAFE RUNTIME WRAPPER COUPLING LAYER
  -- =========================================================================
  -- 1. Introspect and back up the user's entire real configuration state dynamically
  local wk_config = require('which-key.config')
  local user_backup = vim.deepcopy(wk_config)

  -- 2. Establish a unified, safe fallback container for uninitialized spaces
  local delay_val = user_backup.delay or 0
  local icons_val = user_backup.icons or { mappings = vim.g.have_nerd_font }

  -- 3. Execute setup modifications to lock in Helix metrics across the engine layout cache
  wk.setup({
    preset = 'helix',
    delay = delay_val,
    icons = icons_val,
    sort = { 'order', 'group', 'manual', 'mod' },
  })

  -- 4. Inject your plugin array definitions securely
  wk.add(wk_table)

  -- 5. Restore the user's entire environment footprint completely unmarred in the background
  vim.schedule(function()
    -- Restore original reference properties safely
    for k, v in pairs(wk_config) do
      wk_config[k] = nil
    end
    for k, v in pairs(user_backup) do
      wk_config[k] = v
    end

    -- Force Which-Key to re-cache back onto the user's preferred native layout specification
    local r_wk = require('which-key')
    r_wk.setup({ preset = user_backup.preset or 'classic' })
  end)
  -- =========================================================================
end

return M
