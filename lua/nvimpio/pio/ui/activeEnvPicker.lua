local pio = require('nvimpio.pio.upkeep')

local M = {}

function M.select_env_picker()
  local current_active = pio.get_active_env('UI Picker: ')
  if not current_active or not _G.metadata or not _G.metadata.envs then
    return
  end

  local envs = {}
  for name, _ in pairs(_G.metadata.envs) do
    table.insert(envs, name)
  end
  table.sort(envs)

  -- 1. Use an explicit, styled GUI block configuration
  local gui_dialog = require('telescope.themes').get_dropdown({
    -- Hide structural line text prompts entirely to look like a small window card
    prompt_prefix = '   ',
    selection_caret = ' ❯ ',

    -- Force a small, square dialogue geometry in the dead center
    layout_strategy = 'center',
    layout_config = {
      width = 32,
      height = #envs + 2,
    },

    -- Strip out top line prompt structures so it acts purely as a selector list
    borderchars = {
      prompt = { ' ', ' ', ' ', ' ', ' ', ' ', ' ', ' ' },
      results = { '─', '│', '─', '│', '╭', '╮', '╯', '╰' },
      preview = { '─', '│', '─', '│', '╭', '╮', '╯', '╰' },
    },
  })

  -- 2. Pass to the selection core with explicit checkbox decoration properties
  vim.ui.select(envs, {
    prompt = 'Select Environment Target',
    kind = 'nvimpio_env_selector',
    format_item = function(name)
      -- Renders as stylized radio buttons [●] or [○]
      return (name == current_active) and (' [●] ' .. name) or (' [○] ' .. name)
    end,
    telescope = gui_dialog,
  }, function(choice)
    if choice then
      _G.metadata.active_env = choice
      vim.cmd('redrawstatus') -- Instantly updates your statusline indicators
      OS.notify(string.format('Swapped to -> %s', choice), 'info')
    end
  end)
end

return M

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
