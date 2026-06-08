local M = {}

-- Memory tracking slots for running background shell process IDs
local pio_cli_job = nil
local pio_mon_job = nil

-- Caches to hold the last visible line output from the streams
local pio_cli_last_line = 'No active processes running.'
local pio_mon_last_line = 'No active device trace logs.'

-- Toggle tracking flags
local is_panel_open = false
local active_view = 'cli'

----------------------------------------------------------------------------------------
-- INFO: Core Layout Generator (Global Statusline Winbar Panel Engine)
function M.ToggleTerminal(command, terminal_type)
  -- 1. Normalize variables and titles right at the top
  if terminal_type == 'monitor' or (command and string.find(command, ' monitor')) then
    terminal_type = 'monitor'
    active_view = 'monitor'
  else
    terminal_type = 'cli'
    active_view = 'cli'
  end

  -- 2. TOGGLE ACTION: If the panel is already active, hide it and clear the status row
  if is_panel_open and command == '' then
    vim.o.statusline = '' -- Restore native statusline
    is_panel_open = false
    return
  end

  is_panel_open = true

  -- 3. PROCESS BACKGROUND SPARK: Spawn the shell thread if it doesn't exist yet
  local current_job = (terminal_type == 'monitor') and pio_mon_job or pio_cli_job

  if not current_job then
    local target_shell = vim.o.shell
    if vim.fn.has('win32') == 1 then
      target_shell = 'powershell.exe'
    end

    local job_id = vim.fn.jobstart(target_shell, {
      term = false, -- Headless background job stream
      on_stdout = function(_, data)
        if data and #data > 0 then
          -- Grab the very last string line emitted by the PlatformIO process
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

          -- Automatically force an interface redraw to update the panel text row live
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
    return '%#MyWinBar#' .. title .. '%* ' .. display_text .. ' %=' .. '[Press ;; to Swap | Toggle off via shortcut]'
  end

  -- Mount the layout function to Neovim's global environment
  local hl = { bg = '#80a3d4', fg = '#000000' }
  vim.api.nvim_set_hl(0, 'MyWinBar', { bg = hl.bg, fg = hl.fg })

  _G.PioGlobalConsolePanel = UpdateGlobalPanel
  vim.o.statusline = '%{%v:lua.PioGlobalConsolePanel()%}'

  -----------------------------------------------------------------------------
  -- GLOBAL NAVIGATION & RECALL SHORTCUT VECTOR OVERRIDES
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
      vim.api.nvim_chan_send(active_chan, command .. '\n')
    end
  end
end

return M

-- local M = {}
--
-- -- Persistent background storage buffers for running shell processes
-- local pio_cli_buf = nil
-- local pio_mon_buf = nil
--
-- -- Display window tracking handles
-- local pio_cli_win = nil
-- local pio_mon_win = nil
--
-- ----------------------------------------------------------------------------------------
-- -- INFO: Safe Window Closure Logic (Tied to pressing 'q' inside normal mode)
-- local function HideTerminalWindow(terminal_type)
--   local win_id = (terminal_type == 'monitor') and pio_mon_win or pio_cli_win
--   if win_id and vim.api.nvim_win_is_valid(win_id) then
--     vim.api.nvim_win_close(win_id, true)
--   end
--   if terminal_type == 'monitor' then
--     pio_mon_win = nil
--   else
--     pio_cli_win = nil
--   end
-- end
--
-- ----------------------------------------------------------------------------------------
-- -- INFO: Core Layout Spawner (Global Canvas Layer Architecture)
-- function M.ToggleTerminal(command, terminal_type)
--   -- 1. Normalize variables and titles right at the top
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
--   -- 2. MUTUAL EXCLUSION: If the other terminal is open, close its window layer first
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
--   -- 4. THE CORRECT WINDOWS POWERSHELL PIPELINE:
--   -- Generates a native unlisted terminal channel block natively without E474 errors
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
--     -- FIXED: We launch the shell inside a clean nvim_buf_call wrapper using termopen.
--     -- This sets the 'buftype' to 'terminal' automatically, fixing your typing bugs!
--     vim.api.nvim_buf_call(target_buf, function()
--       vim.fn.termopen(target_shell)
--     end)
--
--     -- CLEAN HEADER FILTER: Cleans up initial PlatformIO startup diagnostics menu text rows
--     local pio_group = vim.api.nvim_create_augroup('PioCleaner_' .. target_buf, { clear = true })
--     vim.api.nvim_create_autocmd({ 'TextChanged', 'TextChangedI' }, {
--       group = pio_group,
--       buffer = target_buf,
--       callback = function()
--         vim.schedule(function()
--           if vim.api.nvim_buf_is_valid(target_buf) then
--             local lines = vim.api.nvim_buf_get_lines(target_buf, 0, -1, false)
--             for i, line in ipairs(lines) do
--               local is_garbage = line:find('|| Processing')
--                 or line:find('--- forcing')
--                 or line:find('--- Terminal')
--                 or line:find('--- Available filters')
--                 or line:find('--- More details')
--                 or line:find('--- Quit:')
--               if is_garbage then
--                 vim.api.nvim_buf_set_lines(target_buf, i - 1, i, false, { '' })
--               end
--             end
--           end
--         end)
--       end,
--     })
--   end
--
--   -- 5. ABSOLUTE GEOMETRIC GRID CONFIGURATION:
--   -- Locks position securely on a separate overlay layer to prevent vertical pillar splitting
--   local target_height = math.ceil(vim.o.lines * 0.28)
--   local cmdheight = vim.o.cmdheight or 1
--
--   local win_opts = {
--     relative = 'editor',
--     style = 'minimal',
--     focusable = true,
--     width = vim.o.columns,
--     height = target_height,
--     row = vim.o.lines - target_height - cmdheight - 1,
--     col = 0,
--   }
--
--   -- 6. DRAW THE RECTANGLE VIEWPORT OVERLAY
--   local new_win = vim.api.nvim_open_win(target_buf, true, win_opts)
--   if terminal_type == 'monitor' then
--     pio_mon_win = new_win
--   else
--     pio_cli_win = new_win
--   end
--
--   -- 7. PANE OPTION DECORATIONS
--   vim.cmd('setlocal nonumber norelativenumber signcolumn=no')
--   vim.api.nvim_set_option_value('winfixheight', true, { scope = 'local', win = new_win })
--
--   -- 8. VISUAL WINBAR DECORATIONS
--   local hl = { bg = '#80a3d4', fg = '#000000' }
--   vim.api.nvim_set_hl(0, 'MyWinBar', { bg = hl.bg, fg = hl.fg })
--   local winBartitle = '%#MyWinBar# ' .. title .. ' [Press ;; to Switch | Press q to hide]%*'
--   vim.api.nvim_set_option_value('winbar', winBartitle, { scope = 'local', win = new_win })
--
--   -----------------------------------------------------------------------------
--   -- LOCAL MAPS (Scoped strictly to this terminal buffer)
--   -----------------------------------------------------------------------------
--   vim.keymap.set('t', '<Esc>', [[<C-\><C-n>]], { buffer = target_buf })
--   vim.keymap.set('n', 'q', function()
--     HideTerminalWindow(terminal_type)
--   end, { buffer = target_buf })
--
--   -- CRASH-FREE UPWARD NAVIGATION SHORTCUT
--   vim.keymap.set({ 'n', 't' }, '<C-k>', function()
--     if vim.api.nvim_get_mode().mode == 't' then
--       local esc = vim.api.nvim_replace_termcodes([[<C-\><C-n>]], true, true, true)
--       vim.api.nvim_feedkeys(esc, 'n', false)
--     end
--     vim.schedule(function()
--       vim.cmd('wincmd k')
--     end)
--   end, { buffer = target_buf, silent = true })
--
--   -- DUAL PANEL HOME ROW CROSS SWITCHER (;;)
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
--   -- GLOBAL SHORTCUT RE-REGISTRATIONS (Preserved across context switches)
--   -----------------------------------------------------------------------------
--   vim.keymap.set('n', '<C-h>', '<C-w>h')
--   vim.keymap.set('n', '<C-l>', '<C-w>l')
--
--   -- GLOBAL INTERCEPT DOWNWARD MOVEMENT KEY:
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
--   -- Pass PlatformIO command strings directly through the modern background channel
--   if command and command ~= '' then
--     local chan_id = vim.b[target_buf].terminal_job_id
--     if chan_id then
--       -- Uses standard chansend to pipe the execution strings directly to the shell process
--       vim.fn.chansend(chan_id, command .. '\r\n')
--     end
--   end
--
--   vim.cmd('startinsert')
-- end
--
-- return M
