local M = {}

local config = require('nvimpio').config

M.stdout_callback = nil
M.exit_callback = nil

-- Persistent background storage buffers for running shell processes
local pio_cli_buf = nil
local pio_mon_buf = nil

-- Display window tracking handles
local pio_cli_win = nil
local pio_mon_win = nil

-- HARD-LOCK HEIGHT PROFILE METRIC: Stores the static target height globally within the module loop
local target_panel_height = 0

----------------------------------------------------------------------------------------
-- INFO: Safe terminal exit routine (Tied to pressing 'q' inside normal mode)
local function SafeCloseTerminal(buf_id)
  if buf_id and vim.api.nvim_buf_is_valid(buf_id) then
    local win_id = vim.fn.bufwinid(buf_id)
    if win_id and win_id ~= -1 and vim.api.nvim_win_is_valid(win_id) then
      vim.api.nvim_win_close(win_id, true)
      -- Force standard workspace windows to balance their layout spacing evenly once on close
      vim.cmd('wincmd =')
    end
  end
end

----------------------------------------------------------------------------------------
-- INFO: Core Layout Spawner (Global Edge-Anchored Window Partition Architecture)
function M.ToggleTerminal(command, terminal_type)
  -- 1. Enforce strict title header assignments immediately at the top
  local title = ''
  if terminal_type == 'monitor' or (command and string.find(command, ' monitor')) then
    title = ' Pio Monitor '
    terminal_type = 'monitor'
  else
    title = ' Pio CLI> '
    terminal_type = 'cli'
  end

  local target_win = (terminal_type == 'monitor') and pio_mon_win or pio_cli_win
  local other_win = (terminal_type == 'monitor') and pio_cli_win or pio_mon_win
  local target_buf = (terminal_type == 'monitor') and pio_mon_buf or pio_cli_buf
  local other_buf = (terminal_type == 'monitor') and pio_cli_buf or pio_mon_buf

  -- 2. MUTUAL EXCLUSION: If the opponent window is visible, hide it first
  if other_win and vim.api.nvim_win_is_valid(other_win) then
    SafeCloseTerminal(other_buf)
  end

  -- 3. TOGGLE ACTION: If our target window is already open, close it
  if target_win and vim.api.nvim_win_is_valid(target_win) then
    SafeCloseTerminal(target_buf)
    return
  end

  -- 4. NEW HASSLE-FREE PROCESS INITIALIZATION ENGINE: Completely free of deprecated APIs
  if not target_buf or not vim.api.nvim_buf_is_valid(target_buf) then
    target_buf = vim.api.nvim_create_buf(false, true) -- Unlisted scratch buffer
    if terminal_type == 'monitor' then
      pio_mon_buf = target_buf
    else
      pio_cli_buf = target_buf
    end

    -- Detect shell engine path natively
    local target_shell = vim.o.shell
    if vim.fn.has('win32') == 1 then
      if vim.fn.executable('pwsh.exe') == 1 then
        target_shell = 'pwsh.exe'
      else
        target_shell = 'powershell.exe'
      end
    end

    -- FIXED FIX: We call jobstart inside a pristine buffer wrapper without nvim_open_term.
    -- This sets the 'buftype' to 'terminal' cleanly, preventing deprecation warnings and line typing bugs!
    vim.api.nvim_buf_call(target_buf, function()
      vim.fn.jobstart(target_shell, {
        term = true, -- Attaches a native PTY container natively onto the blank buffer context
        on_stdout = function(_, data, _)
          if type(M.stdout_callback) == 'function' then
            M.stdout_callback(target_buf, data)
          end
        end,
        on_exit = function()
          if type(M.exit_callback) == 'function' then
            M.exit_callback()
          end
        end,
      })
    end)
  end

  -- 5. THE GLOBAL GRID TRACKER MATRICES:
  target_panel_height = math.ceil(vim.o.lines * 0.28)

  local win_opts = {
    split = 'below', -- Directions token to open the partition beneath upper nodes
    win = -1, -- HARDLOCK GRID: Breaks out of local columns into top-level monitor screen frame
    height = target_panel_height,
  }

  -- 6. RENDER THE STABLE CORE ROW PARTITION
  local new_win = vim.api.nvim_open_win(target_buf, true, win_opts)
  if terminal_type == 'monitor' then
    pio_mon_win = new_win
  else
    pio_cli_win = new_win
  end

  -- 7. CLEAN WINDOW SYSTEM FLAGS (Completely free of layout loops)
  vim.cmd('setlocal nonumber norelativenumber signcolumn=no')
  vim.api.nvim_set_option_value('winfixheight', true, { scope = 'local', win = new_win })

  -- 8. FIXED ANTI-SHRINKING VIEWPORT GUARD
  local pio_group = vim.api.nvim_create_augroup('PioFocusGuard_' .. target_buf, { clear = true })
  vim.api.nvim_create_autocmd('WinEnter', {
    group = pio_group,
    buffer = target_buf,
    callback = function()
      local term_win = (terminal_type == 'monitor') and pio_mon_win or pio_cli_win
      if term_win and vim.api.nvim_win_is_valid(term_win) then
        pcall(vim.api.nvim_win_set_height, term_win, target_panel_height)
      end
    end,
  })

  -- 9. VISUAL CUSTOM WINBAR STYLING
  local hl = { bg = '#80a3d4', fg = '#000000' }
  vim.api.nvim_set_hl(0, 'MyWinBar', { bg = hl.bg, fg = hl.fg })
  local winBartitle = '%#MyWinBar#' .. title .. '%*'
  vim.api.nvim_set_option_value('winbar', winBartitle, { scope = 'local', win = new_win })

  -----------------------------------------------------------------------------
  -- LOCAL MAPS (Scoped strictly to this terminal buffer layer instance)
  -----------------------------------------------------------------------------
  vim.keymap.set('t', '<Esc>', [[<C-\><C-n>]], { buffer = target_buf })
  vim.keymap.set('n', 'q', function()
    SafeCloseTerminal(target_buf)
  end, { buffer = target_buf })

  -- CRASH-FREE UPWARD NAVIGATION KEYMAP
  vim.keymap.set({ 'n', 't' }, '<C-k>', function()
    if vim.api.nvim_get_mode().mode == 't' then
      local esc = vim.api.nvim_replace_termcodes([[<C-\><C-n>]], true, true, true)
      vim.api.nvim_feedkeys(esc, 'n', false)
    end
    vim.schedule(function()
      vim.cmd('wincmd k')
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
  vim.keymap.set('n', '<C-j>', function()
    local cur_win = (terminal_type == 'monitor') and pio_mon_win or pio_cli_win
    if cur_win and vim.api.nvim_win_is_valid(cur_win) then
      vim.api.nvim_set_current_win(cur_win)
      pcall(vim.api.nvim_win_set_height, cur_win, target_panel_height)
      vim.cmd('startinsert')
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
-- local config = require('nvimpio').config
--
-- M.stdout_callback = nil
-- M.exit_callback = nil
--
-- -- Persistent background storage buffers for running shell processes
-- local pio_cli_buf = nil
-- local pio_mon_buf = nil
--
-- -- Display window tracking handles
-- local pio_cli_win = nil
-- local pio_mon_win = nil
--
-- -- HARD-LOCK HEIGHT PROFILE METRIC: Stores the static target height globally within the module loop
-- local target_panel_height = 0
--
-- ----------------------------------------------------------------------------------------
-- -- INFO: Safe terminal exit routine (Tied to pressing 'q' inside normal mode)
-- local function SafeCloseTerminal(buf_id)
--   if buf_id and vim.api.nvim_buf_is_valid(buf_id) then
--     local win_id = vim.fn.bufwinid(buf_id)
--     if win_id and win_id ~= -1 and vim.api.nvim_win_is_valid(win_id) then
--       vim.api.nvim_win_close(win_id, true)
--       -- Force standard workspace windows to balance their layout spacing evenly once on close
--       vim.cmd('wincmd =')
--     end
--   end
-- end
--
-- ----------------------------------------------------------------------------------------
-- -- INFO: Core Layout Spawner (Global Edge-Anchored Window Partition Architecture)
-- function M.ToggleTerminal(command, terminal_type)
--   -- 1. Enforce strict title header assignments immediately at the top
--   local title = ''
--   if command and string.find(command, ' monitor') then
--     title = ' Pio Monitor '
--     terminal_type = 'monitor'
--   else
--     title = ' Pio CLI> '
--     terminal_type = 'cli'
--   end
--
--   local target_win = (terminal_type == 'monitor') and pio_mon_win or pio_cli_win
--   local other_win = (terminal_type == 'monitor') and pio_cli_win or pio_mon_win
--   local target_buf = (terminal_type == 'monitor') and pio_mon_buf or pio_cli_buf
--   local other_buf = (terminal_type == 'monitor') and pio_cli_buf or pio_mon_buf
--
--   -- 2. MUTUAL EXCLUSION: FIXED: Correctly passes the scoped other_buf variable pointer
--   if other_win and vim.api.nvim_win_is_valid(other_win) then
--     SafeCloseTerminal(other_buf)
--   end
--
--   -- 3. TOGGLE ACTION: If our target window is already open, close it
--   if target_win and vim.api.nvim_win_is_valid(target_win) then
--     SafeCloseTerminal(target_buf)
--     return
--   end
--
--   -- 4. PROCESS PERSISTENCE: Pure native unlisted scratch buffer generation
--   if not target_buf or not vim.api.nvim_buf_is_valid(target_buf) then
--     target_buf = vim.api.nvim_create_buf(false, true) -- Unlisted scratch buffer
--     if terminal_type == 'monitor' then
--       pio_mon_buf = target_buf
--     else
--       pio_cli_buf = target_buf end
--
--     -- FIXED SHELL DETECTION FOR POWERSHELL 7+ (pwsh) vs POWERSHELL 5 (powershell)
--     local target_shell = vim.o.shell
--     if vim.fn.has('win32') == 1 then
--       -- If the user has modern PowerShell 7+ installed on their system, use it natively!
--       if vim.fn.executable('pwsh.exe') == 1 then
--         target_shell = 'pwsh.exe'
--       else
--         -- Fallback cleanly to built-in Windows PowerShell 5 if pwsh isn't found
--         target_shell = 'powershell.exe'
--       end
--     end
--
--     -- Run the shell cleanly. This sets 'buftype' to 'terminal' natively, fixing typing bugs!
--     vim.api.nvim_buf_call(target_buf, function()
--       vim.fn.termopen(target_shell, {
--         on_stdout = function(_, data, _)
--           if type(M.stdout_callback) == 'function' then
--             M.stdout_callback(target_buf, data)
--           end
--         end,
--         on_exit = function()
--           if type(M.exit_callback) == 'function' then
--             M.exit_callback()
--           end
--         end,
--       })
--     end)
--   end
--   -- 5. THE GLOBAL GRID TRACKER MATRICES:
--   -- We compute and freeze the height configuration variable during this instantiation pass
--   target_panel_height = math.ceil(vim.o.lines * 0.28)
--
--   local win_opts = {
--     split = 'below', -- Directions token to open the partition beneath upper nodes
--     win = -1, -- HARDLOCK GRID: Breaks out of local columns into top-level monitor screen frame
--     height = target_panel_height,
--   }
--
--   -- 6. RENDER THE STABLE CORE ROW PARTITION
--   local new_win = vim.api.nvim_open_win(target_buf, true, win_opts)
--   if terminal_type == 'monitor' then
--     pio_mon_win = new_win
--   else
--     pio_cli_win = new_win
--   end
--
--   -- 7. CLEAN WINDOW SYSTEM FLAGS (Completely free of layout loops)
--   vim.cmd('setlocal nonumber norelativenumber signcolumn=no')
--   vim.api.nvim_set_option_value('winfixheight', true, { scope = 'local', win = new_win })
--
--   -- 8. FIXED ANTI-SHRINKING VIEWPORT GUARD
--   -- This autocmd hooks exclusively onto the terminal buffer. Every single time the user clicks
--   -- or switches focus inside it, this callback forces Neovim to retain the rigid target height,
--   -- stopping any automatic column compression bugs.
--   local pio_group = vim.api.nvim_create_augroup('PioFocusGuard_' .. target_buf, { clear = true })
--   vim.api.nvim_create_autocmd('WinEnter', {
--     group = pio_group,
--     buffer = target_buf,
--     callback = function()
--       local term_win = (terminal_type == 'monitor') and pio_mon_win or pio_cli_win
--       if term_win and vim.api.nvim_win_is_valid(term_win) then
--         pcall(vim.api.nvim_win_set_height, term_win, target_panel_height)
--       end
--     end,
--   })
--
--   -- 9. VISUAL CUSTOM WINBAR STYLING
--   local hl = { bg = '#80a3d4', fg = '#000000' }
--   vim.api.nvim_set_hl(0, 'MyWinBar', { bg = hl.bg, fg = hl.fg })
--   local winBartitle = '%#MyWinBar#' .. title .. '%*'
--   vim.api.nvim_set_option_value('winbar', winBartitle, { scope = 'local', win = new_win })
--
--   -----------------------------------------------------------------------------
--   -- LOCAL MAPS (Scoped strictly to this terminal buffer layer instance)
--   -----------------------------------------------------------------------------
--   vim.keymap.set('t', '<Esc>', [[<C-\><C-n>]], { buffer = target_buf })
--   vim.keymap.set('n', 'q', function()
--     SafeCloseTerminal(target_buf)
--   end, { buffer = target_buf })
--
--   -- CRASH-FREE UPWARD NAVIGATION KEYMAP
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
--   -- FIXED ANTI-SHRINKING SHORTCUT: Enforces your target height size variable programmatically
--   -- right during the hotkey focus jump transition pass.
--   vim.keymap.set('n', '<C-j>', function()
--     local cur_win = (terminal_type == 'monitor') and pio_mon_win or pio_cli_win
--     if cur_win and vim.api.nvim_win_is_valid(cur_win) then
--       vim.api.nvim_set_current_win(cur_win)
--       pcall(vim.api.nvim_win_set_height, cur_win, target_panel_height)
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
