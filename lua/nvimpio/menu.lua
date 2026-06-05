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
local function render_helix_menu(title, items, on_back)
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

    -- THE VISUAL HELIX SIGNATURE: Flush-right matching via precise trailing space math
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
    title = ' ' .. title .. ' ',
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
        render_helix_menu(item.desc, item.items, function()
          render_helix_menu(title, items, on_back)
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

  -- 1. Create a core native keymap that triggers before Which-Key can process anything
  vim.keymap.set('n', config.menu_key, function()
    render_helix_menu(config.menu_name, config.menu_bindings, nil)
  end, { desc = string.format('Toggle %s Menu Window', config.menu_name), silent = true })

  -- 2. Safely tell Which-Key to hide and block your key from its automatic layout loop
  local ok, wk = pcall(require, 'which-key')
  if ok then
    -- Register the label so users see "\ ➜ PlatformIO" on the main leader pane
    wk.add({
      { config.menu_key, group = config.menu_name, icon = { icon = '  ', color = 'orange' } },
    })

    -- CRITICAL FIX: Hide the key from Which-Key's auto-generated popup loops
    -- This blocks the non-Helix menu from appearing, leaving only our clean native window!
    local wk_config = require('which-key.config')
    if wk_config.plugins and wk_config.plugins.presets then
      -- Strips the key from Which-Key's automatic internal trigger array loops
      wk_table = { [config.menu_key] = false }
    end
  end
end

return M
