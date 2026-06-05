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
  local wk_table = {} -- Strictly hold sub-menu paths

  -- Recursive menu hierarchy mapping iterator traversal flattening algorithm
  local function traverseMenu(menu, wkey)
    for _, child_node in ipairs(menu or {}) do
      if child_node.node == 'menu' then
        traverseMenu(child_node.items, wkey .. child_node.shortcut)
        table.insert(wk_table, { wkey .. child_node.shortcut, group = child_node.desc, icon = icon })
      elseif child_node.node == 'item' then
        table.insert(wk_table, {
          wkey .. child_node.shortcut,
          '<cmd>' .. child_node.command .. '<CR>',
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

  -- Parse inner submenus under your main trigger key path
  traverseMenu(config.menu_bindings, config.menu_key)

  -- =========================================================================
  -- THE INTERCEPT FUNCTION PATTERN (CRASH-FREE & FLUID HELIX)
  -- =========================================================================

  -- 1. Register the core menu path statically so it shows up in global menus
  wk.add({
    { config.menu_key, group = config.menu_name, icon = icon },
  })

  -- 2. Inject the dynamic layout swap inside a local function mapping definition
  wk.add({
    {
      config.menu_key,
      icon = icon,
      desc = config.menu_name,
      -- Map the execution straight to an intermediate runtime state callback function
      function()
        local wk_config = require('which-key.config')

        -- Back up the user's active preset preference safely
        local original_preset = wk_config.preset or 'classic'

        -- Switch the layout engine's active preset target strictly to Helix
        wk_config.preset = 'helix'

        -- Force Which-Key to instantly re-render its open windows using Helix layout math
        wk.show({
          keys = config.menu_key,
          spec = wk_table,
        })

        -- Reset back to the user's preferred layout style cleanly in the background
        -- 50ms delay guarantees that your menu renders as Helix first before resetting
        vim.defer_fn(function()
          local restore_config = require('which-key.config')
          restore_config.preset = original_preset
        end, 50)
      end,
    },
  })
  -- =========================================================================
end

return M
