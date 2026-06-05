local M = {}

-- stylua: ignore
---Recursively merges user-defined menus onto factory default tree definitions
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
local function show_native_picker(title, items, parent_menu_items)
  -- 1. Format choices for display
  local choices = {}
  for _, item in ipairs(items or {}) do
    local label = item.node == 'menu' and ('    ' .. item.desc) or ('    ' .. item.desc)
    table.insert(choices, label)
  end

  if parent_menu_items then
    table.insert(choices, '    Back')
  end

  -- 2. Open standard native selection window loop interface
  vim.ui.select(choices, {
    prompt = ' ' .. title .. ' ',
  }, function(choice, index)
    if not choice then
      return
    end -- User hit Esc to close cleanly

    -- Handle Back tracking navigation choice
    if choice == '    Back' and parent_menu_items then
      show_native_picker('PlatformIO', parent_menu_items, nil)
      return
    end

    local selected_item = items[index]
    if not selected_item then
      return
    end

    if selected_item.node == 'item' then
      -- Execute target command string safely inside standard thread
      vim.cmd(selected_item.command)
    elseif selected_item.node == 'menu' then
      -- Recursively dive deeper into submenus safely
      show_native_picker(selected_item.desc, selected_item.items, items)
    end
  end)
end

---Processes configuration parameters and provisions standard which-key entries
function M.buildUserMenu(config)
  if config == nil or config.menu_key == nil then
    return
  end

  -- 1. Map your trigger shortcut straight to a clean, isolated native selection prompt script
  vim.keymap.set('n', config.menu_key, function()
    show_native_picker(config.menu_name, config.menu_bindings, nil)
  end, { desc = string.format('Toggle %s Picker', config.menu_name), silent = true })

  -- 2. Statically document the entry path inside Which-Key if it is installed
  -- This lists your menu cleanly as "\ ➜ PlatformIO" on their leader dash,
  -- but running it seamlessly drops straight out to Neovim's clean native engine selector!
  local ok, wk = pcall(require, 'which-key')
  if ok then
    wk.add({
      { config.menu_key, group = config.menu_name, icon = { icon = '  ', color = 'orange' } },
    })
  end
end

return M
