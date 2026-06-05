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

---Renders a pure, native floating window modeled exactly after the Helix menu layout
local function render_native_menu(title, items, on_back)
  -- 1. Format text strings and dynamically calculate perfect Helix column layout dimensions
  local display_lines = {}
  local key_mappings = {}
  local max_desc_len = 0

  for _, item in ipairs(items) do
    local label = item.node == 'menu' and ('+' .. item.desc) or item.desc
    if #label > max_desc_len then
      max_desc_len = #label
    end
  end

  for _, item in ipairs(items) do
    local shortcut_str = '[' .. item.shortcut .. ']'
    local label = item.node == 'menu' and ('+' .. item.desc) or item.desc

    -- THE VISUAL HELIX SIGNATURE: Perfectly padding descriptions left, right-aligning hotkey markers
    local padding = string.rep(' ', (max_desc_len - #label) + 4)
    table.insert(display_lines, '  ' .. label .. padding .. shortcut_str .. '  ')
    key_mappings[item.shortcut:lower()] = item
  end

  if on_back then
    table.insert(display_lines, string.rep('─', max_desc_len + 12))
    table.insert(display_lines, '  Back          [<BS>]  ')
  end

  -- 2. Compute window positioning metrics centering right over the current buffer screen
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, display_lines)

  local width = max_desc_len + 12
  local height = #display_lines
  local ui = vim.api.nvim_list_uis()[1]

  local win = vim.api.nvim_open_win(buf, true, {
    relative = 'editor',
    width = width,
    height = height,
    col = ui and ((ui.width - width) / 2) or 10,
    row = ui and ((ui.height - height) / 2) or 10,
    style = 'minimal',
    border = 'single',
    title = ' ' .. title .. ' ',
    title_pos = 'center',
  })

  -- Style the window using standard Neovim float highlights
  vim.wo[win].winhl = 'Normal:NormalFloat,Border:FloatBorder'
  vim.bo[buf].modifiable = false

  -- 3. Inline helper function to safely clean up window instances on keypress
  local function close_menu()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end

  -- 4. Keybinding interception maps inside the floating window
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
        -- Execute user item commands instantly
        vim.cmd(item.command)
      elseif item.node == 'menu' then
        -- Recursively tunnel deeper into custom submenus natively
        render_native_menu(item.desc, item.items, function()
          render_native_menu(title, items, on_back)
        end)
      end
    end, { buffer = buf, silent = true })
  end
end

---Processes the configuration parameters and sets up the native launch hotkey
function M.buildUserMenu(config)
  if config == nil or config.menu_key == nil then
    return
  end

  -- Bind your trigger shortcut key cleanly directly to our new native render loop
  vim.keymap.set('n', config.menu_key, function()
    render_native_menu(config.menu_name, config.menu_bindings, nil)
  end, { desc = string.format('Toggle %s Native Menu', config.menu_name), silent = true })

  -- Register a standard text placeholder description inside Which-Key if installed
  -- This guarantees your menu is listed cleanly as "\ ➜ PlatformIO" on their main leader dashboard!
  local ok, wk = pcall(require, 'which-key')
  if ok then
    wk.add({ { config.menu_key, group = config.menu_name } })
  end
end

return M
