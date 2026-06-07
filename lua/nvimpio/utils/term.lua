local M = {}

-- Memory slots to preserve running terminal process background buffers
local pio_cli_buf = nil
local pio_mon_buf = nil

-- Memory trackers for the native terminal channel IDs (job IDs)
local pio_cli_chan = nil
local pio_mon_chan = nil

----------------------------------------------------------------------------------------
-- INFO: Safe Hide Engine (Tied to pressing 'q' inside normal mode)
local function HideTerminalWindow(terminal_type)
  local target_buf = (terminal_type == 'monitor') and pio_mon_buf or pio_cli_buf
  if target_buf and vim.api.nvim_buf_is_valid(target_buf) then
    local win_id = vim.fn.bufwinid(target_buf)
    if win_id and win_id ~= -1 then
      vim.api.nvim_win_close(win_id, true)
    end
  end
end

----------------------------------------------------------------------------------------
-- INFO: Unified Full-Width Bottom Terminal Spawner (Stable Architecture)
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

  local target_buf = (terminal_type == 'monitor') and pio_mon_buf or pio_cli_buf
  local other_buf = (terminal_type == 'monitor') and pio_cli_buf or pio_mon_buf

  -- 2. MUTUAL EXCLUSION: If the other terminal panel window is open, hide it first
  if other_buf and vim.api.nvim_buf_is_valid(other_buf) then
    local other_win = vim.fn.bufwinid(other_buf)
    if other_win and other_win ~= -1 then
      vim.api.nvim_win_close(other_win, true)
    end
  end

  -- 3. TOGGLE ACTION: If our target window is already open, hide it
  if target_buf and vim.api.nvim_buf_is_valid(target_buf) then
    local target_win = vim.fn.bufwinid(target_buf)
    if target_win and target_win ~= -1 then
      vim.api.nvim_win_close(target_win, true)
      return
    end
  end

  -- 4. PROCESS PERSISTENCE: Pure native unlisted scratch buffer generation
  if not target_buf or not vim.api.nvim_buf_is_valid(target_buf) then
    target_buf = vim.api.nvim_create_buf(false, true) -- Unlisted scratch buffer
    if terminal_type == 'monitor' then
      pio_mon_buf = target_buf
    else
      pio_cli_buf = target_buf
    end

    -- FIXED CRASH: We execute jobstart directly onto an unmodified buffer.
    -- We removed nvim_open_term completely to fix the buffer conflict error.
    vim.api.nvim_buf_call(target_buf, function()
      local job_id = vim.fn.jobstart(vim.o.shell, {
        term = true,
        on_exit = function()
          if terminal_type == 'monitor' then
            pio_mon_chan = nil
          else
            pio_cli_chan = nil
          end
        end,
      })
      if terminal_type == 'monitor' then
        pio_mon_chan = job_id
      else
        pio_cli_chan = job_id
      end
    end)
  end

  -- 5. FIXED ABSOLUTE PANEL DIMENSIONS:
  -- Using 'botright split' with a hardlocked height creates a true workspace split
  -- and completely avoids any aggressive resizing autocommands or loop loops.
  local target_height = math.ceil(vim.o.lines * 0.28)
  vim.cmd('botright ' .. target_height .. 'split')
  local new_win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(new_win, target_buf)

  -- 6. HARD-LOCK WINDOW FLAGS:
  -- Tells Neovim that your terminal window size is rigid and cannot be squished
  -- or collapsed down by files or other incoming windows.
  vim.cmd('setlocal nonumber norelativenumber signcolumn=no')
  vim.api.nvim_set_option_value('winfixheight', true, { scope = 'local', win = new_win })

  -- 7. VISUAL CUSTOM WINBAR STYLING
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
  -- GLOBAL SHORTCUT OVERRIDES (Registered dynamically for the active window)
  -----------------------------------------------------------------------------
  vim.keymap.set('n', '<C-h>', '<C-w>h')
  vim.keymap.set('n', '<C-l>', '<C-w>l')

  -- GLOBAL INTERCEPT DOWNWARD MOVEMENT HOOK:
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
    end, { silent = true })
  else
    vim.keymap.set('n', [[<leader>\t]], function()
      M.ToggleTerminal('', 'cli')
    end, { silent = true })
  end
  -----------------------------------------------------------------------------

  -- Automatically stream project compile command flags via the modern channel pipelines
  if command and command ~= '' then
    local active_job = (terminal_type == 'monitor') and pio_mon_chan or pio_cli_chan
    if active_job then
      -- FIXED: Uses the native nvim_chan_send API on the unmodified job channel
      vim.api.nvim_chan_send(active_job, command .. (vim.fn.has('win32') == 1 and '\r\n' or '\n'))
    end
  end

  vim.cmd('startinsert')
end

return M
