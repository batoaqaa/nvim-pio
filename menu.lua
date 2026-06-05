local M = {}

-- stylua: ignore
---Recursively merges user-defined menus onto factory default tree definitions
---@param defaults table The factory baseline menu arrays
---@param overrides table The user custom override menu arrays
---@param path string Context indicator string for verbose error outputs
---@return table merged_tree The synthesized final array layout
function M.merge_menu_tree(defaults, overrides, path)
  -- 1. Fast fallback return if no valid overrides are provided
  if type(overrides) ~= 'table' then
    return vim.deepcopy(defaults)
  end

  -- 2. Create a clean deep copy of defaults so we never mutate the factory settings
  local res = vim.deepcopy(defaults)

  -- 3. Sequentially process every single node item the user passed in
  for _, u_node in ipairs(overrides) do
    if type(u_node) == 'table' then
      -- DYNAMIC LOOKUP LAYER: Identify matches by unique functional signature instead of hotkey
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
        -- SCENARIO A: The item exists in our defaults. Patch modified properties securely.
        if u_node.shortcut then matched_node.shortcut = u_node.shortcut end
        if u_node.desc then matched_node.desc = u_node.desc end
        if u_node.command then matched_node.command = u_node.command end

        -- Recursive call to process nested submenu list items safely
        if matched_node.node == 'menu' and u_node.items then
          matched_node.items = M.merge_menu_tree(matched_node.items or {}, u_node.items, path .. '.items')
        end
      else
        -- SCENARIO B: Brand new node item layout signature! Append to registry tree.
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
  local wk_table = { mode = { 'n', 'v' } }

  local function traverseMenu(menu, wkey)
    for _, child_node in ipairs(menu or {}) do
      if child_node.node == 'menu' then
        traverseMenu(child_node.items, wkey .. child_node.shortcut)
        table.insert(wk_table, { wkey .. child_node.shortcut, group = child_node.desc, icon = icon })
      elseif child_node.node == 'item' then
        table.insert(wk_table, {
          wkey .. child_node.shortcut,
          '<cmd>' .. child_node.command .. '<CR>', -- FIX: Removed the buggy space after <cmd>
          desc = child_node.desc,
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

  -- =========================================================================
  -- THE CORRECT V3 WAY: Attach the preset directly to your root menu item
  -- =========================================================================
  table.insert(wk_table, {
    config.menu_key,
    group = config.menu_name,
    icon = icon,
    preset = 'helix', -- Enforces helix visual style ONLY for this menu group tree branch!
  })

  -- Flatten the configuration array menu items definitions
  traverseMenu(config.menu_bindings, config.menu_key)

  -- Send directly to the mapping engine with isolated sorting overrides
  wk.add(wk_table, {
    sort = { 'order', 'group', 'manual', 'mod' }, -- Safely handles sorting isolated only to this block
  })
end
-- function M.buildUserMenu(config)
--   if config == nil or config.menu_key == nil then
--     return
--   end
--
--   local icon = { icon = '  ', color = 'orange' }
--   local wk_table = { mode = { 'n', 'v' } }
--
--   -- Recursive menu hierarchy mapping iterator traversal flattening algorithm
--   local function traverseMenu(menu, wkey)
--     for _, child_node in ipairs(menu or {}) do
--       if child_node.node == 'menu' then
--         traverseMenu(child_node.items, wkey .. child_node.shortcut)
--         table.insert(wk_table, { wkey .. child_node.shortcut, group = child_node.desc, icon = icon })
--       elseif child_node.node == 'item' then
--         table.insert(wk_table, {
--           wkey .. child_node.shortcut,
--           '<cmd>' .. child_node.command .. '<CR>',
--           desc = child_node.desc,
--           icon = icon,
--         })
--       end
--     end
--   end
--
--   -- Safely assert Which-Key access without crashing Neovim profiles lacking it
--   local ok, wk = pcall(require, 'which-key')
--   if not ok then
--     return
--   end
--
--   -- Initialize Which-Key layout defaults safely if it hasn't loaded yet
--   local is_whichkey_loaded = package.loaded['which-key'] ~= nil
--   if not is_whichkey_loaded then
--     wk.setup({
--       delay = 0,
--       icons = {
--         mappings = vim.g.have_nerd_font,
--         keys = vim.g.have_nerd_font and {} or {
--           Up = '<Up> ',
--           Down = '<Down> ',
--           Left = '<Left> ',
--           Right = '<Right> ',
--           C = '<C-…> ',
--           M = '<M-…> ',
--           D = '<D-…> ',
--           S = '<S-…> ',
--           CR = '<CR> ',
--           Esc = '<Esc> ',
--         },
--       },
--     })
--   end
--
--   -- =========================================================================
--   -- CRITICAL: INJECT HELIX PRESET PROPERTIES ONTO THE TOP-LEVEL GROUP BINDING
--   -- =========================================================================
--   table.insert(wk_table, {
--     config.menu_key,
--     group = config.menu_name,
--     icon = icon,
--     -- Forces Which-Key v3 engine to evaluate this specific branch using Helix's columns style
--     preset = 'helix',
--     expand = 0, -- Ensures menus do not instantly spill wide in columns layout
--   })
--
--   -- Run tree flattening algorithm
--   traverseMenu(config.menu_bindings, config.menu_key)
--
--   -- Send directly to layout engine using strict array sorting overrides
--   wk.add(wk_table, {
--     sort = { 'order', 'group', 'manual', 'mod' },
--   })
-- end

return M

-- local M = {}
--
-- -- stylua: ignore
-- function M.merge_menu_tree(defaults, overrides, path)
--   -- 1. Fast fallback return if no valid overrides are provided
--   if type(overrides) ~= 'table' then
--     return vim.deepcopy(defaults)
--   end
--
--   -- 2. Create a clean deep copy of defaults so we never mutate the factory settings
--   local res = vim.deepcopy(defaults)
--
--   -- 3. Sequentially process every single node item the user passed in
--   for _, u_node in ipairs(overrides) do
--     if type(u_node) == 'table' then
--       -- DYNAMIC LOOKUP LAYER: Identify matches by unique functional signature instead of hotkey
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
--         -- SCENARIO A: The item exists in our defaults. Patch modified properties securely.
--         if u_node.shortcut then matched_node.shortcut = u_node.shortcut end
--         if u_node.desc then matched_node.desc = u_node.desc end
--         if u_node.command then matched_node.command = u_node.command end
--
--         -- Recursive call to process nested submenu list items safely
--         if matched_node.node == 'menu' and u_node.items then
--           matched_node.items = M.merge_menu_tree(matched_node.items or {}, u_node.items, path .. '.items')
--         end
--       else
--         -- SCENARIO B: Brand new node item layout signature! Append to registry tree.
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
-- function M.buildUserMenu(config)
--   if config.menu_key == nil then
--     return
--   end
--
--   local icon = { icon = '  ', color = 'orange' }
--   local wk_table = { mode = { 'n', 'v' } }
--
--   -- Recursive menu hierarchy mapping iterator traversal
--   local function traverseMenu(menu, wkey)
--     for _, child_node in ipairs(menu) do
--       if child_node.node == 'menu' then
--         traverseMenu(child_node.items, wkey .. child_node.shortcut)
--         table.insert(wk_table, { wkey .. child_node.shortcut, group = child_node.desc, icon = icon })
--       elseif child_node.node == 'item' then
--         table.insert(wk_table, {
--           wkey .. child_node.shortcut,
--           '<cmd>' .. child_node.command .. '<CR>',
--           desc = child_node.desc,
--           icon = icon,
--         })
--       end
--     end
--   end
--
--   -- Safely assert Which-Key access without crashing Neovim profiles lacking it
--   local ok, wk = pcall(require, 'which-key')
--   if not ok then
--     return
--   end
--
--   -- Initialize Which-Key layout defaults safely if it hasn't loaded yet
--   local is_whichkey_loaded = package.loaded['which-key'] ~= nil
--   if not is_whichkey_loaded then
--     wk.setup({
--       preset = 'helix',
--       delay = 0,
--       icons = {
--         mappings = vim.g.have_nerd_font,
--         keys = vim.g.have_nerd_font and {} or {
--           Up = '<Up> ',
--           Down = '<Down> ',
--           Left = '<Left> ',
--           Right = '<Right> ',
--           C = '<C-…> ',
--           M = '<M-…> ',
--           D = '<D-…> ',
--           S = '<S-…> ',
--           CR = '<CR> ',
--           Esc = '<Esc> ',
--         },
--       },
--     })
--   end
--
--   -- Base Root Trigger Menu assignment mapping
--   table.insert(wk_table, { config.menu_key, group = config.menu_name, icon = icon })
--
--   -- Run tree flattening algorithm
--   traverseMenu(config.menu_bindings, config.menu_key)
--
--   -- Send directly to layout engine using strict array sorting overrides isolated *only* to this block
--   wk.add(wk_table, {
--     sort = { 'order', 'group', 'manual', 'mod' },
--   })
-- end
--
-- return M

-- local M = {}
--
-- -- stylua: ignore
-- function M.merge_menu_tree(defaults, overrides, path)
--   -- 1. Fast fallback return if no valid overrides are provided
--   if type(overrides) ~= 'table' then
--     return vim.deepcopy(defaults)
--   end
--
--   -- 2. Create a clean deep copy of defaults so we never mutate the factory settings
--   local res = vim.deepcopy(defaults)
--
--   -- 3. Sequentially process every single node item the user passed in
--   for _, u_node in ipairs(overrides) do
--     if type(u_node) == 'table' and u_node.shortcut then
--       -- DYNAMIC LOOKUP LAYER: Re-index shortcuts on every pass to track newly appended items!
--       local matched_node = nil
--       for _, existing_item in ipairs(res) do
--         if existing_item.shortcut == u_node.shortcut then
--           matched_node = existing_item
--           break
--         end
--       end
--
--       if matched_node then
--         -- SCENARIO A: The item exists in our defaults. Carefully patch allowed properties.
--         if u_node.node and u_node.node ~= matched_node.node then
--           error(string.format("Structure Error at %s: Cannot mutate structural node type from '%s' to '%s'", path, matched_node.node, u_node.node), 0)
--         end
--
--         if u_node.desc then matched_node.desc = u_node.desc end
--         if u_node.command then matched_node.command = u_node.command end
--
--         -- Recursive call to process nested submenu list items safely
--         if matched_node.node == 'menu' and u_node.items then
--           matched_node.items = M.merge_menu_tree(matched_node.items or {}, u_node.items, path .. '.items')
--         end
--       else
--         -- SCENARIO B: Brand new item! Deep copy it to prevent reference tracking memory leakage bugs
--         local new_node = vim.deepcopy(u_node)
--         new_node.node = new_node.node or 'item'
--
--         -- If they appended a brand new menu shell block, recursively build its internal array items
--         if new_node.node == 'menu' then
--           new_node.items = M.merge_menu_tree({}, u_node.items or {}, path .. '.items')
--         end
--
--         -- Safely append to the main list array. It will now collect EVERY appended item perfectly!
--         table.insert(res, new_node)
--       end
--     end
--   end
--
--   return res
-- end
--
-- function M.buildUserMenu(config)
--   local icon = { icon = '  ', color = 'orange' } -- Assign platformio orange icon
--   local wk_table = { mode = { 'n', 'v' } }
--
--   local function traverseMenu(menu, wkey)
--     for _, child_node in ipairs(menu) do
--       if child_node.node == 'menu' then
--         traverseMenu(child_node.items, wkey .. child_node.shortcut)
--         table.insert(wk_table, { wkey .. child_node.shortcut, group = child_node.desc, icon = icon })
--       elseif child_node.node == 'item' then
--         table.insert(wk_table, {
--           wkey .. child_node.shortcut,
--           '<cmd> ' .. child_node.command .. '<CR>',
--           desc = child_node.desc,
--           icon = icon,
--         })
--       end
--     end
--   end
--   if config.menu_key == nil then
--     return
--   end
--
--   local wk_config = { preset = 'helix' }
--   local is_whichkey_loaded = package.loaded['which-key'] ~= nil
--   local ok, wk = pcall(require, 'which-key')
--   if ok then
--     if not is_whichkey_loaded then
--       wk.setup({
--         preset = 'helix', --"classic", --"helix", --
--         delay = 0,
--         icons = {
--           -- set icon mappings to true if you have a Nerd Font
--           mappings = vim.g.have_nerd_font,
--           -- If you are using a Nerd Font: set icons.keys to an empty table which will use the
--           -- default which-key.nvim defined Nerd Font icons, otherwise define a string table
--           keys = vim.g.have_nerd_font and {} or {
--             Up = '<Up> ',
--             Down = '<Down> ',
--             Left = '<Left> ',
--             Right = '<Right> ',
--             C = '<C-…> ',
--             M = '<M-…> ',
--             D = '<D-…> ',
--             S = '<S-…> ',
--             CR = '<CR> ',
--             Esc = '<Esc> ',
--             ScrollWheelDown = '<ScrollWheelDown> ',
--             ScrollWheelUp = '<ScrollWheelUp> ',
--             NL = '<NL> ',
--             BS = '<BS> ',
--             Space = '<Space> ',
--             Tab = '<Tab> ',
--             F1 = '<F1>',
--             F2 = '<F2>',
--             F3 = '<F3>',
--             F4 = '<F4>',
--             F5 = '<F5>',
--             F6 = '<F6>',
--             F7 = '<F7>',
--             F8 = '<F8>',
--             F9 = '<F9>',
--             F10 = '<F10>',
--             F11 = '<F11>',
--             F12 = '<F12>',
--           },
--         },
--         -- sort = { "order", "group", "manual", "mod" },
--         sort = { 'local', 'order', 'group', 'alphanum', 'mod' },
--       })
--     else
--       require('which-key').setup({ preset = 'helix' })
--     end
--     -- vim.api.nvim_echo({ { 'which-key plugin not found!', 'ErrorMsg' } }, true, {})
--     -- return
--   end
--
--   local wkConfig = require('which-key.config')
--   wkConfig.sort = { 'order', 'group', 'manual', 'mod' }
--
--   table.insert(wk_table, { config.menu_key, group = config.menu_name, icon = icon })
--
--   traverseMenu(config.menu_bindings, config.menu_key)
--
--   wk.add(wk_table)
-- end
--
-- return M
