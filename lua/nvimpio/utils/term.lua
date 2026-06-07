local M = {}

-- Memory slots to preserve running terminal process background buffers
local pio_cli_buf = nil
local pio_mon_buf = nil

-- Memory trackers for the floating window handles
local pio_cli_win = nil
local pio_mon_win = nil

function M.get_part(str, index)
  local parts = vim.split(str, ':')
  return parts[index] or ''
end

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
end

function M.ToggleTerminal(command, terminal_type)
  local target_win = (terminal_type == 'monitor') and pio_mon_win or pio_cli_win
  local other_win = (terminal_type == 'monitor') and pio_cli_win or pio_mon_win
  local target_buf = (terminal_type == 'monitor') and pio_mon_buf or pio_cli_buf

  -- 1. MUTUAL EXCLUSION: If the other terminal is open, close it out first
  if other_win and vim.api.nvim_win_is_valid(other_win) then
    vim.api.nvim_win_close(other_win, true)
    if terminal_type == 'monitor' then
      pio_cli_win = nil
    else
      pio_mon_win = nil
    end
  end

  -- 2. TOGGLE ACTION: If our target window is already open, close it
  if target_win and vim.api.nvim_win_is_valid(target_win) then
    vim.api.nvim_win_close(target_win, true)
    if terminal_type == 'monitor' then
      pio_mon_win = nil
    else
      pio_cli_win = nil
    end
    return
  end

  -- 3. BACKGROUND BUFFER VALIDATION: Reuse existing shell or generate a fresh process
  if not target_buf or not vim.api.nvim_buf_is_valid(target_buf) then
    target_buf = vim.api.nvim_create_buf(false, true)
    if terminal_type == 'monitor' then
      pio_mon_buf = target_buf
    else
      pio_cli_buf = target_buf
    end

    vim.api.nvim_buf_call(target_buf, function()
      vim.fn.termopen(vim.o.shell)
    end)
  end

  -- 4. ABSOLUTE GEOMETRIC BOUNDS
  local target_height = math.ceil(vim.o.lines * 0.28)
  local cmdheight = vim.o.cmdheight or 1

  local win_opts = {
    relative = 'editor', -- Forces it to act as a bottom layout panel above sidebars
    style = 'minimal',
    focusable = true,
    width = vim.o.columns,
    height = target_height,
    row = vim.o.lines - target_height - cmdheight - 1,
    col = 0,
  }

  -- 5. DRAW WINDOW
  local new_win = vim.api.nvim_open_win(target_buf, true, win_opts)
  if terminal_type == 'monitor' then
    pio_mon_win = new_win
  else
    pio_cli_win = new_win
  end

  -- 6. VISUAL CUSTOM WINBAR STYLING
  local hl = { bg = '#80a3d4', fg = '#000000' }
  vim.api.nvim_set_hl(0, 'MyWinBar', { bg = hl.bg, fg = hl.fg })
  local title = (terminal_type == 'monitor') and 'Pio Monitor' or 'Pio CLI>'
  local winBartitle = '%#MyWinBar# ' .. title .. ' [Press q to hide]%*'
  vim.api.nvim_set_option_value('winbar', winBartitle, { scope = 'local', win = new_win })

  -----------------------------------------------------------------------------
  -- KEYMAP GROUP A: BUFFER-LOCAL KEYMAPS (Only work INSIDE the terminal)
  -----------------------------------------------------------------------------
  -- Safely drop out of terminal input mode back to normal navigation mode
  vim.keymap.set('t', '<Esc>', [[<C-\><C-n>]], { buffer = target_buf })

  -- Tap 'q' in normal mode to instantly hide the panel
  vim.keymap.set('n', 'q', function()
    HideTerminalWindow(terminal_type)
  end, { buffer = target_buf })

  -- Escape path out of the terminal panel back UP to code workspace files

  -- Escape path out of the terminal panel back UP to code workspace files
  vim.keymap.set({ 'n', 't' }, '<C-k>', function()
    -- FIXED CRASH: Replaced broken vim.cmd string with safe native feedkeys
    if vim.api.nvim_get_mode().mode == 't' then
      local escape_keys = vim.api.nvim_replace_termcodes([[<C-\><C-n>]], true, true, true)
      vim.api.nvim_feedkeys(escape_keys, 'n', false)
    end

    -- Micro-schedule ensures the terminal drops insertion state before Neovim moves the cursor window focus
    vim.schedule(function()
      vim.cmd('wincmd k')
    end)
  end, { buffer = target_buf, silent = true })
  -----------------------------------------------------------------------------
  -- KEYMAP GROUP B: GLOBAL NAVIGATION HOOKS (Registered on generation)
  -----------------------------------------------------------------------------
  -- Re-register standard directional layout moves
  vim.keymap.set('n', '<C-h>', '<C-w>h')
  vim.keymap.set('n', '<C-l>', '<C-w>l')

  -- Intercepts Ctrl-J everywhere in Neovim and routes focus straight to this terminal win ID
  vim.keymap.set('n', '<C-j>', function()
    -- Dynamically verify that the window handle we generated is still valid and open
    if new_win and vim.api.nvim_win_is_valid(new_win) then
      vim.api.nvim_set_current_win(new_win)
      vim.cmd('startinsert')
    else
      -- Fallback cleanly to user's standard downward layout navigation if panel is hidden
      vim.cmd('wincmd j')
    end
  end, { silent = true })

  if terminal_type == 'monitor' then
    vim.keymap.set('n', '<leader>\\gm', function()
      M.ToggleTerminal('', 'monitor')
    end, { desc = 'Toggle/Recall PlatformIO Monitor Panel', silent = true })
  else
    vim.keymap.set('n', '<leader>\\t', function()
      M.ToggleTerminal('', 'cli')
    end, { desc = 'Toggle/Recall PlatformIO CLI Panel', silent = true })
  end
  -----------------------------------------------------------------------------

  -- 8. EXECUTE PENDING PLATFORMIO COMMAND STRINGS
  if command and command ~= '' then
    local job_id = vim.b[target_buf].terminal_job_id
    if job_id then
      vim.fn.chansend(job_id, command .. (vim.fn.has('win32') == 1 and '\r\n' or '\n'))
    end
  end

  vim.cmd('startinsert')
end
return M
