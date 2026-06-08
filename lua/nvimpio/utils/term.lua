local M = {}

-- Memory trackers for your two persistent plugin terminal buffers
local pio_cli_buf = nil
local pio_mon_buf = nil

-- Keeps track of the total window count to detect sidebar layout adjustments dynamically
local last_layout_win_count = 0

----------------------------------------------------------------------------------------
-- INFO: Safe terminal exit routine (Tied to pressing 'q' inside normal mode)
local function SafeCloseTerminal(buf_id)
  if buf_id and vim.api.nvim_buf_is_valid(buf_id) then
    local win_id = vim.fn.bufwinid(buf_id)
    if win_id and win_id ~= -1 and vim.api.nvim_win_is_valid(win_id) then
      vim.api.nvim_win_close(win_id, true)
      -- Force standard workspace windows to balance their layout spacing evenly
      vim.cmd('wincmd =')
    end
  end
end

----------------------------------------------------------------------------------------
-- INFO: Unified Full-Width Bottom Terminal Spawner (Dynamic Self-Healing Grid)
function M.ToggleTerminal(command, terminal_type)
  -- 1. Enforce strict title header assignments immediately at the top
  local title = ''
  if terminal_type == 'monitor' or (command and string.find(command, ' monitor')) then
    title = 'Pio Monitor'
    terminal_type = 'monitor'
  else
    title = 'Pio CLI>'
    terminal_type = 'cli'
  end

  -- Determine target buffer context arrays
  local target_buf = (terminal_type == 'monitor') and pio_mon_buf or pio_cli_buf
  local other_buf = (terminal_type == 'monitor') and pio_cli_buf or pio_mon_buf

  -- 2. MUTUAL EXCLUSION: If the opponent window is currently open, hide it first
  if other_buf and vim.api.nvim_buf_is_valid(other_buf) then
    local other_win = vim.fn.bufwinid(other_buf)
    if other_win and other_win ~= -1 and vim.api.nvim_win_is_valid(other_win) then
      vim.api.nvim_win_close(other_win, true)
    end
  end

  -- 3. TOGGLE ACTION: If our target terminal window is already open on screen, close it
  if target_buf and vim.api.nvim_buf_is_valid(target_buf) then
    local target_win = vim.fn.bufwinid(target_buf)
    if target_win and target_win ~= -1 and vim.api.nvim_win_is_valid(target_win) then
      vim.api.nvim_win_close(target_win, true)
      vim.cmd('wincmd =')
      return
    end
  end

  -- 4. FIXED LAYOUT MECHANIC: Initialize a horizontal split pane at the bottom edge.
  -- 'botright split' tells Neovim to cut the layout tree at the root screen layer.
  local target_height = math.ceil(vim.o.lines * 0.28)
  vim.cmd('botright ' .. target_height .. 'split')
  local new_win = vim.api.nvim_get_current_win()

  -- 5. REUSE RUNNING PROCESS BUFFER OR GENERATE A FRESH NATIVE SESSION
  if target_buf and vim.api.nvim_buf_is_valid(target_buf) then
    vim.api.nvim_win_set_buf(new_win, target_buf)
  else
    -- Determine target windows platform shell engine cleanly
    local target_shell = vim.o.shell
    if vim.fn.has('win32') == 1 then
      target_shell = 'powershell.exe'
    end

    -- Uses a native non-deprecated terminal invocation call on a clean scratch buffer
    vim.cmd('terminal ' .. target_shell)
    target_buf = vim.api.nvim_get_current_buf()
    if terminal_type == 'monitor' then
      pio_mon_buf = target_buf
    else
      pio_cli_buf = target_buf
    end
  end

  -- 6. HARD-LOCK WINDOW LAYOUT MARGINS
  vim.cmd('setlocal nonumber norelativenumber signcolumn=no')
  vim.api.nvim_set_option_value('winfixheight', true, { scope = 'local', win = new_win })

  -- Record initial layout state to baseline the window balance tracking checks
  last_layout_win_count = #vim.api.nvim_list_wins()

  -- 7. THE SELF-HEALING GRID PROTECTION ENGINE (No Hardcoding!)
  -- This autocmd watches window openings globally. If the window count changes, it means
  -- an unknown sidebar (Aerial, Neo-tree, symbols-outline, etc.) was loaded.
  -- It runs a single layout correction pass, then IMMEDIATELY disconnects itself.
  -- This architecture guarantees it can NEVER enter an infinite loop or crush your text windows!
  local platformio_group = vim.api.nvim_create_augroup('PioLayoutGuard_' .. target_buf, { clear = true })
  vim.api.nvim_create_autocmd({ 'WinNew', 'BufWinEnter' }, {
    group = platformio_group,
    callback = function()
      local current_win_count = #vim.api.nvim_list_wins()

      -- If a new sidebar has generated a vertical screen partition column...
      if current_win_count ~= last_layout_win_count then
        local term_win = vim.fn.bufwinid(target_buf)
        if term_win and term_win ~= -1 and vim.api.nvim_win_is_valid(term_win) then
          -- Temporarily clear the group to prevent recursion loops dead in their tracks
          vim.api.nvim_clear_autocmds({ group = 'PioLayoutGuard_' .. target_buf })

          vim.schedule(function()
            if vim.api.nvim_win_is_valid(term_win) then
              local cur_win = vim.api.nvim_get_current_win()

              -- Jump focus back down, force layout flatness, and restore standard dimensions
              vim.api.nvim_set_current_win(term_win)
              vim.cmd('wincmd J')
              vim.cmd('wincmd =')

              if cur_win and vim.api.nvim_win_is_valid(cur_win) then
                vim.api.nvim_set_current_win(cur_win)
              end

              -- Re-register this self-healing layout guide for the next sidebar transition action
              last_layout_win_count = #vim.api.nvim_list_wins()
              M.ToggleTerminal(command, terminal_type)
            end
          end)
        end
      end
    end,
  })

  -- 8. VISUAL WINBAR DECORATION INTEGRATION
  local hl = { bg = '#80a3d4', fg = '#000000' }
  vim.api.nvim_set_hl(0, 'MyWinBar', { bg = hl.bg, fg = hl.fg })
  local winBartitle = '%#MyWinBar# ' .. title .. ' [Press ;; to Switch | Press q to hide]%*'
  vim.api.nvim_set_option_value('winbar', winBartitle, { scope = 'local', win = new_win })

  -----------------------------------------------------------------------------
  -- LOCAL MAPS (Scoped strictly to this terminal buffer layer instance)
  -----------------------------------------------------------------------------
  vim.keymap.set('t', '<Esc>', [[<C-\><C-n>]], { buffer = target_buf })
  vim.keymap.set('n', 'q', function()
    SafeCloseTerminal(target_buf)
  end, { buffer = target_buf })

  -- Escape path out of the terminal pane back UP to code files without crashes
  vim.keymap.set({ 'n', 't' }, '<C-k>', function()
    if vim.api.nvim_get_mode().mode == 't' then
      local esc = vim.api.nvim_replace_termcodes([[<C-\><C-n>]], true, true, true)
      vim.api.nvim_feedkeys(esc, 'n', false)
    end
    vim.schedule(function()
      vim.cmd('wincmd k')
    end)
  end, { buffer = target_buf, silent = true })

  -- HOME-ROW CROSS SWITCHER: Double tap semi-colon (;;) to swap panels instantly!
  vim.keymap.set({ 'n', 't' }, ';;', function()
    if vim.api.nvim_get_mode().mode == 't' then
      local esc = vim.api.nvim_replace_termcodes([[<C-\><C-n>]], true, true, true)
      vim.api.nvim_feedkeys(esc, 'n', false)
    end

    local next_type = (terminal_type == 'monitor') and 'cli' or 'monitor'
    vim.schedule(function()
      M.ToggleTerminal('', next_type)
    end)
  end, { buffer = target_buf, silent = true, desc = 'Switch between PlatformIO terminals' })

  -----------------------------------------------------------------------------
  -- GLOBAL NAVIGATION & RECALL SHORTCUTS
  -----------------------------------------------------------------------------
  vim.keymap.set('n', '<C-h>', '<C-w>h')
  vim.keymap.set('n', '<C-l>', '<C-w>l')

  -- Intercepts Ctrl-J everywhere and drops cursor directly into this active terminal split row
  vim.keymap.set('n', '<C-j>', function()
    if new_win and vim.api.nvim_win_is_valid(new_win) then
      vim.api.nvim_set_current_win(new_win)
      vim.cmd('startinsert')
    else
      vim.cmd('wincmd j')
    end
  end, { silent = true })

  if terminal_type == 'monitor' then
    vim.keymap.set('n', [[<leader>\gm]], function()
      M.ToggleTerminal('', 'monitor')
    end, { desc = 'Toggle PlatformIO Monitor Panel', silent = true })
  else
    vim.keymap.set('n', [[<leader>\t]], function()
      M.ToggleTerminal('', 'cli')
    end, { desc = 'Toggle PlatformIO CLI Panel', silent = true })
  end
  -----------------------------------------------------------------------------

  -- Clean out layout pass handlers when terminal buffer exits
  vim.api.nvim_create_autocmd('BufUnload', {
    group = platformio_group,
    buffer = target_buf,
    callback = function()
      pcall(vim.api.nvim_clear_autocmds, { group = 'PioLayoutGuard_' .. target_buf })
    end,
  })

  -- Automatically run passed command strings via your platformio job channels
  if command and command ~= '' then
    local job_id = vim.b[target_buf].terminal_job_id
    if job_id then
      vim.fn.chansend(job_id, command .. (vim.fn.has('win32') == 1 and '\r\n' or '\n'))
    end
  end

  vim.cmd('startinsert')
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
