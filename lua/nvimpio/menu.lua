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
          '<cmd>' .. child_node.command .. '<CR>', -- Space-free command block trigger string
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

  -- 1. Register the base category title group mapping definition statically
  table.insert(wk_table, { config.menu_key, group = config.menu_name, icon = icon })

  -- 2. Fully evaluate and expand your multi-nested menu tree bindings layout
  traverseMenu(config.menu_bindings, config.menu_key)

  -- =========================================================================
  -- THE INTERCEPT STATE MECHANISM (PRODUCING 100% VISUAL HELIX CONTEXT)
  -- =========================================================================
  -- We back up the user choices and intercept right when the window opens.
  -- This forces a clean state re-render without relying on broken function callbacks.
  local user_original_preset = 'classic'

  -- Create an autocommand loop listener to detect when Which-Key hooks onto the screen window
  vim.api.nvim_create_autocmd('FileType', {
    pattern = 'which-key',
    callback = function()
      local active_state = require('which-key.state')
      -- Ensure the plugin layout applies strictly if the active menu chain path matches your root key
      if active_state.value and active_state.value.keys and active_state.value.keys:find(config.menu_key, 1, true) then
        local wk_config = require('which-key.config')
        user_original_preset = wk_config.preset or 'classic'

        -- Temporarily swap layout preferences to Helix right inside the render engine thread
        wk_config.preset = 'helix'
        pcall(function()
          require('which-key.view').update()
        end)
      end
    end,
  })

  -- Automatically restore user properties the exact millisecond the window pane closes
  vim.api.nvim_create_autocmd('BufLeave', {
    pattern = '*',
    callback = function()
      if vim.bo.filetype == 'which-key' then
        local wk_config = require('which-key.config')
        wk_config.preset = user_original_preset
      end
    end,
  })

  -- 3. Register the complete mappings table cleanly into Which-Key's registry
  wk.add(wk_table, {
    sort = { 'order', 'group', 'manual', 'mod' },
    win = {
      position = 'bottom',
      border = 'single',
      -- Center your custom orange icon symbol directly on the header layout title!
      title = '  ' .. config.menu_name .. ' ',
      title_pos = 'center',
    },
  })
  -- =========================================================================
end

return M
