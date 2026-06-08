local M = {}

-- Persistent background storage buffers for running shell processes
local pio_cli_buf = nil
local pio_mon_buf = nil

-- Display window tracking handles
local pio_cli_win = nil
local pio_mon_win = nil

-- Remembers where the user's main file tree and code splits live
local original_workspace_tab = nil
local pio_isolated_tab = nil

----------------------------------------------------------------------------------------
-- INFO: Safe Window Closure Logic (Tied to pressing 'q' inside normal mode)
local function HideTerminalWindow(terminal_type)
  local target_win = (terminal_type == 'monitor') and pio_mon_win or pio_cli_win
  if target_win and vim.api.nvim_win_is_valid(target_win) then
    vim.api.nvim_win_close(target_win, true)
  end
  if terminal_type == 'monitor' then
    pio_mon_win = nil
  else
    pio_cli_win = nil
  end

  -- Clean up and shut down the isolated tab page if both console panels are closed
  if pio_isolated_tab and vim.api.nvim_tabpage_is_valid(pio_isolated_tab) then
    local tab_wins = vim.api.nvim_tabpage_list_wins(pio_isolated_tab)
    if #tab_wins <= 1 then
      vim.cmd('tabclose')
      pio_isolated_tab = nil
      -- Return user focus safely back to their original workspace file tree
      if original_workspace_tab and vim.api.nvim_tabpage_is_valid(original_workspace_tab) then
        vim.api.nvim_set_current_tabpage(original_workspace_tab)
      end
    end
  end
end

----------------------------------------------------------------------------------------
-- INFO: Core Layout Spawner (Isolated Tabular Page Architecture)
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

  local target_win = (terminal_type == 'monitor') and pio_mon_win or pio_cli_win
  local other_win = (terminal_type == 'monitor') and pio_cli_win or pio_mon_win
  local target_buf = (terminal_type == 'monitor') and pio_mon_buf or pio_cli_buf

  -- 2. MUTUAL EXCLUSION: If the opponent window is visible, hide it first
  if other_win and vim.api.nvim_win_is_valid(other_win) then
    vim.api.nvim_win_close(other_win, true)
    if terminal_type == 'monitor' then
      pio_cli_win = nil
    else
      pio_mon_win = nil
    end
  end

  -- 3. TOGGLE ACTION: If our target window is already open, close it
  if target_win and vim.api.nvim_win_is_valid(target_win) then
    vim.api.nvim_win_close(target_win, true)
    if terminal_type == 'monitor' then
      pio_mon_win = nil
    else
      pio_cli_win = nil
    end

    -- Safe return to code view tab if closing the active console
    if original_workspace_tab and vim.api.nvim_tabpage_is_valid(original_workspace_tab) then
      vim.api.nvim_set_current_tabpage(original_workspace_tab)
    end
    return
  end

  -- 4. CACHE ORIGINAL WORKSPACE: Remember exactly where the file-tree cache is healthy
  local current_tab = vim.api.nvim_get_current_tabpage()
  if current_tab ~= pio_isolated_tab then
    original_workspace_tab = current_tab
  end

  -- 5. PROCESS PERSISTENCE: Pure native unlisted scratch buffer generation
  if not target_buf or not vim.api.nvim_buf_is_valid(target_buf) then
    target_buf = vim.api.nvim_create_buf(false, true) -- Unlisted scratch buffer
    if terminal_type == 'monitor' then
      pio_mon_buf = target_buf
    else
      pio_cli_buf = target_buf
    end

    -- Determine target windows platform shell engine cleanly
    local target_shell = vim.o.shell
    if vim.fn.has('win32') == 1 then
      target_shell = 'powershell.exe'
    end

    -- Run the shell cleanly. This sets 'buftype' to 'terminal' natively, fixing typing bugs!
    vim.api.nvim_buf_call(target_buf, function()
      vim.fn.termopen(target_shell)
    end)
  end

  -- 6. TABPAGE LAYOUT SEPARATION: Safely initialize or hop into our isolated display layer tab
  if pio_isolated_tab and vim.api.nvim_tabpage_is_valid(pio_isolated_tab) then
    vim.api.nvim_set_current_tabpage(pio_isolated_tab)
  else
    vim.cmd('tabnew')
    pio_isolated_tab = vim.api.nvim_get_current_tabpage()
  end

  -- Draw the full-screen width split row partition inside this isolated tab environment
  local target_height = math.ceil(vim.o.lines * 0.28)
  vim.cmd('botright ' .. target_height .. 'split')

  local new_win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(new_win, target_buf)
  if terminal_type == 'monitor' then
    pio_mon_win = new_win
  else
    pio_cli_win = new_win
  end

  -- 7. HARD-LOCK WINDOW SYSTEM FLAGS
  vim.cmd('setlocal nonumber norelativenumber signcolumn=no')
  vim.api.nvim_set_option_value('winfixheight', true, { scope = 'local', win = new_win })

  -- 8. VISUAL CUSTOM WINBAR STYLING
  local hl = { bg = '#80a3d4', fg = '#000000' }
  vim.api.nvim_set_hl(0, 'MyWinBar', { bg = hl.bg, fg = hl.fg })
  local winBartitle = '%#MyWinBar# ' .. title .. ' [Press ;; to Switch | Press q to hide]%*'
  vim.api.nvim_set_option_value('winbar', winBartitle, { scope = 'local', win = new_win })

  -----------------------------------------------------------------------------
  -- LOCAL MAPS (Scoped strictly to this terminal buffer layer instance)
  -----------------------------------------------------------------------------
  vim.keymap.set('t', '<Esc>', [[<C-\><C-n>]], { buffer = target_buf })
  vim.keymap.set('n', 'q', function()
    HideTerminalWindow(terminal_type)
  end, { buffer = target_buf })

  -- SAFE RE-ROUTING NAVIGATION KEYMAP:
  -- When the user presses <C-k> to leave the terminal, this macro instantly jumps
  -- them out of the terminal tab and drops them back into their healthy workspace file tab!
  vim.keymap.set({ 'n', 't' }, '<C-k>', function()
    if vim.api.nvim_get_mode().mode == 't' then
      local esc = vim.api.nvim_replace_termcodes([[<C-\><C-n>]], true, true, true)
      vim.api.nvim_feedkeys(esc, 'n', false)
    end
    vim.schedule(function()
      if original_workspace_tab and vim.api.nvim_tabpage_is_valid(original_workspace_tab) then
        vim.api.nvim_set_current_tabpage(original_workspace_tab)
      end
    end)
  end, { buffer = target_buf, silent = true })

  -- DOUBLE SEMI-COLON CROSS SWITCHER LOGIC
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

  -- GLOBAL INTERCEPT DOWNWARD MOVEMENT HOOK:
  -- Focuses your cursor straight down into your active terminal pane natively,
  -- automatically moving them into the isolated terminal tab view.
  vim.keymap.set('n', '<C-j>', function()
    if pio_isolated_tab and vim.api.nvim_tabpage_is_valid(pio_isolated_tab) then
      vim.api.nvim_set_current_tabpage(pio_isolated_tab)
      local cur_win = (terminal_type == 'monitor') and pio_mon_win or pio_cli_win
      if cur_win and vim.api.nvim_win_is_valid(cur_win) then
        vim.api.nvim_set_current_win(cur_win)
        vim.cmd('startinsert')
      end
    else
      vim.cmd('wincmd j')
    end
  end, { silent = true })

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

  -- Pass PlatformIO command strings directly through the background terminal channel
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
