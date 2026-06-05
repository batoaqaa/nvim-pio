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

---Renders a stable, standardized menu layout using Neovim's native selection engine
---@param title string Window group heading label string
---@param items table Active node items tree configuration array
---@param parent_menu_items table|nil Falling back backtracking data array
local function show_native_picker(title, items, parent_menu_items)
  -- 1. Scan the tree layer first to compute the max description layout width
  local max_desc_len = 0
  for _, item in ipairs(items or {}) do
    local label = item.node == 'menu' and ('+' .. item.desc) or item.desc
    if #label > max_desc_len then
      max_desc_len = #label
    end
  end

  -- 2. Format choices padding descriptions left, forcing shortcuts right-aligned perfectly
  local choices = {}
  local lookup_registry = {}

  for i, item in ipairs(items or {}) do
    local label = item.node == 'menu' and ('    ' .. item.desc) or ('    ' .. item.desc)
    local hotkey_str = '[' .. item.shortcut:upper() .. ']'

    -- THE VISUAL HELIX SIGNATURE: Math-driven precise trailing space right-alignment padding
    local padding = string.rep(' ', (max_desc_len - #item.desc) + 6)
    local formatted_row = label .. padding .. hotkey_str

    table.insert(choices, formatted_row)
    lookup_registry[i] = item
  end

  -- Append structural backtracking button option if inside a sub-heading level
  if parent_menu_items then
    table.insert(choices, '    Back')
  end

  -- 3. Invoke Neovim's built-in picker loop interface window container
  vim.ui.select(choices, {
    prompt = '   ' .. title .. ' ',
  }, function(choice, index)
    if not choice then
      return
    end -- User pressed <Esc> to drop out cleanly

    -- Handle back tracking navigation choice
    if choice == '    Back' and parent_menu_items then
      show_native_picker('PlatformIO', parent_menu_items, nil)
      return
    end

    local selected_item = lookup_registry[index]
    if not selected_item then
      return
    end

    if selected_item.node == 'item' then
      -- Fire target Vim string command instantly inside core thread
      vim.cmd(selected_item.command)
    elseif selected_item.node == 'menu' then
      -- Recursively dive deeper into submenus safely
      show_native_picker(selected_item.desc, selected_item.items, items)
    end
  end)
end

---Processes configuration parameters and provisions standard which-key entries
---@param config table The fully validated configuration options table
function M.buildUserMenu(config)
  if config == nil or config.menu_key == nil then
    return
  end

  -- 1. Map your trigger shortcut straight to our clean, isolated native selection picker script
  vim.keymap.set('n', config.menu_key, function()
    -- Closes Which-Key's parent lookup window instantly right as you trigger your menu
    pcall(function()
      require('which-key.view').close()
    end)

    -- Launch the beautifully padded layout picker loop
    show_native_picker(config.menu_name, config.menu_bindings, nil)
  end, { desc = string.format('Toggle %s Action Picker', config.menu_name), silent = true })

  -- 2. Statically document the entry path inside Which-Key if it is installed
  -- This lists your menu cleanly as "\ ➜ PlatformIO" on their leader dash,
  -- but running it seamlessly drops straight out to our clean native engine selector!
  local ok, wk = pcall(require, 'which-key')
  if ok then
    wk.add({
      { config.menu_key, group = config.menu_name, icon = { icon = '  ', color = 'orange' } },
    })
  end
end

return M
