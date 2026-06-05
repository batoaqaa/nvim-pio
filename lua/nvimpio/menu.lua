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
  local wk_table = {}

  -- =========================================================================
  -- LEADER EXPANSION LAYER: Resolves string compilation conflicts
  -- =========================================================================
  local base_key = config.menu_key
  if base_key:sub(1, 8):lower() == '<leader>' then
    local map_leader = vim.g.mapleader or ' '
    base_key = map_leader .. base_key:sub(9)
  end

  -- 1. Scan the tree first to compute the max description layout width
  local max_desc_len = 0
  local function calculateWidth(menu)
    for _, child in ipairs(menu or {}) do
      local label = child.node == 'menu' and ('+' .. child.desc) or child.desc
      if #label > max_desc_len then
        max_desc_len = #label
      end
      if child.node == 'menu' then
        calculateWidth(child.items)
      end
    end
  end
  calculateWidth(config.menu_bindings)

  -- 2. Build explicit mappings padding descriptions to replicate the Helix preset layout
  local function traverseMenu(menu, wkey)
    for _, child_node in ipairs(menu or {}) do
      local current_key = wkey .. child_node.shortcut
      local clean_label = child_node.node == 'menu' and ('+' .. child_node.desc) or child_node.desc

      -- Calculate structural trailing spaces to right-align the hotkey markers manually
      local pad_count = (max_desc_len - #clean_label) + 6
      local padding_str = string.rep(' ', pad_count)
      local simulated_helix_desc = clean_label .. padding_str .. '[' .. child_node.shortcut .. ']'

      if child_node.node == 'menu' then
        table.insert(wk_table, { current_key, group = simulated_helix_desc, icon = icon })
        traverseMenu(child_node.items, current_key)
      elseif child_node.node == 'item' then
        table.insert(wk_table, {
          current_key,
          '<cmd>' .. child_node.command .. '<CR>', -- Fixed the space bug after <cmd>
          desc = simulated_helix_desc,
          icon = icon,
        })
      end
    end
  end

  -- Safely require which-key without crashing if the user doesn't have it installed
  local ok, wk = pcall(require, 'which-key')
  if not ok then
    return
  end

  -- 3. Statically register the root category title mapping with your title icon text appended
  table.insert(wk_table, { base_key, group = config.menu_name, icon = icon })

  -- 4. Expand your menu tree selections using the cleaned base key paths
  traverseMenu(config.menu_bindings, base_key)

  -- 5. Send everything directly to the Which-Key mapping registry
  wk.add(wk_table, {
    sort = { 'order', 'group', 'manual', 'mod' },
    win = {
      position = 'bottom',
      border = 'single',
      -- Injects your Nerd Font icon symbol text straight onto the window title border!
      title = '  ' .. config.menu_name .. ' ',
      title_pos = 'center',
    },
  })
end

return M
-- local M = {}
--
-- -- stylua: ignore
-- ---Recursively merges user-defined menus onto factory default tree definitions
-- ---@param defaults table The factory baseline menu arrays
-- ---@param overrides table The user custom override menu arrays
-- ---@param path string Context indicator string for verbose error outputs
-- ---@return table merged_tree The synthesized final array layout
-- function M.merge_menu_tree(defaults, overrides, path)
--   if type(overrides) ~= 'table' then
--     return vim.deepcopy(defaults)
--   end
--
--   local res = vim.deepcopy(defaults)
--
--   for _, u_node in ipairs(overrides) do
--     if type(u_node) == 'table' then
--       local matched_node = nil
--       for _, existing_item in ipairs(res) do
--         if existing_item.node == u_node.node then
--           if u_node.node == 'item' and u_node.command == existing_item.command then
--             matched_node = existing_item
--             break
--           elseif u_node.node == 'menu' and u_node.desc == existing_item.desc then
--             matched_node = existing_item
--             break
--           end
--         end
--       end
--
--       if matched_node then
--         if u_node.shortcut then matched_node.shortcut = u_node.shortcut end
--         if u_node.desc then matched_node.desc = u_node.desc end
--         if u_node.command then matched_node.command = u_node.command end
--
--         if matched_node.node == 'menu' and u_node.items then
--           matched_node.items = M.merge_menu_tree(matched_node.items or {}, u_node.items, path .. '.items')
--         end
--       else
--         local new_node = vim.deepcopy(u_node)
--         new_node.node = new_node.node or 'item'
--
--         if new_node.node == 'menu' then
--           new_node.items = M.merge_menu_tree({}, u_node.items or {}, path .. '.items')
--         end
--
--         table.insert(res, new_node)
--       end
--     end
--   end
--
--   return res
-- end
--
-- ---Processes the final configuration state and maps interactive menus to Which-Key
-- ---@param config table The fully validated runtime options table
-- function M.buildUserMenu(config)
--   if config == nil or config.menu_key == nil then
--     return
--   end
--
--   local icon = { icon = '  ', color = 'orange' } -- Assign platformio orange icon
--   local wk_table = {} -- Clean list collection layout container
--
--   -- Clear flat traversal matching function path
--   local function traverseMenu(menu, wkey)
--     for _, child_node in ipairs(menu or {}) do
--       if child_node.node == 'menu' then
--         traverseMenu(child_node.items, wkey .. child_node.shortcut)
--         table.insert(wk_table, { wkey .. child_node.shortcut, group = child_node.desc, icon = icon })
--       elseif child_node.node == 'item' then
--         table.insert(wk_table, {
--           wkey .. child_node.shortcut,
--           '<cmd>' .. child_node.command .. '<CR>', -- Pristine, space-free command trigger
--           desc = child_node.desc,
--           icon = icon,
--         })
--       end
--     end
--   end
--
--   -- Safely wrap require in a pcall to protect users who don't install which-key
--   local ok, wk = pcall(require, 'which-key')
--   if not ok then
--     return
--   end
--
--   -- 1. Statically bind the root menu key indicator title mapping
--   table.insert(wk_table, { config.menu_key, group = config.menu_name, icon = icon })
--
--   -- 2. Traverse your configuration list tree items natively
--   traverseMenu(config.menu_bindings, config.menu_key)
--
--   -- =========================================================================
--   -- THE NATIVE GITHUB-SAFE OVERRIDE METRICS (EXACT HELIX LAYOUT)
--   -- =========================================================================
--   -- Passing properties directly inside the second argument options dictionary
--   -- applies these styles ONLY to this menu profile path branch registry.
--   wk.add(wk_table, {
--     sort = { 'order', 'group', 'manual', 'mod' }, -- Enforce neat manual sorting layout
--     expand = 0, -- Prevents messy column layout splitting
--
--     -- Explicitly replicate the look and feel metrics of the Helix preset layout
--     layout = {
--       align = 'right', -- THE HELIX VISUAL SIGNATURE: Right-aligns key labels next to text
--       spacing = 3, -- Column item padding width
--     },
--     win = {
--       position = 'bottom', -- Locks appearance position at the bottom of the screen
--       border = 'single', -- Emulates Helix's clean sharp borders look
--     },
--   })
--   -- =========================================================================
-- end
--
-- return M
