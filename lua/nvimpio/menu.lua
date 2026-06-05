local M = {}

-- stylua: ignore
---Recursively merges user-defined menus onto factory default tree definitions
---@param defaults table The factory baseline menu arrays
---@param overrides table The user custom override menu arrays
---@param path string Context indicator string for verbose error outputs
---@return table merged_tree The synthesized final array layout
function M.merge_menu_tree(defaults, overrides, path)
  if type(overrides) ~= 'table' then return vim.deepcopy(defaults) end
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

---Renders a pure, native floating window modeled exactly after the Helix menu layout
local function render_helix_float(title, items, on_back)
  local display_lines = {}
  local key_mappings = {}
  local max_desc_len = 0

  -- 1. Scan the active level items to find the longest description label string width
  for _, item in ipairs(items or {}) do
    local label = item.node == 'menu' and ('+' .. item.desc) or item.desc
    if #label > max_desc_len then
      max_desc_len = #label
    end
  end

  -- 2. Build the visual text layout padding right-aligning the hotkey shortcut labels perfectly
  for _, item in ipairs(items or {}) do
    local shortcut_str = '[' .. item.shortcut .. ']'
    local label = item.node == 'menu' and ('+' .. item.desc) or item.desc

    -- THE TRUE HELIX SIGNATURE: Flush-right matching via precise trailing space math
    local padding = string.rep(' ', (max_desc_len - #label) + 6)
    table.insert(display_lines, '  ' .. label .. padding .. shortcut_str .. '  ')
    key_mappings[item.shortcut:lower()] = item
  end

  -- Append structural navigation hints if we are inside a nested submenu branch
  if on_back then
    table.insert(display_lines, string.rep('─', max_desc_len + 14))
    table.insert(display_lines, '  Back          ' .. string.rep(' ', max_desc_len - 4) .. '[<BS>] ')
  end

  -- 3. Open an unlisted, temporary scratchpad canvas buffer memory row
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, display_lines)

  local width = max_desc_len + 14
  local height = #display_lines
  local ui = vim.api.nvim_list_uis()

  -- Spawns the clean centered screen popup floating layout window
  local win = vim.api.nvim_open_win(buf, true, {
    relative = 'editor',
    width = width,
    height = height,
    col = ui and ui[1] and ((ui[1].width - width) / 2) or 15,
    row = ui and ui[1] and ((ui[1].height - height) / 2) or 10,
    style = 'minimal',
    border = 'single',
    title = '   ' .. title .. ' ',
    title_pos = 'center',
  })

  -- Apply professional Neovim float palette background highlights configurations
  vim.wo[win].winhl = 'Normal:NormalFloat,Border:FloatBorder'
  vim.bo[buf].modifiable = false

  local function close_menu()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end

  -- 4. Map navigation interception hotkeys cleanly bound strictly to this window buffer
  vim.keymap.set('n', '<Esc>', close_menu, { buffer = buf, silent = true })

  if on_back then
    vim.keymap.set('n', '<BS>', function()
      close_menu()
      on_back()
    end, { buffer = buf, silent = true })
  end

  for shortcut, item in pairs(key_mappings) do
    vim.keymap.set('n', shortcut, function()
      close_menu()
      if item.node == 'item' then
        -- Native execution trigger call
        vim.cmd(item.command)
      elseif item.node == 'menu' then
        -- Recursively open the nested branch, passing a back-closure reference
        render_helix_float(item.desc, item.items, function()
          render_helix_float(title, items, on_back)
        end)
      end
    end, { buffer = buf, silent = true })
  end
end

---Processes the final options configuration maps and initializes triggers
function M.buildUserMenu(config)
  if config == nil or config.menu_key == nil then
    return
  end

  -- =========================================================================
  -- CLEAN KEYBOARD COUPLING INTERCEPT LAYER
  -- =========================================================================
  -- 1. Create a native Neovim keymap pointing directly to our Helix engine loop
  -- This executes instantly when <leader>\ is struck, bypassing Which-Key's rendering hooks!
  vim.keymap.set('n', config.menu_key, function()
    -- Closes Which-Key's active parent lookup dashboard window buffer if it's currently open
    pcall(function()
      require('which-key.view').close()
    end)

    -- Renders your pristine, flawless native Helix panel overlay window
    render_helix_float(config.menu_name, config.menu_bindings, nil)
  end, { desc = string.format('Toggle %s Menu Window', config.menu_name), silent = true })

  -- 2. Statically register a single simple label definition inside Which-Key if it exists
  -- This guarantees your menu shows up cleanly as "\ ➜ PlatformIO" on their leader dash,
  -- but running it seamlessly drops straight out to our clean native float canvas instead!
  local ok, wk = pcall(require, 'which-key')
  if ok then
    wk.add({
      { config.menu_key, group = config.menu_name, icon = { icon = '  ', color = 'orange' } },
    })
  end
  -- =========================================================================
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
