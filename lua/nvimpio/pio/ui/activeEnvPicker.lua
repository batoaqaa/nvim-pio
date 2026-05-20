-- local pio = require('nvimpio.pio.upkeep')

local M = {}

function M.select_env_picker()
  if not _G.metadata or not _G.metadata.envs then
    return
  end
  local current_active = _G.metadata.active_env

  local envs = vim.tbl_keys(_G.metadata.envs)
  table.sort(envs)

  -- Set native floating window borders color to make sure it looks great
  vim.api.nvim_set_hl(0, 'FloatBorder', { fg = '#4ec9b0', bg = 'NONE' })

  vim.ui.select(envs, {
    prompt = 'Select Active Target Environment:',
    kind = 'nvimpio_env_selector',
    format_item = function(name)
      local idx = vim.fn.index(envs, name) + 1
      local line = string.format(' %d. %s %s', idx, (name == current_active) and '[x]' or '[ ]', name)

      -- FORCE WIDTH: Pad the string with spaces so it matches a minimum width (e.g., 45 characters)
      local target_width = 45
      local padding_needed = target_width - #line
      if padding_needed > 0 then
        line = line .. string.rep(' ', padding_needed)
      end

      return line
    end,
  }, function(choice)
    if choice then
      _G.metadata.active_env = choice
      vim.cmd('redrawstatus')
      OS.notify(string.format('PlatformIO target swapped -> %s', choice), 'info')
    end
  end)
end

return M
-- local M = {}
--
-- function M.select_env_picker()
--   if not _G.metadata or not _G.metadata.envs then
--     return
--   end
--   local current_active = _G.metadata.active_env
--
--   -- local envs = {}
--   -- for env_name, _ in pairs(_G.metadata.envs) do table.insert(envs, env_name) end
--   local envs = vim.tbl_keys(_G.metadata.envs)
--   table.sort(envs) -- Alphabetical sort for UI presentation
--
--   -- Force the highlight colors to activate right before the window opens
--   vim.api.nvim_set_hl(0, 'TelescopeBorder', { fg = '#4ec9b0', bg = 'NONE' })
--
--   vim.ui.select(envs, {
--     -- prompt = 'Select Active Target Environment:',
--     prompt = '',
--     kind = 'nvimpio_env_selector',
--     format_item = function(name)
--       local idx = vim.fn.index(envs, name) + 1
--       return string.format(' %d. %s %s', idx, (name == current_active) and '[x]' or '[ ]', name)
--     end,
--   }, function(choice)
--     if choice then
--       _G.metadata.active_env = choice
--       vim.cmd('redrawstatus')
--       OS.notify(string.format('PlatformIO target swapped -> %s', choice), 'info')
--     end
--   end)
-- end
--
-- return M

-- local M = {}
--
-- function M.select_env_picker()
--   -- Assume your engine populated _G.metadata.envs with your target table
--   if not _G.metadata or not _G.metadata.envs then
--     return
--   end
--   local current_active = _G.metadata.active_env
--   -- local current_active = pio.get_active_env('UI Picker: ')
--
--   -- 1. EXTRACT KEYS: Use pairs() to harvest the environment board names
--   -- local envs = {}
--   -- for env_name, _ in pairs(_G.metadata.envs) do
--   --   table.insert(envs, env_name)
--   -- end
--   local envs = vim.tbl_keys(_G.metadata.envs)
--   table.sort(envs) -- Alphabetical sort for UI presentation
--
--   -- 2. Build the Centered Dropdown GUI Theme Geometry
--   local theme = require('telescope.themes').get_dropdown({
--     prompt_title = 'Select Environment',
--     results_title = 'Available Boards',
--
--     -- ADJUSTMENT 1: Increase the height container envelope size multiplier!
--     -- Changing this to #envs + 5 or #envs + 6 gives the window plenty of extra row lines.
--     layout_config = {
--       width = 38,
--       height = #envs + 5,
--     },
--
--     -- ADJUSTMENT 2: Restore the top framing borders of the prompt container window canopy.
--     -- Wiping these entirely causes the dropdown engine to collapse internal height spaces.
--     borderchars = {
--       prompt = { '─', '│', ' ', '│', '╭', '╮', '│', '│' },
--       results = { '─', '│', '─', '│', '├', '┤', '╯', '╰' },
--       preview = { '─', '│', '─', '│', '╭', '╮', '╯', '╰' },
--     },
--   })
--
--   -- 3. Execute the standard Telescope Dialogue Window Card
--   require('telescope.pickers')
--     .new(theme, {
--       initial_mode = 'insert',
--       finder = require('telescope.finders').new_table({
--         results = envs,
--         entry_maker = function(name)
--           local idx = vim.fn.index(envs, name) + 1
--           local checkbox = (name == current_active) and '[x]' or '[ ]' -- Universal font-safe format
--           return { value = name, display = string.format(' %d. %s %s', idx, checkbox, name), ordinal = name }
--         end,
--       }),
--       sorter = require('telescope.config').values.generic_sorter(theme),
--       attach_mappings = function(prompt_bufnr, map)
--         local make_selection = function()
--           local selection = require('telescope.actions.state').get_selected_entry()
--           require('telescope.actions').close(prompt_bufnr)
--           if selection then
--             _G.metadata.active_env = selection.value
--             vim.cmd('redrawstatus') -- Swaps your statusline indicators immediately
--             OS.notify(string.format('PlatformIO target swapped -> %s', selection.value), 'info')
--           end
--         end
--
--         -- Map normal mode keys
--         map('n', '<CR>', make_selection)
--         map('n', '<Space>', make_selection)
--
--         -- Map insert mode keys (Since your config sets initial_mode = 'insert'!)
--         map('i', '<CR>', make_selection)
--
--         -- Map Number Keys (1, 2, 3...) to trigger instant target updates
--         -- Added both normal ('n') and insert ('i') support so typing numbers jumps instantly!
--         for idx = 1, math.min(#envs, 9) do
--           local handler = function()
--             require('telescope.actions.state').get_current_picker(prompt_bufnr):set_selection(idx - 1)
--             make_selection()
--           end
--           map('n', tostring(idx), handler)
--           map('i', tostring(idx), handler)
--         end
--         return true
--       end,
--     })
--     :find()
-- end
-- return M
