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

  -- 1. Grab your working, centered dropdown geometry configuration
  local dropdown = require('telescope.themes').get_dropdown({
    prompt_title = 'Select Environment',
    layout_config = { width = 38, height = #envs + 2 }, -- Forces it wide enough to show all envs
    borderchars = {
      prompt = { ' ', ' ', ' ', ' ', ' ', ' ', ' ', ' ' },
      results = { '─', '│', '─', '│', '╭', '╮', '╯', '╰' },
      preview = { '─', '│', '─', '│', '╭', '╮', '╯', '╰' },
    },
  })

  -- 2. Open a dedicated Telescope Picker (Prevents the 1-line collapsing bug!)
  require('telescope.pickers')
    .new(dropdown, {
      initial_mode = 'normal', -- Disables typing, allows arrow/number navigation instantly
      finder = require('telescope.finders').new_table({
        results = envs,
        entry_maker = function(name)
          local idx = vim.fn.index(envs, name) + 1
          local checkbox = (name == current_active) and '[x]' or '[ ]' -- Universal font safe
          return { value = name, display = string.format(' %d. %s %s', idx, checkbox, name), ordinal = name }
        end,
      }),
      sorter = require('telescope.config').values.generic_sorter(dropdown),
      attach_mappings = function(prompt_bufnr, map)
        local make_selection = function()
          local selection = require('telescope.actions.state').get_selected_entry()
          require('telescope.actions').close(prompt_bufnr)
          if selection then
            _G.metadata.active_env = selection.value
            vim.cmd('redrawstatus') -- Instantly updates your radio buttons on your statusline
            OS.notify(string.format('Swapped target -> %s', selection.value), 'info')
          end
        end
        map('n', '<CR>', make_selection)
        map('n', '<Space>', make_selection)

        -- 3. Map Number Keys (1, 2, 3...) to trigger instant JIT selection updates
        for idx = 1, math.min(#envs, 9) do
          map('n', tostring(idx), function()
            require('telescope.actions.state').get_current_picker(prompt_bufnr):set_selection(idx - 1)
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
--   local current_active = pio.get_active_env('UI Picker: ')
--   if not current_active or not _G.metadata or not _G.metadata.envs then
--     return
--   end
--
--   -- 1. Build an optimized, numbered menu list using basic brackets
--   local menu_lines = { '--- Select Active Target Environment ---' }
--   local envs = {}
--   for name, _ in pairs(_G.metadata.envs) do
--     table.insert(envs, name)
--   end
--   table.sort(envs)
--
--   for idx, name in ipairs(envs) do
--     local checkbox = (name == current_active) and '[x]' or '[ ]'
--     table.insert(menu_lines, string.format('%d. %s %s', idx, checkbox, name))
--   end
--
--   -- 2. Trigger Neovim's native selection engine instantly
--   -- Users just tap numbers (1, 2, 3) or use arrows to select a board!
--   local choice = vim.fn.inputlist(menu_lines)
--   if choice > 0 and choice <= #envs then
--     _G.metadata.active_env = envs[choice]
--     vim.cmd('redrawstatus') -- Swaps your statusline indicators immediately
--     OS.notify(string.format('PlatformIO target swapped -> %s', envs[choice]), 'info')
--   end
-- end
--
-- return M
-- local M = {}
--
-- function M.select_env_picker()
--   -- 1. Refresh active environments data structures via your engine
--   local current_active = pio.get_active_env('UI Picker: ')
--   if not current_active or not _G.metadata or not _G.metadata.envs then
--     return
--   end
--
--   -- 2. Extract and sort environment board strings cleanly
--   local envs = {}
--   for name, _ in pairs(_G.metadata.envs) do
--     table.insert(envs, name)
--   end
--   table.sort(envs)
--
--   -- 3. Calculate perfectly centered structural dimensions
--   local ui = vim.api.nvim_list_uis()[1]
--   if not ui then
--     return
--   end
--
--   local width = 36
--   local height = #envs + 2 -- Enforces padding lines above and below
--   local row = math.floor((ui.height - height) / 2)
--   local col = math.floor((ui.width - width) / 2)
--
--   -- 4. Open a clean, native floating window card
--   local bufnr = vim.api.nvim_create_buf(false, true)
--   local win_id = vim.api.nvim_open_win(bufnr, true, {
--     relative = 'editor',
--     width = width,
--     height = height,
--     row = row,
--     col = col,
--     style = 'minimal',
--     border = 'rounded',
--     title = ' Select Target Environment ',
--     title_pos = 'center',
--   })
--
--   -- Configure buffer flags to prevent user text insertion modifications
--   vim.bo[bufnr].buftype = 'nofile'
--   vim.bo[bufnr].bufhidden = 'wipe'
--
--   -- 5. Build and render the display rows
--   local display_lines = { '' } -- Top padding line
--   local target_cursor_row = 2
--
--   for idx, name in ipairs(envs) do
--     local checkbox = (name == current_active) and '[x]' or '[ ]'
--     -- Prefixes explicit numbers for quick reference visibility maps
--     table.insert(display_lines, string.format('  %d. %s %s', idx, checkbox, name))
--     if name == current_active then
--       target_cursor_row = idx + 1
--     end
--   end
--   table.insert(display_lines, '') -- Bottom padding line
--
--   vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, display_lines)
--   vim.bo[bufnr].modifiable = false
--
--   -- Position the active line focus cursor straight out of the gate
--   pcall(vim.api.nvim_win_set_cursor, win_id, { target_cursor_row, 2 })
--
--   -- 6. Interaction Handlers (Window termination and execution states)
--   local function close_win()
--     if vim.api.nvim_win_is_valid(win_id) then
--       vim.api.nvim_win_close(win_id, true)
--     end
--   end
--
--   local function confirm_choice()
--     local cursor = vim.api.nvim_win_get_cursor(win_id)
--     local chosen_env = envs[cursor[1] - 1] -- Remove top padding offset to get true array item index
--     if chosen_env then
--       _G.metadata.active_env = chosen_env
--       vim.cmd('redrawstatus') -- Sync statusline radio selections instantly
--       close_win()
--       OS.notify(string.format('PlatformIO target swapped -> %s', chosen_env), 'info')
--     end
--   end
--
--   -- 7. Define navigation constraints and keyboard maps inside the menu card
--   local k_opts = { buffer = bufnr, silent = true, noremap = true }
--
--   -- Restrict arrow navigation loops from sliding out into empty padding regions
--   vim.keymap.set('n', 'j', function()
--     local r = vim.api.nvim_win_get_cursor(win_id)[1]
--     if r < #envs + 1 then
--       vim.cmd('normal! j')
--     end
--   end, k_opts)
--
--   vim.keymap.set('n', 'k', function()
--     local r = vim.api.nvim_win_get_cursor(win_id)[1]
--     if r > 2 then
--       vim.cmd('normal! k')
--     end
--   end, k_opts)
--
--   -- Selection maps
--   vim.keymap.set('n', '<CR>', confirm_choice, k_opts)
--   vim.keymap.set('n', '<Space>', confirm_choice, k_opts)
--
--   -- Quit windows maps
--   vim.keymap.set('n', '<Esc>', close_win, k_opts)
--   vim.keymap.set('n', 'q', close_win, k_opts)
--
--   -- 8. NUMBER KEY SHORTCUT MAPS: Typing '1', '2' chooses that environment row immediately
--   for idx = 1, math.min(#envs, 9) do
--     vim.keymap.set('n', tostring(idx), function()
--       -- Highlight the row line instantly and execute confirmation callbacks JIT
--       pcall(vim.api.nvim_win_set_cursor, win_id, { idx + 1, 2 })
--       confirm_choice()
--     end, k_opts)
--   end
-- end
--
-- return M
