local M = {}

-- Memory slots to preserve running background process stream job IDs
local pio_cli_job = nil
local pio_mon_job = nil

-- Caches to hold the last visible line output from the background process streams
local pio_cli_last_line = 'No active PlatformIO compilation processes running.'
local pio_mon_last_line = 'No active device hardware diagnostic logs.'

-- Toggle tracking flags to manage the global overlay line panel
local is_panel_open = false
local active_view = 'cli'

----------------------------------------------------------------------------------------
-- INFO: Core Layout Generator (Global Statusline Console Panel Engine)
function M.ToggleTerminal(command, terminal_type)
  -- 1. Enforce strict title header assignments immediately at the top
  if terminal_type == 'monitor' or (command and string.find(command, ' monitor')) then
    terminal_type = 'monitor'
    active_view = 'monitor'
  else
    terminal_type = 'cli'
    active_view = 'cli'
  end

  -- 2. TOGGLE ACTION: If the panel is already active, hide it and clear the status row
  if is_panel_open and command == '' then
    vim.o.statusline = '' -- Instantly restores the user's native statusline configuration
    is_panel_open = false
    return
  end

  is_panel_open = true

  -- 3. PROCESS PERSISTENCE LAYER: Spawn the background process thread if it doesn't exist yet
  local current_job = (terminal_type == 'monitor') and pio_mon_job or pio_cli_job

  if not current_job then
    local target_shell = vim.o.shell
    if vim.fn.has('win32') == 1 then
      target_shell = 'powershell.exe'
    end

    -- Start the background process thread cleanly without deprecated functions
    local job_id = vim.fn.jobstart(target_shell, {
      term = false, -- Headless background data pipe stream
      on_stdout = function(_, data)
        if data and #data > 0 then
          -- Grab the very last string line emitted by the active PlatformIO stream
          for i = #data, 1, -1 do
            if data[i] ~= '' then
              local clean = data[i]:gsub('\r', '')
              if terminal_type == 'monitor' then
                pio_mon_last_line = clean
              else
                pio_cli_last_line = clean
              end
              break
            end
          end

          -- Automatically force a clean interface refresh to display incoming log data live
          if is_panel_open then
            vim.cmd('redrawstatus')
          end
        end
      end,
    })

    if terminal_type == 'monitor' then
      pio_mon_job = job_id
    else
      pio_cli_job = job_id
    end
  end

  -- 4. THE PANEL RENDER ENGINE: Custom global status bar layout block
  -- This intercepts the editor layout baseline and draws your shell text stream
  -- across 100% horizontal screen width. Completely immune to sidebars!
  local function UpdateGlobalPanel()
    local display_text = (active_view == 'monitor') and pio_mon_last_line or pio_cli_last_line
    local title = (active_view == 'monitor') and ' Pio Monitor ' or ' Pio CLI> '

    -- Form your custom highlight themes dynamically inside the bar string
    return '%#MyWinBar#' .. title .. '%* ' .. display_text .. ' %=' .. '[Press ;; to Swap Views]'
  end

  -- Mount the layout function directly into Neovim's global environment
  local hl = { bg = '#80a3d4', fg = '#000000' }
  vim.api.nvim_set_hl(0, 'MyWinBar', { bg = hl.bg, fg = hl.fg })

  _G.PioGlobalConsolePanel = UpdateGlobalPanel
  vim.o.statusline = '%{%v:lua.PioGlobalConsolePanel()%}'

  -----------------------------------------------------------------------------
  -- GLOBAL NAVIGATION & SHORTCUT COMPATIBILITY
  -----------------------------------------------------------------------------
  vim.keymap.set('n', '<C-h>', '<C-w>h')
  vim.keymap.set('n', '<C-l>', '<C-w>l')
  vim.keymap.set('n', '<C-j>', '<C-w>j')
  vim.keymap.set('n', '<C-k>', '<C-w>k')

  -- HOME-ROW CROSS SWITCHER: Double tap semi-colon (;;) to cross-fade streams instantly!
  vim.keymap.set('n', ';;', function()
    active_view = (active_view == 'monitor') and 'cli' or 'monitor'
    vim.cmd('redrawstatus')
  end, { silent = true, desc = 'Switch between PlatformIO terminal logs' })

  if terminal_type == 'monitor' then
    vim.keymap.set('n', [[<leader>\gm]], function()
      M.ToggleTerminal('', 'monitor')
    end, { silent = true })
  else
    vim.keymap.set('n', [[<leader>\t]], function()
      M.ToggleTerminal('', 'cli')
    end, { silent = true })
  end
  -----------------------------------------------------------------------------

  -- Pass PlatformIO macro command strings directly down through the active background stream
  if command and command ~= '' then
    local active_chan = (terminal_type == 'monitor') and pio_mon_job or pio_cli_job
    if active_chan then
      -- Stream your compilation command strings safely over the modern API channel pipe
      vim.api.nvim_chan_send(active_chan, command .. '\n')
    end
  end
end

return M
-- local M = {}
--
-- -- Memory slots to preserve running terminal process background buffers
-- local pio_cli_buf = nil
-- local pio_mon_buf = nil
--
-- -- Memory trackers for the active window IDs
-- local pio_cli_win = nil
-- local pio_mon_win = nil
--
-- ----------------------------------------------------------------------------------------
-- -- INFO: Safe Window Closure Logic (Tied to pressing 'q' inside normal mode)
-- local function HideTerminalWindow(terminal_type)
--   local target_win = (terminal_type == 'monitor') and pio_mon_win or pio_cli_win
--   if target_win and vim.api.nvim_win_is_valid(target_win) then
--     vim.api.nvim_win_close(target_win, true)
--   end
--   if terminal_type == 'monitor' then
--     pio_mon_win = nil
--   else
--     pio_cli_win = nil
--   end
-- end
--
-- ----------------------------------------------------------------------------------------
-- -- INFO: Core Layout Spawner (Buffer-Relative Overlay Framework)
-- function M.ToggleTerminal(command, terminal_type)
--   -- 1. Enforce strict title header assignments immediately at the top
--   local title = ''
--   if terminal_type == 'monitor' or (command and string.find(command, ' monitor')) then
--     title = 'Pio Monitor'
--     terminal_type = 'monitor'
--   else
--     title = 'Pio CLI>'
--     terminal_type = 'cli'
--   end
--
--   local target_win = (terminal_type == 'monitor') and pio_mon_win or pio_cli_win
--   local other_win = (terminal_type == 'monitor') and pio_cli_win or pio_mon_win
--   local target_buf = (terminal_type == 'monitor') and pio_mon_buf or pio_cli_buf
--
--   -- 2. MUTUAL EXCLUSION: If the other terminal panel window is visible, hide it first
--   if other_win and vim.api.nvim_win_is_valid(other_win) then
--     vim.api.nvim_win_close(other_win, true)
--     if terminal_type == 'monitor' then
--       pio_cli_win = nil
--     else
--       pio_mon_win = nil
--     end
--   end
--
--   -- 3. TOGGLE ACTION: If our target window is already open, close it
--   if target_win and vim.api.nvim_win_is_valid(target_win) then
--     vim.api.nvim_win_close(target_win, true)
--     if terminal_type == 'monitor' then
--       pio_mon_win = nil
--     else
--       pio_cli_win = nil
--     end
--     return
--   end
--
--   -- 4. PROCESS PERSISTENCE: Pure native unlisted scratch buffer generation
--   if not target_buf or not vim.api.nvim_buf_is_valid(target_buf) then
--     target_buf = vim.api.nvim_create_buf(false, true) -- Unlisted scratch buffer
--     if terminal_type == 'monitor' then
--       pio_mon_buf = target_buf
--     else
--       pio_cli_buf = target_buf
--     end
--
--     -- Determine target windows platform shell engine cleanly
--     local target_shell = vim.o.shell
--     if vim.fn.has('win32') == 1 then
--       target_shell = 'powershell.exe'
--     end
--
--     -- Run the shell cleanly. This sets 'buftype' to 'terminal' natively, fixing typing bugs!
--     vim.api.nvim_buf_call(target_buf, function()
--       vim.fn.termopen(target_shell)
--     end)
--   end
--
--   -- 5. THE BUFFER-RELATIVE LAYOUT FIX:
--   -- We anchor the float directly to the user's active file pane window handle (win = parent_file_win).
--   -- This makes your terminal completely immune to being smashed or squeezed by Aerial or Neo-tree!
--   local parent_file_win = vim.api.nvim_get_current_win()
--   local file_win_width = vim.api.nvim_win_get_width(parent_file_win)
--   local file_win_height = vim.api.nvim_win_get_height(parent_file_win)
--
--   local target_height = math.ceil(file_win_height * 0.32)
--
--   local win_opts = {
--     relative = 'win', -- HARD-LOCKS TO THE FILE WINDOW ONLY: Bypasses monitor grid completely
--     win = parent_file_win, -- Binds the coordinate system to their current text document pane
--     style = 'minimal', -- Disables border and padding overheads
--     focusable = true, -- Keeps keyboard layout paths fully operational
--     width = file_win_width, -- Stretches exactly to the margins of their code file pane
--     height = target_height,
--     row = file_win_height - target_height, -- Clamps precisely to the bottom of the file view
--     col = 0, -- Starts flush with the left edge of their text
--   }
--
--   -- 6. RENDER THE SECURE HORIZONTAL PANEL OVERLAY
--   local new_win = vim.api.nvim_open_win(target_buf, true, win_opts)
--   if terminal_type == 'monitor' then
--     pio_mon_win = new_win
--   else
--     pio_cli_win = new_win
--   end
--
--   -- 7. CLEAN SYSTEM OPTIONS DECORATIONS
--   vim.cmd('setlocal nonumber norelativenumber signcolumn=no')
--   vim.api.nvim_set_option_value('winfixheight', true, { scope = 'local', win = new_win })
--
--   -- 8. VISUAL CUSTOM WINBAR STYLING
--   local hl = { bg = '#80a3d4', fg = '#000000' }
--   vim.api.nvim_set_hl(0, 'MyWinBar', { bg = hl.bg, fg = hl.fg })
--   local winBartitle = '%#MyWinBar# ' .. title .. ' [Press ;; to Switch | Press q to hide]%*'
--   vim.api.nvim_set_option_value('winbar', winBartitle, { scope = 'local', win = new_win })
--
--   -----------------------------------------------------------------------------
--   -- LOCAL MAPS (Scoped strictly to this terminal buffer layer instance)
--   -----------------------------------------------------------------------------
--   vim.keymap.set('t', '<Esc>', [[<C-\><C-n>]], { buffer = target_buf })
--   vim.keymap.set('n', 'q', function()
--     HideTerminalWindow(terminal_type)
--   end, { buffer = target_buf })
--
--   -- CRASH-FREE UPWARD NAVIGATION KEYMAP
--   vim.keymap.set({ 'n', 't' }, '<C-k>', function()
--     if vim.api.nvim_get_mode().mode == 't' then
--       local esc = vim.api.nvim_replace_termcodes([[<C-\><C-n>]], true, true, true)
--       vim.api.nvim_feedkeys(esc, 'n', false)
--     end
--     vim.schedule(function()
--       if parent_file_win and vim.api.nvim_win_is_valid(parent_file_win) then
--         vim.api.nvim_set_current_win(parent_file_win)
--       end
--     end)
--   end, { buffer = target_buf, silent = true })
--
--   -- DOUBLE SEMI-COLON CROSS SWITCHER LOGIC
--   vim.keymap.set({ 'n', 't' }, ';;', function()
--     if vim.api.nvim_get_mode().mode == 't' then
--       local esc = vim.api.nvim_replace_termcodes([[<C-\><C-n>]], true, true, true)
--       vim.api.nvim_feedkeys(esc, 'n', false)
--     end
--
--     local next_type = (terminal_type == 'monitor') and 'cli' or 'monitor'
--     vim.schedule(function()
--       M.ToggleTerminal('', next_type)
--     end)
--   end, { buffer = target_buf, silent = true, desc = 'Switch between PlatformIO terminals' })
--
--   -----------------------------------------------------------------------------
--   -- GLOBAL NAVIGATION & RECALL SHORTCUTS
--   -----------------------------------------------------------------------------
--   vim.keymap.set('n', '<C-h>', '<C-w>h')
--   vim.keymap.set('n', '<C-l>', '<C-w>l')
--
--   -- GLOBAL INTERCEPT DOWNWARD MOVEMENT HOOK:
--   -- Focuses your cursor straight down into your active terminal pane natively
--   vim.keymap.set('n', '<C-j>', function()
--     if new_win and vim.api.nvim_win_is_valid(new_win) then
--       vim.api.nvim_set_current_win(new_win)
--       vim.cmd('startinsert')
--     else
--       vim.cmd('wincmd j')
--     end
--   end, { silent = true })
--
--   if terminal_type == 'monitor' then
--     vim.keymap.set('n', [[<leader>\gm]], function()
--       M.ToggleTerminal('', 'monitor')
--     end, { silent = true })
--   else
--     vim.keymap.set('n', [[<leader>\t]], function()
--       M.ToggleTerminal('', 'cli')
--     end, { silent = true })
--   end
--   -----------------------------------------------------------------------------
--
--   -- Automatically run passed command strings via your platformio job channels
--   if command and command ~= '' then
--     local job_id = vim.b[target_buf].terminal_job_id
--     if job_id then
--       vim.fn.chansend(job_id, command .. (vim.fn.has('win32') == 1 and '\r\n' or '\n'))
--     end
--   end
--
--   vim.cmd('startinsert')
-- end
--
-- return M

-- local M = {}
--
-- -- Memory trackers for your two persistent plugin terminal buffers
-- local pio_cli_buf = nil
-- local pio_mon_buf = nil
--
-- -- Memory trackers for the active floating window IDs
-- local pio_cli_win = nil
-- local pio_mon_win = nil
--
-- -- Tracks layout states to shrink and restore the text editor window cleanly
-- local saved_code_win = nil
-- local saved_code_height = nil
--
-- ----------------------------------------------------------------------------------------
-- -- INFO: Safe Window Closure Logic (Tied to pressing 'q' inside normal mode)
-- local function HideTerminalWindow(terminal_type)
--   local target_win = (terminal_type == 'monitor') and pio_mon_win or pio_cli_win
--   if target_win and vim.api.nvim_win_is_valid(target_win) then
--     vim.api.nvim_win_close(target_win, true)
--   end
--   if terminal_type == 'monitor' then
--     pio_mon_win = nil
--   else
--     pio_cli_win = nil
--   end
--
--   -- PREMIUM RESIZE RESTORATION: Snap the code window back to 100% full screen height
--   if saved_code_win and vim.api.nvim_win_is_valid(saved_code_win) and saved_code_height then
--     vim.api.nvim_win_set_height(saved_code_win, saved_code_height)
--     saved_code_win = nil
--     saved_code_height = nil
--   end
-- end
--
-- ----------------------------------------------------------------------------------------
-- -- INFO: Core Layout Spawner (Global Edge-Anchored Overlay Architecture)
-- function M.ToggleTerminal(command, terminal_type)
--   -- 1. Enforce strict title header assignments immediately at the top
--   local title = ''
--   if terminal_type == 'monitor' or (command and string.find(command, ' monitor')) then
--     title = 'Pio Monitor'
--     terminal_type = 'monitor'
--   else
--     title = 'Pio CLI>'
--     terminal_type = 'cli'
--   end
--
--   local target_win = (terminal_type == 'monitor') and pio_mon_win or pio_cli_win
--   local other_win = (terminal_type == 'monitor') and pio_cli_win or pio_mon_win
--   local target_buf = (terminal_type == 'monitor') and pio_mon_buf or pio_cli_buf
--
--   -- 2. MUTUAL EXCLUSION: If the other terminal panel window is visible, hide it first
--   if other_win and vim.api.nvim_win_is_valid(other_win) then
--     vim.api.nvim_win_close(other_win, true)
--     if terminal_type == 'monitor' then
--       pio_cli_win = nil
--     else
--       pio_mon_win = nil
--     end
--   end
--
--   -- 3. TOGGLE ACTION: If our target window is already open, close it and restore layout
--   if target_win and vim.api.nvim_win_is_valid(target_win) then
--     HideTerminalWindow(terminal_type)
--     return
--   end
--
--   -- 4. PROCESS PERSISTENCE: Pure native unlisted scratch buffer generation
--   if not target_buf or not vim.api.nvim_buf_is_valid(target_buf) then
--     target_buf = vim.api.nvim_create_buf(false, true) -- Unlisted scratch buffer
--     if terminal_type == 'monitor' then
--       pio_mon_buf = target_buf
--     else
--       pio_cli_buf = target_buf
--     end
--
--     -- Determine target windows platform shell engine cleanly
--     local target_shell = vim.o.shell
--     if vim.fn.has('win32') == 1 then
--       target_shell = 'powershell.exe'
--     end
--
--     -- Run the shell cleanly. This sets 'buftype' to 'terminal' natively, fixing typing bugs!
--     vim.api.nvim_buf_call(target_buf, function()
--       vim.fn.termopen(target_shell)
--     end)
--   end
--
--   -- 5. ABSOLUTE GLOBAL LAYOUT GEOMETRY:
--   -- We query the total screen rows and columns to draw a precise full-width canvas
--   local screen_width = vim.o.columns
--   local screen_lines = vim.o.lines
--   local cmdheight = vim.o.cmdheight or 1
--   local target_height = math.ceil(screen_lines * 0.28)
--
--   -- 6. PREMIUM RESIZE INTERCEPTOR:
--   -- Before rendering the overlay, we shrink the user's active code file window height.
--   -- This forces their text workspace to shift upward, so the terminal NEVER blocks any text rows!
--   local active_win = vim.api.nvim_get_current_win()
--   if not saved_code_height and vim.bo[vim.api.nvim_get_current_buf()].buftype == '' then
--     saved_code_win = active_win
--     saved_code_height = vim.api.nvim_win_get_height(active_win)
--
--     -- Shrink the text window out of the terminal's boundary box area
--     pcall(vim.api.nvim_win_set_height, active_win, saved_code_height - target_height)
--   end
--
--   local win_opts = {
--     relative = 'editor', -- Detaches completely from Neovim's standard column split tree
--     style = 'minimal', -- Disables borders, gutters, and layout adjustments
--     focusable = true, -- Keeps keyboard interaction and typing focus active
--     width = screen_width,
--     height = target_height,
--     row = screen_lines - target_height - cmdheight - 1, -- Pins perfectly above the command bar
--     col = 0, -- Spans across 100% of the screen from left to right edge
--   }
--
--   -- 7. RENDER THE GLOBAL PERSISTENT PANE
--   local new_win = vim.api.nvim_open_win(target_buf, true, win_opts)
--   if terminal_type == 'monitor' then
--     pio_mon_win = new_win
--   else
--     pio_cli_win = new_win
--   end
--
--   -- 8. CLEAN SYSTEM INSTANCE DECORATIONS
--   vim.cmd('setlocal nonumber norelativenumber signcolumn=no')
--   vim.api.nvim_set_option_value('winfixheight', true, { scope = 'local', win = new_win })
--
--   -- 9. VISUAL WINBAR DECORATION INTEGRATION
--   local hl = { bg = '#80a3d4', fg = '#000000' }
--   vim.api.nvim_set_hl(0, 'MyWinBar', { bg = hl.bg, fg = hl.fg })
--   local winBartitle = '%#MyWinBar# ' .. title .. ' [Press ;; to Switch | Press q to hide]%*'
--   vim.api.nvim_set_option_value('winbar', winBartitle, { scope = 'local', win = new_win })
--
--   -----------------------------------------------------------------------------
--   -- LOCAL MAPS (Scoped strictly to this terminal buffer layer instance)
--   -----------------------------------------------------------------------------
--   vim.keymap.set('t', '<Esc>', [[<C-\><C-n>]], { buffer = target_buf })
--   vim.keymap.set('n', 'q', function()
--     HideTerminalWindow(terminal_type)
--   end, { buffer = target_buf })
--
--   -- CRASH-FREE UPWARD NAVIGATION KEYMAP
--   vim.keymap.set({ 'n', 't' }, '<C-k>', function()
--     if vim.api.nvim_get_mode().mode == 't' then
--       local esc = vim.api.nvim_replace_termcodes([[<C-\><C-n>]], true, true, true)
--       vim.api.nvim_feedkeys(esc, 'n', false)
--     end
--     vim.schedule(function()
--       if saved_code_win and vim.api.nvim_win_is_valid(saved_code_win) then
--         vim.api.nvim_set_current_win(saved_code_win)
--       else
--         vim.cmd('wincmd k')
--       end
--     end)
--   end, { buffer = target_buf, silent = true })
--
--   -- DOUBLE SEMI-COLON CROSS SWITCHER LOGIC
--   vim.keymap.set({ 'n', 't' }, ';;', function()
--     if vim.api.nvim_get_mode().mode == 't' then
--       local esc = vim.api.nvim_replace_termcodes([[<C-\><C-n>]], true, true, true)
--       vim.api.nvim_feedkeys(esc, 'n', false)
--     end
--
--     local next_type = (terminal_type == 'monitor') and 'cli' or 'monitor'
--     vim.schedule(function()
--       M.ToggleTerminal('', next_type)
--     end)
--   end, { buffer = target_buf, silent = true, desc = 'Switch between PlatformIO terminals' })
--
--   -----------------------------------------------------------------------------
--   -- GLOBAL NAVIGATION & RECALL SHORTCUTS
--   -----------------------------------------------------------------------------
--   vim.keymap.set('n', '<C-h>', '<C-w>h')
--   vim.keymap.set('n', '<C-l>', '<C-w>l')
--
--   -- GLOBAL INTERCEPT DOWNWARD MOVEMENT HOOK:
--   -- Focuses your cursor straight down into your active terminal pane natively
--   vim.keymap.set('n', '<C-j>', function()
--     local cur_win = (terminal_type == 'monitor') and pio_mon_win or pio_cli_win
--     if cur_win and vim.api.nvim_win_is_valid(cur_win) then
--       vim.api.nvim_set_current_win(cur_win)
--       vim.cmd('startinsert')
--     else
--       vim.cmd('wincmd j')
--     end
--   end, { silent = true })
--
--   if terminal_type == 'monitor' then
--     vim.keymap.set('n', [[<leader>\gm]], function()
--       M.ToggleTerminal('', 'monitor')
--     end, { silent = true })
--   else
--     vim.keymap.set('n', [[<leader>\t]], function()
--       M.ToggleTerminal('', 'cli')
--     end, { silent = true })
--   end
--   -----------------------------------------------------------------------------
--
--   -- Automatically run passed command strings via your platformio job channels
--   if command and command ~= '' then
--     local job_id = vim.b[target_buf].terminal_job_id
--     if job_id then
--       vim.fn.chansend(job_id, command .. (vim.fn.has('win32') == 1 and '\r\n' or '\n'))
--     end
--   end
--
--   vim.cmd('startinsert')
-- end
--
-- return M
-- -- local M = {}
-- --
-- -- -- Memory slots to preserve running terminal process background buffers
-- -- local pio_cli_buf = nil
-- -- local pio_mon_buf = nil
-- --
-- -- -- Memory trackers for the active window IDs
-- -- local pio_cli_win = nil
-- -- local pio_mon_win = nil
-- --
-- -- ----------------------------------------------------------------------------------------
-- -- -- INFO: Safe Window Closure Logic (Tied to pressing 'q' inside normal mode)
-- -- local function HideTerminalWindow(terminal_type)
-- --   local target_win = (terminal_type == 'monitor') and pio_mon_win or pio_cli_win
-- --   if target_win and vim.api.nvim_win_is_valid(target_win) then
-- --     vim.api.nvim_win_close(target_win, true)
-- --   end
-- --   if terminal_type == 'monitor' then
-- --     pio_mon_win = nil
-- --   else
-- --     pio_cli_win = nil
-- --   end
-- -- end
-- --
-- -- ----------------------------------------------------------------------------------------
-- -- -- INFO: Core Layout Spawner (Buffer-Relative Overlay Framework)
-- -- function M.ToggleTerminal(command, terminal_type)
-- --   -- 1. Enforce strict title header assignments immediately at the top
-- --   local title = ''
-- --   if terminal_type == 'monitor' or (command and string.find(command, ' monitor')) then
-- --     title = 'Pio Monitor'
-- --     terminal_type = 'monitor'
-- --   else
-- --     title = 'Pio CLI>'
-- --     terminal_type = 'cli'
-- --   end
-- --
-- --   local target_win = (terminal_type == 'monitor') and pio_mon_win or pio_cli_win
-- --   local other_win = (terminal_type == 'monitor') and pio_cli_win or pio_mon_win
-- --   local target_buf = (terminal_type == 'monitor') and pio_mon_buf or pio_cli_buf
-- --
-- --   -- 2. MUTUAL EXCLUSION: If the other terminal panel window is visible, hide it first
-- --   if other_win and vim.api.nvim_win_is_valid(other_win) then
-- --     vim.api.nvim_win_close(other_win, true)
-- --     if terminal_type == 'monitor' then
-- --       pio_cli_win = nil
-- --     else
-- --       pio_mon_win = nil
-- --     end
-- --   end
-- --
-- --   -- 3. TOGGLE ACTION: If our target window is already open, close it
-- --   if target_win and vim.api.nvim_win_is_valid(target_win) then
-- --     vim.api.nvim_win_close(target_win, true)
-- --     if terminal_type == 'monitor' then
-- --       pio_mon_win = nil
-- --     else
-- --       pio_cli_win = nil
-- --     end
-- --     return
-- --   end
-- --
-- --   -- 4. PROCESS PERSISTENCE: Pure native unlisted scratch buffer generation
-- --   if not target_buf or not vim.api.nvim_buf_is_valid(target_buf) then
-- --     target_buf = vim.api.nvim_create_buf(false, true) -- Unlisted scratch buffer
-- --     if terminal_type == 'monitor' then
-- --       pio_mon_buf = target_buf
-- --     else
-- --       pio_cli_buf = target_buf
-- --     end
-- --
-- --     -- Determine target windows platform shell engine cleanly
-- --     local target_shell = vim.o.shell
-- --     if vim.fn.has('win32') == 1 then
-- --       target_shell = 'powershell.exe'
-- --     end
-- --
-- --     -- Run the shell cleanly. This sets 'buftype' to 'terminal' natively, fixing typing bugs!
-- --     vim.api.nvim_buf_call(target_buf, function()
-- --       vim.fn.termopen(target_shell)
-- --     end)
-- --   end
-- --
-- --   -- 5. THE BUFFER-RELATIVE LAYOUT FIX:
-- --   -- We anchor the float directly to the user's active file pane window handle (win = parent_file_win).
-- --   -- This makes your terminal completely immune to being smashed or squeezed by Aerial or Neo-tree!
-- --   local parent_file_win = vim.api.nvim_get_current_win()
-- --   local file_win_width = vim.api.nvim_win_get_width(parent_file_win)
-- --   local file_win_height = vim.api.nvim_win_get_height(parent_file_win)
-- --
-- --   local target_height = math.ceil(file_win_height * 0.32)
-- --
-- --   local win_opts = {
-- --     relative = 'win', -- HARD-LOCKS TO THE FILE WINDOW ONLY: Bypasses monitor grid completely
-- --     win = parent_file_win, -- Binds the coordinate system to their current text document pane
-- --     style = 'minimal', -- Disables border and padding overheads
-- --     focusable = true, -- Keeps keyboard layout paths fully operational
-- --     width = file_win_width, -- Stretches exactly to the margins of their code file pane
-- --     height = target_height,
-- --     row = file_win_height - target_height, -- Clamps precisely to the bottom of the file view
-- --     col = 0, -- Starts flush with the left edge of their text
-- --   }
-- --
-- --   -- 6. RENDER THE SECURE горизонтальный PANEL OVERLAY
-- --   local new_win = vim.api.nvim_open_win(target_buf, true, win_opts)
-- --   if terminal_type == 'monitor' then
-- --     pio_mon_win = new_win
-- --   else
-- --     pio_cli_win = new_win
-- --   end
-- --
-- --   -- 7. CLEAN SYSTEM OPTIONS DECORATIONS
-- --   vim.cmd('setlocal nonumber norelativenumber signcolumn=no')
-- --   vim.api.nvim_set_option_value('winfixheight', true, { scope = 'local', win = new_win })
-- --
-- --   -- 8. VISUAL CUSTOM WINBAR STYLING
-- --   local hl = { bg = '#80a3d4', fg = '#000000' }
-- --   vim.api.nvim_set_hl(0, 'MyWinBar', { bg = hl.bg, fg = hl.fg })
-- --   local winBartitle = '%#MyWinBar# ' .. title .. ' [Press ;; to Switch | Press q to hide]%*'
-- --   vim.api.nvim_set_option_value('winbar', winBartitle, { scope = 'local', win = new_win })
-- --
-- --   -----------------------------------------------------------------------------
-- --   -- LOCAL MAPS (Scoped strictly to this terminal buffer layer instance)
-- --   -----------------------------------------------------------------------------
-- --   vim.keymap.set('t', '<Esc>', [[<C-\><C-n>]], { buffer = target_buf })
-- --   vim.keymap.set('n', 'q', function()
-- --     HideTerminalWindow(terminal_type)
-- --   end, { buffer = target_buf })
-- --
-- --   -- CRASH-FREE UPWARD NAVIGATION KEYMAP
-- --   vim.keymap.set({ 'n', 't' }, '<C-k>', function()
-- --     if vim.api.nvim_get_mode().mode == 't' then
-- --       local esc = vim.api.nvim_replace_termcodes([[<C-\><C-n>]], true, true, true)
-- --       vim.api.nvim_feedkeys(esc, 'n', false)
-- --     end
-- --     vim.schedule(function()
-- --       if parent_file_win and vim.api.nvim_win_is_valid(parent_file_win) then
-- --         vim.api.nvim_set_current_win(parent_file_win)
-- --       end
-- --     end)
-- --   end, { buffer = target_buf, silent = true })
-- --
-- --   -- DOUBLE SEMI-COLON CROSS SWITCHER LOGIC
-- --   vim.keymap.set({ 'n', 't' }, ';;', function()
-- --     if vim.api.nvim_get_mode().mode == 't' then
-- --       local esc = vim.api.nvim_replace_termcodes([[<C-\><C-n>]], true, true, true)
-- --       vim.api.nvim_feedkeys(esc, 'n', false)
-- --     end
-- --
-- --     local next_type = (terminal_type == 'monitor') and 'cli' or 'monitor'
-- --     vim.schedule(function()
-- --       M.ToggleTerminal('', next_type)
-- --     end)
-- --   end, { buffer = target_buf, silent = true, desc = 'Switch between PlatformIO terminals' })
-- --
-- --   -----------------------------------------------------------------------------
-- --   -- GLOBAL NAVIGATION & RECALL SHORTCUTS
-- --   -----------------------------------------------------------------------------
-- --   vim.keymap.set('n', '<C-h>', '<C-w>h')
-- --   vim.keymap.set('n', '<C-l>', '<C-w>l')
-- --
-- --   -- GLOBAL INTERCEPT DOWNWARD MOVEMENT HOOK:
-- --   -- Focuses your cursor straight down into your active terminal pane natively
-- --   vim.keymap.set('n', '<C-j>', function()
-- --     if new_win and vim.api.nvim_win_is_valid(new_win) then
-- --       vim.api.nvim_set_current_win(new_win)
-- --       vim.cmd('startinsert')
-- --     else
-- --       vim.cmd('wincmd j')
-- --     end
-- --   end, { silent = true })
-- --
-- --   if terminal_type == 'monitor' then
-- --     vim.keymap.set('n', [[<leader>\gm]], function()
-- --       M.ToggleTerminal('', 'monitor')
-- --     end, { silent = true })
-- --   else
-- --     vim.keymap.set('n', [[<leader>\t]], function()
-- --       M.ToggleTerminal('', 'cli')
-- --     end, { silent = true })
-- --   end
-- --   -----------------------------------------------------------------------------
-- --
-- --   -- Automatically run passed command strings via your platformio job channels
-- --   if command and command ~= '' then
-- --     local job_id = vim.b[target_buf].terminal_job_id
-- --     if job_id then
-- --       vim.fn.chansend(job_id, command .. (vim.fn.has('win32') == 1 and '\r\n' or '\n'))
-- --     end
-- --   end
-- --
-- --   vim.cmd('startinsert')
-- -- end
-- --
-- -- return M
