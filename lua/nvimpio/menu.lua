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

  local icon = { icon = '  ', color = 'orange' } -- Assign platformio orange icon

  -- Flat traversal parser building clean, relative shortcuts recursively
  local function traverseMenu(menu)
    local bindings = {}
    for _, child_node in ipairs(menu or {}) do
      if child_node.node == 'menu' then
        local submenu_node = {
          child_node.shortcut,
          group = child_node.desc,
          icon = icon,
        }
        -- Recursively unpack and append child sub-nodes into this nested menu container
        local children = traverseMenu(child_node.items)
        for _, child in ipairs(children) do
          table.insert(submenu_node, child)
        end
        table.insert(bindings, submenu_node)
      elseif child_node.node == 'item' then
        table.insert(bindings, {
          child_node.shortcut,
          '<cmd>' .. child_node.command .. '<CR>', -- Pristine, space-free command execution string
          desc = child_node.desc,
          icon = icon,
        })
      end
    end
    return bindings
  end

  -- Safely require which-key without crashing Neovim profiles lacking it
  local ok, wk = pcall(require, 'which-key')
  if not ok then
    return
  end

  -- Parse all internal bindings recursively into a nested structural layout array
  local nested_items = traverseMenu(config.menu_bindings)

  -- =========================================================================
  -- THE NATIVE V3 WAY: Structural Branching Definition
  -- =========================================================================
  -- Base configuration node for your root menu trigger path
  local root_node = {
    config.menu_key,
    group = config.menu_name,
    icon = icon,

    -- FORCES TRUE HELIX RENDERING AND PERFECT RIGHT-ALIGNMENT FOR THIS BRANCH ONLY:
    preset = 'helix',

    -- Inject window properties modifying only this specific popup panel instance
    win = {
      position = 'bottom',
      border = 'single',
      -- Injects your Nerd Font icon symbol text directly onto the window title border!
      title = '  ' .. config.menu_name .. ' ',
      title_pos = 'center',
    },
  }

  -- Inject all compiled sub-bindings cleanly inside your root node list layout
  for _, item in ipairs(nested_items) do
    table.insert(root_node, item)
  end

  -- Safely push the completed layout to Which-Key's core mapping engine
  wk.add({ root_node })
  -- =========================================================================
end

return M
