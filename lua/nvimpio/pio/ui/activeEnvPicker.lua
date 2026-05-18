local pio = require('nvimpio.pio.upkeep')

local M = {}

function M.select_env_picker()
  -- 1. Refresh active environments data structures via your engine
  local current_active = pio.get_active_env('UI Picker: ')
  if not current_active or not _G.metadata or not _G.metadata.envs then
    return
  end

  -- 2. Extract and sort environment board strings cleanly
  local envs = {}
  for name, _ in pairs(_G.metadata.envs) do
    table.insert(envs, name)
  end
  table.sort(envs)

  local pickers = require('telescope.pickers')
  local finders = require('telescope.finders')
  local actions = require('telescope.actions')
  local action_state = require('telescope.actions.state')
  local conf = require('telescope.config').values

  -- Calculate precise bounded scaling geometry based on list length parameters
  local calculated_height = #envs + 2
  local win_height = math.max(calculated_height, 4)

  -- 3. INSTANTIATE THE PICKER WINDOW CORE
  pickers
    .new({}, {
      prompt_title = 'Select Target Environment',
      initial_mode = 'normal', -- Disables terminal input text typing completely
      sorting_strategy = 'ascending', -- Keeps elements sorted from top to bottom
      layout_strategy = 'center', -- Forces dialog box to the dead center of the screen

      -- THE FIX FOR COLLAPSING: Geometry parameters must reside inside the explicit strategy key!
      layout_config = {
        center = {
          width = 42,
          height = win_height, -- Tells Telescope exactly how many rows to display
        },
      },

      borderchars = {
        prompt = { '─', '│', '─', '│', '╭', '╮', '╯', '╰' },
        results = { '─', '│', '─', '│', '├', '┤', '╯', '╰' },
        preview = { '─', '│', '─', '│', '╭', '╮', '╯', '╰' },
      },

      finder = finders.new_table({
        results = envs,
        entry_maker = function(name)
          -- Identify the numeric index rank location of this item row segment
          local row_num = 0
          for i, val in ipairs(envs) do
            if val == name then
              row_num = i
              break
            end
          end

          -- Nerd Font V3 icons that feature exactly matching width alignments
          local radio_icon = (name == current_active) and ' ' or ' '

          -- Formats index selection numbers cleanly onto the left column row text
          local display_text = string.format(' %d. %s %s', row_num, radio_icon, name)

          return {
            value = name,
            display = display_text,
            ordinal = name,
          }
        end,
      }),

      sorter = conf.generic_sorter({}),

      attach_mappings = function(prompt_bufnr, map)
        local function make_selection()
          local selection = action_state.get_selected_entry()
          actions.close(prompt_bufnr)
          if selection then
            _G.metadata.active_env = selection.value
            vim.cmd('redrawstatus') -- Instantly redraws your statusline indicators
            OS.notify(string.format('PlatformIO active_env swapped -> %s', selection.value), 'info')
          end
        end

        -- Action: Map traditional navigation confirmation keys
        map('n', '<CR>', make_selection)
        map('n', '<Space>', make_selection)

        -- 4. NUMBER KEY MAP ROUTER: Direct binding map for '1' through '9' choices
        for idx = 1, math.min(#envs, 9) do
          map('n', tostring(idx), function()
            local picker_instance = action_state.get_current_picker(prompt_bufnr)
            -- Move Telescope's internal focus selection state array index pointer (0-based)
            picker_instance:set_selection(idx - 1)
            make_selection()
          end)
        end

        return true
      end,
    })
    :find()
end

return M

-- local M = {}
--
-- function M.select_env_picker()
--   -- 1. Refresh active environments data structures via your engine
--   local current_active = pio.get_active_env('UI Picker: ')
--   if not current_active or not _G.metadata or not _G.metadata.envs then
--     return
--   end
--
--   -- 2. Gather and sort environment names cleanly
--   local envs = {}
--   for name, _ in pairs(_G.metadata.envs) do
--     table.insert(envs, name)
--   end
--   table.sort(envs)
--
--   -- 3. CRITICAL INITIALIZATION PASS (Copying your working Terminal List architecture!)
--   -- This guarantees Telescope intercepts our upcoming vim.ui.select loop natively!
--   local telescope = require('telescope')
--   telescope.setup({
--     extensions = {
--       ['ui-select'] = {
--         require('telescope.themes').get_dropdown({
--           -- Your custom clean border configuration rules
--           borderchars = {
--             prompt = { ' ', ' ', ' ', ' ', ' ', ' ', ' ', ' ' },
--             results = { ' ', ' ', ' ', ' ', ' ', ' ', ' ', ' ' },
--             preview = { '─', '│', '─', '│', '╭', '╮', '╯', '╰' },
--           },
--           prompt_position = 'top',
--           prompt_prefix = '🔍 ',
--           selection_caret = '❯ ',
--           entry_prefix = '  ',
--           initial_mode = 'insert',
--           scroll_strategy = 'cycle',
--           sorting_strategy = 'ascending',
--           color_devicons = true,
--           use_less = true,
--         }),
--       },
--     },
--   })
--   telescope.load_extension('ui-select')
--
--   -- 4. Invoke the picker. It will now consistently render as a beautiful centered GUI card!
--   vim.ui.select(envs, {
--     prompt = 'Select Active Hardware Target:',
--     kind = 'nvimpio_env_selector',
--
--     -- Format your options with stylized checkboxes/radio buttons
--     format_item = function(name)
--       return (name == current_active) and (' [●] ' .. name) or (' [○ ] ' .. name)
--     end,
--   }, function(choice)
--     if choice then
--       -- Commit choice to global tracking contexts
--       _G.metadata.active_env = choice
--
--       -- Instantly update statusline markers
--       vim.cmd('redrawstatus')
--
--       OS.notify(string.format('PlatformIO active_env swapped -> %s', choice), 'info')
--     else
--       vim.api.nvim_echo({ { 'No environment target selected.', 'Normal' } }, true, {})
--     end
--   end)
-- end
--
-- return M

-- local M = {}
--
-- function M.select_env_picker()
--   local current_active = pio.get_active_env('UI Picker: ')
--   if not current_active or not _G.metadata or not _G.metadata.envs then
--     return
--   end
--
--   local envs = {}
--   for name, _ in pairs(_G.metadata.envs) do
--     table.insert(envs, name)
--   end
--   table.sort(envs)
--
--   -- 1. Use an explicit, styled GUI block configuration
--   local gui_dialog = require('telescope.themes').get_dropdown({
--     -- Hide structural line text prompts entirely to look like a small window card
--     prompt_prefix = '   ',
--     selection_caret = ' ❯ ',
--
--     -- Force a small, square dialogue geometry in the dead center
--     layout_strategy = 'center',
--     layout_config = {
--       width = 32,
--       height = #envs + 2,
--     },
--
--     -- Strip out top line prompt structures so it acts purely as a selector list
--     borderchars = {
--       prompt = { ' ', ' ', ' ', ' ', ' ', ' ', ' ', ' ' },
--       results = { '─', '│', '─', '│', '╭', '╮', '╯', '╰' },
--       preview = { '─', '│', '─', '│', '╭', '╮', '╯', '╰' },
--     },
--   })
--
--   -- 2. Pass to the selection core with explicit checkbox decoration properties
--   vim.ui.select(envs, {
--     prompt = 'Select Environment Target',
--     kind = 'nvimpio_env_selector',
--     format_item = function(name)
--       -- Renders as stylized radio buttons [●] or [○]
--       return (name == current_active) and (' [●] ' .. name) or (' [○] ' .. name)
--     end,
--     telescope = gui_dialog,
--   }, function(choice)
--     if choice then
--       _G.metadata.active_env = choice
--       vim.cmd('redrawstatus') -- Instantly updates your statusline indicators
--       OS.notify(string.format('Swapped to -> %s', choice), 'info')
--     end
--   end)
-- end
--
-- return M

-- local M = {}
--
-- function M.select_env_picker()
--   local current_active = pio.get_active_env('UI Picker: ')
--   if not current_active or not _G.metadata or not _G.metadata.envs then
--     return
--   end
--
--   -- 1. Gather all environment names cleanly
--   local envs = {}
--   for name, _ in pairs(_G.metadata.envs) do
--     table.insert(envs, name)
--   end
--   table.sort(envs)
--
--   -- 2. Define a tiny, centered dropdown window config layout
--   local tiny_window = require('telescope.themes').get_dropdown({
--     prompt_prefix = ' ', -- Blank out the search prompt icon to look like a simple window
--     layout_config = { width = 35, height = #envs + 2 }, -- Force it small and narrow
--   })
--
--   -- 3. Leverage Neovim's selection core with native radio format parameters
--   vim.ui.select(envs, {
--     prompt = 'Select Target Environment',
--     kind = 'nvimpio_env_selector',
--     format_item = function(name)
--       -- Simple Radio Button UI decoration row
--       return (name == current_active) and (' [●] ' .. name) or (' [○] ' .. name)
--     end,
--     telescope = tiny_window,
--   }, function(choice)
--     if choice then
--       _G.metadata.active_env = choice
--       vim.cmd('redrawstatus') -- Instantly swap your statusline radio buttons
--       OS.notify(string.format('Swapped to -> %s', choice), 'info')
--     end
--   end)
-- end
--
-- return M

-- local pio = require('nvimpio.pio.upkeep')
--
-- local M = {}
--
-- -- Interactive Environment Selection Panel
-- function M.select_env_picker()
--   -- 1. Trigger JIT parsing to ensure _G.metadata state is completely fresh and populated
--   local current_active = pio.get_active_env('UI Picker: ')
--
--   -- Safety guard: Exit gracefully if platformio.ini was missing or empty
--   if not current_active or not _G.metadata or not _G.metadata.envs then
--     return
--   end
--
--   local display_options = {}
--   local lookup_map = {}
--
--   -- 2. Extract hardware keys directly out of our consolidated object dictionary
--   for env_name, _ in pairs(_G.metadata.envs) do
--     -- Active choice = Filled Circle (●), Available options = Empty Circle (○)
--     local icon = (env_name == current_active) and '● ' or '○ '
--     local row_text = string.format('%s%s', icon, env_name)
--
--     table.insert(display_options, row_text)
--     lookup_map[row_text] = env_name -- Maps the decorative UI row string back to the raw key
--   end
--
--   -- 3. Alphabetically sort display items so the picker rendering looks uniform
--   table.sort(display_options)
--
--   -- 4. Pass everything down to Neovim's native floating selection wrapper
--   vim.ui.select(display_options, {
--     prompt = ' Select Active Hardware Target ',
--     kind = 'nvimpio_env_selector',
--   }, function(choice)
--     if not choice then
--       return
--     end -- Gracefully handle user escape or cancel events (ESC)
--
--     local chosen_env = lookup_map[choice]
--     if chosen_env then
--       -- Commit choice to global reactive metadata register
--       _G.metadata.active_env = chosen_env
--
--       OS.notify(string.format('PlatformIO active_env swapped -> %s', chosen_env), 'info')
--     end
--   end)
-- end
--
-- return M
