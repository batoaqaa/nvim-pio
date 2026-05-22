local M = {}

-- stylua: ignore
function M.merge_menu_tree(defaults, overrides, path)
  -- 1. Fast fallback return if no valid overrides are provided
  if type(overrides) ~= 'table' then
    return vim.deepcopy(defaults)
  end

  -- 2. Create a clean deep copy of defaults so we never mutate the factory settings
  local res = vim.deepcopy(defaults)

  -- 3. Sequentially process every single node item the user passed in
  for _, u_node in ipairs(overrides) do
    if type(u_node) == 'table' and u_node.shortcut then
      -- DYNAMIC LOOKUP LAYER: Re-index shortcuts on every pass to track newly appended items!
      local matched_node = nil
      for _, existing_item in ipairs(res) do
        if existing_item.shortcut == u_node.shortcut then
          matched_node = existing_item
          break
        end
      end

      if matched_node then
        -- SCENARIO A: The item exists in our defaults. Carefully patch allowed properties.
        if u_node.node and u_node.node ~= matched_node.node then
          error(string.format("Structure Error at %s: Cannot mutate structural node type from '%s' to '%s'", path, matched_node.node, u_node.node), 0)
        end

        if u_node.desc then matched_node.desc = u_node.desc end
        if u_node.command then matched_node.command = u_node.command end

        -- Recursive call to process nested submenu list items safely
        if matched_node.node == 'menu' and u_node.items then
          matched_node.items = M.merge_menu_tree(matched_node.items or {}, u_node.items, path .. '.items')
        end
      else
        -- SCENARIO B: Brand new item! Deep copy it to prevent reference tracking memory leakage bugs
        local new_node = vim.deepcopy(u_node)
        new_node.node = new_node.node or 'item'

        -- If they appended a brand new menu shell block, recursively build its internal array items
        if new_node.node == 'menu' then
          new_node.items = M.merge_menu_tree({}, u_node.items or {}, path .. '.items')
        end

        -- Safely append to the main list array. It will now collect EVERY appended item perfectly!
        table.insert(res, new_node)
      end
    end
  end

  return res
end

function M.buildUserMenu(config)
  local icon = { icon = '  ', color = 'orange' } -- Assign platformio orange icon
  local wk_table = { mode = { 'n', 'v' } }

  local function traverseMenu(menu, wkey)
    for _, child_node in ipairs(menu) do
      if child_node.node == 'menu' then
        traverseMenu(child_node.items, wkey .. child_node.shortcut)
        table.insert(wk_table, { wkey .. child_node.shortcut, group = child_node.desc, icon = icon })
      elseif child_node.node == 'item' then
        table.insert(wk_table, {
          wkey .. child_node.shortcut,
          '<cmd> ' .. child_node.command .. '<CR>',
          desc = child_node.desc,
          icon = icon,
        })
      end
    end
  end
  if config.menu_key == nil then
    return
  end

  local wk_config = { preset = 'helix' }
  local is_whichkey_loaded = package.loaded['which-key'] ~= nil
  local ok, wk = pcall(require, 'which-key')
  if ok then
    if not is_whichkey_loaded then
      wk.setup({
        preset = 'helix', --"classic", --"helix", --
        delay = 0,
        icons = {
          -- set icon mappings to true if you have a Nerd Font
          mappings = vim.g.have_nerd_font,
          -- If you are using a Nerd Font: set icons.keys to an empty table which will use the
          -- default which-key.nvim defined Nerd Font icons, otherwise define a string table
          keys = vim.g.have_nerd_font and {} or {
            Up = '<Up> ',
            Down = '<Down> ',
            Left = '<Left> ',
            Right = '<Right> ',
            C = '<C-…> ',
            M = '<M-…> ',
            D = '<D-…> ',
            S = '<S-…> ',
            CR = '<CR> ',
            Esc = '<Esc> ',
            ScrollWheelDown = '<ScrollWheelDown> ',
            ScrollWheelUp = '<ScrollWheelUp> ',
            NL = '<NL> ',
            BS = '<BS> ',
            Space = '<Space> ',
            Tab = '<Tab> ',
            F1 = '<F1>',
            F2 = '<F2>',
            F3 = '<F3>',
            F4 = '<F4>',
            F5 = '<F5>',
            F6 = '<F6>',
            F7 = '<F7>',
            F8 = '<F8>',
            F9 = '<F9>',
            F10 = '<F10>',
            F11 = '<F11>',
            F12 = '<F12>',
          },
        },
        -- sort = { "order", "group", "manual", "mod" },
        sort = { 'local', 'order', 'group', 'alphanum', 'mod' },
      }) --'modern', --'classic'
    else
      local wk_settings = require('which-key.settings')
      wk_settings.current = vim.tbl_deep_extend('force', wk_settings.current or {}, wk_config)
    end
    -- vim.api.nvim_echo({ { 'which-key plugin not found!', 'ErrorMsg' } }, true, {})
    -- return
  end

  local wkConfig = require('which-key.config')
  wkConfig.sort = { 'order', 'group', 'manual', 'mod' }

  table.insert(wk_table, { config.menu_key, group = config.menu_name, icon = icon })

  traverseMenu(config.menu_bindings, config.menu_key)

  wk.add(wk_table)
end

return M
