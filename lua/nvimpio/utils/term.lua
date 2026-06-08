local M = {}

-- Memory slots to preserve running terminal process background buffers
local pio_cli_buf = nil
local pio_mon_buf = nil

-- Memory trackers for the active window IDs
local pio_cli_win = nil
local pio_mon_win = nil
local last_active_editor_win = nil

----------------------------------------------------------------------------------------
-- 🛡️ NEUTRAL ENVIRONMENT FINDER: Safely escapes sidebars to eliminate column split bugs
local function find_valid_editor_window()
  local wins = vim.api.nvim_tabpage_list_wins(0)
  for _, win in ipairs(wins) do
    if vim.api.nvim_win_is_valid(win) and win ~= pio_cli_win and win ~= pio_mon_win then
      local buf = vim.api.nvim_win_get_buf(win)
      local ft = vim.api.nvim_get_option_value('filetype', { buf = buf })
      local bt = vim.api.nvim_get_option_value('buftype', { buf = buf })
      if ft ~= 'neo-tree' and ft ~= 'aerial' and bt ~= 'terminal' and bt ~= 'nofile' then
        return win
      end
    end
  end
  return nil
end

----------------------------------------------------------------------------------------
-- CLEAN EXIT LOGIC: Disarms protection shields and closes layout splits cleanly
local function HideTerminalWindow(terminal_type)
  local target_win = (terminal_type == 'monitor') and pio_mon_win or pio_cli_win
  if target_win and vim.api.nvim_win_is_valid(target_win) then
    vim.api.nvim_set_option_value('winfixbuf', false, { scope = 'local', win = target_win })
    vim.api.nvim_win_close(target_win, true)
  end
  if terminal_type == 'monitor' then
    pio_mon_win = nil
  else
    pio_cli_win = nil
  end

  if last_active_editor_win and vim.api.nvim_win_is_valid(last_active_editor_win) then
    vim.api.nvim_set_current_win(last_active_editor_win)
  end
end

----------------------------------------------------------------------------------------
-- CORE STRUCTURAL RUNNER (PRODUCTION GRADE COORD-FREE TOPOLOGY)
function M.ToggleTerminal(command, terminal_type)
  ------------------------------------------------------------------

  local group = vim.api.nvim_create_augroup('TerminalPositionLock', { clear = true })
  local settle_timer = nil
  local target_term_buf = nil -- Persists our unique terminal buffer reference in memory

  -- Helper: Safely finds any active window currently rendering our custom terminal buffer
  local function find_term_win()
    if not target_term_buf or not vim.api.nvim_buf_is_valid(target_term_buf) then
      return nil
    end
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      if vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) == target_term_buf then
        return win
      end
    end
    return nil
  end

  vim.api.nvim_create_autocmd({ 'WinNew', 'WinClosed', 'BufEnter' }, {
    group = group,
    pattern = '*',
    callback = function(args)
      -- 1. TRACKER LOGIC: Cache the unique nvimpio-terminal buffer id if we see it
      if vim.bo[args.buf].filetype == 'nvimpio-terminal' then
        target_term_buf = args.buf
      end

      -- If we don't have an active terminal buffer tracked yet, skip layout manipulation
      if not target_term_buf or not vim.api.nvim_buf_is_valid(target_term_buf) then
        return
      end

      -- 2. INSTANT HIDE: If the terminal window is open right now, close its window visibility instantly
      -- This hides it gracefully before Neo-tree or new splits mess up the layout geometries
      local term_win = find_term_win()
      if term_win then
        -- Pass true to force close window layout frames without deleting the background buffer data!
        pcall(vim.api.nvim_win_close, term_win, true)
      end

      -- 3. DEBOUNCED ENGINE: Cancel any existing timers so rapid successive events don't pile up
      if settle_timer then
        pcall(function()
          settle_timer:stop()
          settle_timer:close()
        end)
        settle_timer = nil
      end

      -- 4. WAIT FOR EVERYTHING TO SETTLE (Non-blocking 1-Second Defer Loop)
      settle_timer = vim.uv.new_timer()
      settle_timer:start(
        1000,
        0,
        vim.schedule_wrap(function()
          if settle_timer then
            settle_timer:stop()
            settle_timer:close()
            settle_timer = nil
          end

          -- Verify that the underlying terminal buffer wasn't manually deleted during the delay
          if not target_term_buf or not vim.api.nvim_buf_is_valid(target_term_buf) then
            return
          end

          -- Double-check that it didn't accidentally pop back open during the wait window
          if find_term_win() then
            return
          end

          -- 5. SMOOTH RE-APPEAR: Re-render the terminal buffer perfectly underneath the workspace layout
          local current_win = vim.api.nvim_get_current_win()

          pcall(function()
            -- Open a clean split spanning the complete bottom margin profile of Neovim
            vim.cmd('botright split')
            local new_win = vim.api.nvim_get_current_win()

            -- Re-link our persistent running terminal execution channel back into view!
            vim.api.nvim_win_set_buf(new_win, target_term_buf)
            vim.cmd('resize 15')

            -- Force terminal buffer configurations to stay synced cleanly
            vim.wo[new_win].winfixheight = true

            -- Instantly place the user's cursor focus back into their active text coding split pane
            if vim.api.nvim_win_is_valid(current_win) and current_win ~= new_win then
              vim.api.nvim_set_current_win(current_win)
            end
          end)
        end)
      )
    end,
  })
  -- local group = vim.api.nvim_create_augroup('TerminalPositionLock', { clear = true })
  --
  -- -- A state flag to prevent the function from re-triggering itself during window jumps
  -- local is_adjusting_layout = false
  --
  -- vim.api.nvim_create_autocmd({ 'WinNew', 'WinLeave', 'BufEnter' }, {
  --   group = group,
  --   callback = function(args)
  --     local triggering_buf = args.buf
  --
  --     -- 1. CRITICAL RACE GUARD: Exit immediately if we are already in the middle of shifting windows
  --     if is_adjusting_layout then
  --       return
  --     end
  --
  --     -- 2. TARGETED FILETYPE GUARD: Validate that this is strictly an nvimpio terminal
  --     -- This ignores all generic system terminals, ToggleTerm panels, and code windows.
  --     if vim.bo[triggering_buf].filetype ~= 'nvimpio-terminal' then
  --       return
  --     end
  --
  --     -- 3. Safely schedule the position fix for this specific terminal profile
  --     vim.schedule(function()
  --       for _, win in ipairs(vim.api.nvim_list_wins()) do
  --         if vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) == triggering_buf then
  --           local current_win = vim.api.nvim_get_current_win()
  --
  --           -- Activate the layout shield lock right before shifting focus or moving tabs
  --           is_adjusting_layout = true
  --
  --           pcall(function()
  --             -- Jump in, force the custom panel to the absolute bottom row workspace alignment, and resize
  --             vim.api.nvim_set_current_win(win)
  --             vim.cmd('wincmd J')
  --             vim.cmd('resize 15')
  --
  --             -- Return focus seamlessly back to the user's active cursor row split pane
  --             if vim.api.nvim_win_is_valid(current_win) then
  --               vim.api.nvim_set_current_win(current_win)
  --             end
  --           end)
  --
  --           -- Release the layout state flag lock cleanly once the operation completes
  --           is_adjusting_layout = false
  --           break
  --         end
  --       end
  --     end)
  --   end,
  -- })
  -- local group = vim.api.nvim_create_augroup('TerminalPositionLock', { clear = true })
  --
  -- vim.api.nvim_create_autocmd({ 'WinNew', 'WinLeave', 'BufEnter' }, {
  --   group = group,
  --   callback = function(args) -- 'args' contains data about the event
  --     -- 1. Identify which buffer triggered the event
  --     local triggering_buf = args.buf
  --
  --     -- 2. Check if THAT specific buffer is a terminal
  --     if vim.bo[triggering_buf].buftype == 'terminal' then
  --       -- 3. Safely schedule the position fix for this specific terminal
  --       vim.schedule(function()
  --         -- Find which window is currently holding our target terminal buffer
  --         for _, win in ipairs(vim.api.nvim_list_wins()) do
  --           if vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) == triggering_buf then
  --             local current_win = vim.api.nvim_get_current_win()
  --
  --             -- Jump in, force it down, resize, and jump back
  --             vim.api.nvim_set_current_win(win)
  --             vim.cmd('wincmd J')
  --             vim.cmd('resize 15')
  --
  --             if vim.api.nvim_win_is_valid(current_win) then
  --               vim.api.nvim_set_current_win(current_win)
  --             end
  --
  --             break -- We found it and fixed it, stop looping
  --           end
  --         end
  --       end)
  --     end
  --   end,
  -- })
  ------------------------------------------------------------------
  local active_win = vim.api.nvim_get_current_win()
  if active_win ~= pio_cli_win and active_win ~= pio_mon_win then
    last_active_editor_win = active_win
  end

  local title = ''
  if terminal_type == 'monitor' or (command and string.find(command, ' monitor')) then
    title = 'Pio Monitor'
    terminal_type = 'monitor'
  else
    title = 'Pio CLI>'
    terminal_type = 'cli'
  end

  local target_win = (terminal_type == 'monitor') and pio_mon_win or pio_cli_win
  local other_win = (terminal_type == 'monitor') and pio_cli_win or pio_mon_win
  local target_buf = (terminal_type == 'monitor') and pio_mon_buf or pio_cli_buf

  -- 1. MUTUAL EXCLUSION: Close opposition split instantly
  if other_win and vim.api.nvim_win_is_valid(other_win) then
    vim.api.nvim_set_option_value('winfixbuf', false, { scope = 'local', win = other_win })
    vim.api.nvim_win_close(other_win, true)
    if terminal_type == 'monitor' then
      pio_cli_win = nil
    else
      pio_mon_win = nil
    end
  end

  -- 2. TOGGLE LOGIC: Close active pane if requested
  if target_win and vim.api.nvim_win_is_valid(target_win) then
    HideTerminalWindow(terminal_type)
    return
  end

  -- 3. INTERACTIVE PTY EMULATION ENGINE (DEPRECATION FREE)
  if not target_buf or not vim.api.nvim_buf_is_valid(target_buf) then
    target_buf = vim.api.nvim_create_buf(false, true)
    if terminal_type == 'monitor' then
      pio_mon_buf = target_buf
    else
      pio_cli_buf = target_buf
    end

    vim.api.nvim_set_option_value('filetype', 'nvimpio-terminal', { buf = target_buf })

    local target_shell = vim.o.shell
    if vim.fn.has('win32') == 1 then
      target_shell = 'powershell.exe'
    end

    vim.api.nvim_buf_call(target_buf, function()
      vim.fn.termopen(target_shell)
    end)
  end

  -- 4. 🥇 UNBREAKABLE HORIZONTAL BOTTOM STRUCTURAL ALIGNMENT
  -- Move focus to a normal file workspace buffer before triggering layouts
  local neutral_win = find_valid_editor_window()
  if neutral_win then
    vim.api.nvim_set_current_win(neutral_win)
  end

  local target_height = math.ceil(vim.o.lines * 0.28)

  -- Open a standard structural layout split
  vim.cmd('split')
  local new_win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(new_win, target_buf)

  -- 🔥 THE SHIELD: Rips the split container entirely out of vertical columns
  -- and flattens it horizontally across the absolute bottom row [Index].
  vim.cmd('wincmd J')
  vim.api.nvim_win_set_height(new_win, target_height)

  if terminal_type == 'monitor' then
    pio_mon_win = new_win
  else
    pio_cli_win = new_win
  end

  -- 5. WINDOW PANE DECORATIONS & PROTECTION SHIELDS
  vim.cmd('setlocal nonumber norelativenumber signcolumn=no')

  -- Lock row dimensions to secure height boundaries
  vim.api.nvim_set_option_value('winfixheight', true, { scope = 'local', win = new_win })

  -- 🛡️ KERNEL BUFFER LOCK: Tells Neovim file operations cannot replace or split this window space [Index].
  vim.api.nvim_set_option_value('winfixbuf', true, { scope = 'local', win = new_win })

  local hl = { bg = '#80a3d4', fg = '#000000' }
  vim.api.nvim_set_hl(0, 'MyWinBar', { bg = hl.bg, fg = hl.fg })
  local winBartitle = '%#MyWinBar# ' .. title .. ' [Press ;; to Switch | Press q to hide]%*'
  vim.api.nvim_set_option_value('winbar', winBartitle, { scope = 'local', win = new_win })

  -- 6. BUFFER SPECIFIC MAPS
  vim.keymap.set('t', '<Esc>', [[<C-\><C-n>]], { buffer = target_buf })
  vim.keymap.set('n', 'q', function()
    HideTerminalWindow(terminal_type)
  end, { buffer = target_buf })

  vim.keymap.set({ 'n', 't' }, '<C-k>', function()
    if vim.api.nvim_get_mode().mode == 't' then
      local esc = vim.api.nvim_replace_termcodes([[<C-\><C-n>]], true, true, true)
      vim.api.nvim_feedkeys(esc, 'n', false)
    end
    vim.schedule(function()
      local target = find_valid_editor_window() or last_active_editor_win
      if target and vim.api.nvim_win_is_valid(target) then
        vim.api.nvim_set_current_win(target)
      else
        vim.cmd('wincmd k')
      end
    end)
  end, { buffer = target_buf, silent = true })

  vim.keymap.set({ 'n', 't' }, ';;', function()
    if vim.api.nvim_get_mode().mode == 't' then
      local esc = vim.api.nvim_replace_termcodes([[<C-\><C-n>]], true, true, true)
      vim.api.nvim_feedkeys(esc, 'n', false)
    end
    local next_type = (terminal_type == 'monitor') and 'cli' or 'monitor'
    vim.schedule(function()
      M.ToggleTerminal('', next_type)
    end)
  end, { buffer = target_buf, silent = true })

  if command and command ~= '' then
    local job_id = vim.b[target_buf].terminal_job_id
    if job_id then
      vim.fn.chansend(job_id, command .. (vim.fn.has('win32') == 1 and '\r\n' or '\n'))
    end
  end

  vim.cmd('startinsert')
end

-----------------------------------------------------------------------------
-- GLOBAL NAVIGATION REGISTER
-----------------------------------------------------------------------------
vim.keymap.set('n', '<C-h>', '<C-w>h', { silent = true })
vim.keymap.set('n', '<C-l>', '<C-w>l', { silent = true })

vim.keymap.set('n', '<C-j>', function()
  if pio_cli_win and vim.api.nvim_win_is_valid(pio_cli_win) then
    vim.api.nvim_set_current_win(pio_cli_win)
    vim.cmd('startinsert')
  elseif pio_mon_win and vim.api.nvim_win_is_valid(pio_mon_win) then
    vim.api.nvim_set_current_win(pio_mon_win)
    vim.cmd('startinsert')
  else
    vim.cmd('wincmd j')
  end
end, { silent = true })

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
