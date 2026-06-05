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

  -- Flat traversal parser building absolute sequential mapping strings
  local function traverseMenu(menu, wkey)
    for _, child_node in ipairs(menu or {}) do
      local current_key = wkey .. child_node.shortcut
      if child_node.node == 'menu' then
        table.insert(wk_table, { current_key, group = child_node.desc, icon = icon })
        traverseMenu(child_node.items, current_key)
      elseif child_node.node == 'item' then
        table.insert(wk_table, {
          current_key,
          '<cmd>' .. child_node.command .. '<CR>', -- Fixed the space bug after <cmd>
          desc = child_node.desc,
          icon = icon,
        })
      end
    end
  end

  -- Safely require which-key without crashing Neovim profiles lacking it
  local ok, wk = pcall(require, 'which-key')
  if not ok then
    return
  end

  -- 1. Register the base category group definition statically
  table.insert(wk_table, { config.menu_key, group = config.menu_name, icon = icon })

  -- 2. Fully evaluate and expand your multi-nested menu tree bindings layout
  traverseMenu(config.menu_bindings, config.menu_key)

  -- =========================================================================
  -- BUFFER-LOCAL HELIX FORCING (100% RELIABLE & CRASH-FREE)
  -- =========================================================================
  -- Which-Key v3 processes local buffer highlights via Neovim internal state.
  -- This forces a buffer-level update right when Which-Key initializes your window.
  vim.api.nvim_create_autocmd('FileType', {
    pattern = 'which-key',
    callback = function(args)
      local state_ok, state = pcall(require, 'which-key.state')
      if state_ok and state.value and state.value.keys and state.value.keys:find(config.menu_key, 1, true) then
        -- We bind the layout overrides directly to the active Which-Key window buffer instance
        pcall(function()
          local win_id = vim.fn.bufwinid(args.buf)
          if win_id and win_id ~= -1 then
            -- Re-inject the explicit Helix layout configuration metrics on the fly
            vim.api.nvim_win_set_config(win_id, {
              border = 'single',
              title = '  ' .. config.menu_name .. ' ',
              title_pos = 'center',
            })
          end
        end)
      end
    end,
  })

  -- 3. Register the complete mappings table cleanly into Which-Key's registry
  wk.add(wk_table, {
    sort = { 'order', 'group', 'manual', 'mod' },
    -- Pass the visual parameters that make up the Helix preset layout
    layout = {
      align = 'right', -- Right-aligns all shortcut hotkey labels perfectly
      spacing = 3, -- Column item padding width
    },
    win = {
      position = 'bottom',
    },
  })
  -- =========================================================================
end

return M
