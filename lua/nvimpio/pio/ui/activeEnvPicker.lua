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

  -- 3. Calculate perfectly centered structural dimensions
  local ui = vim.api.nvim_list_uis()[1]
  if not ui then
    return
  end

  local width = 36
  local height = #envs + 2 -- Enforces padding lines above and below
  local row = math.floor((ui.height - height) / 2)
  local col = math.floor((ui.width - width) / 2)

  -- 4. Open a clean, native floating window card
  local bufnr = vim.api.nvim_create_buf(false, true)
  local win_id = vim.api.nvim_open_win(bufnr, true, {
    relative = 'editor',
    width = width,
    height = height,
    row = row,
    col = col,
    style = 'minimal',
    border = 'rounded',
    title = ' Select Target Environment ',
    title_pos = 'center',
  })

  -- Configure buffer flags to prevent user text insertion modifications
  vim.bo[bufnr].buftype = 'nofile'
  vim.bo[bufnr].bufhidden = 'wipe'

  -- 5. Build and render the display rows
  local display_lines = { '' } -- Top padding line
  local target_cursor_row = 2

  for idx, name in ipairs(envs) do
    local checkbox = (name == current_active) and '[x]' or '[ ]'
    -- Prefixes explicit numbers for quick reference visibility maps
    table.insert(display_lines, string.format('  %d. %s %s', idx, checkbox, name))
    if name == current_active then
      target_cursor_row = idx + 1
    end
  end
  table.insert(display_lines, '') -- Bottom padding line

  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, display_lines)
  vim.bo[bufnr].modifiable = false

  -- Position the active line focus cursor straight out of the gate
  pcall(vim.api.nvim_win_set_cursor, win_id, { target_cursor_row, 2 })

  -- 6. Interaction Handlers (Window termination and execution states)
  local function close_win()
    if vim.api.nvim_win_is_valid(win_id) then
      vim.api.nvim_win_close(win_id, true)
    end
  end

  local function confirm_choice()
    local cursor = vim.api.nvim_win_get_cursor(win_id)
    local chosen_env = envs[cursor[1] - 1] -- Remove top padding offset to get true array item index
    if chosen_env then
      _G.metadata.active_env = chosen_env
      vim.cmd('redrawstatus') -- Sync statusline radio selections instantly
      close_win()
      OS.notify(string.format('PlatformIO target swapped -> %s', chosen_env), 'info')
    end
  end

  -- 7. Define navigation constraints and keyboard maps inside the menu card
  local k_opts = { buffer = bufnr, silent = true, noremap = true }

  -- Restrict arrow navigation loops from sliding out into empty padding regions
  vim.keymap.set('n', 'j', function()
    local r = vim.api.nvim_win_get_cursor(win_id)[1]
    if r < #envs + 1 then
      vim.cmd('normal! j')
    end
  end, k_opts)

  vim.keymap.set('n', 'k', function()
    local r = vim.api.nvim_win_get_cursor(win_id)[1]
    if r > 2 then
      vim.cmd('normal! k')
    end
  end, k_opts)

  -- Selection maps
  vim.keymap.set('n', '<CR>', confirm_choice, k_opts)
  vim.keymap.set('n', '<Space>', confirm_choice, k_opts)

  -- Quit windows maps
  vim.keymap.set('n', '<Esc>', close_win, k_opts)
  vim.keymap.set('n', 'q', close_win, k_opts)

  -- 8. NUMBER KEY SHORTCUT MAPS: Typing '1', '2' chooses that environment row immediately
  for idx = 1, math.min(#envs, 9) do
    vim.keymap.set('n', tostring(idx), function()
      -- Highlight the row line instantly and execute confirmation callbacks JIT
      pcall(vim.api.nvim_win_set_cursor, win_id, { idx + 1, 2 })
      confirm_choice()
    end, k_opts)
  end
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
