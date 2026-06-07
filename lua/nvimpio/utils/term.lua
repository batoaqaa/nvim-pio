local M = {}

-- Memory trackers for your two persistent plugin terminal buffers
local pio_cli_buf = nil
local pio_mon_buf = nil

-- Memory trackers for the floating window handles
local pio_cli_win = nil
local pio_mon_win = nil

----------------------------------------------------------------------------------------
-- INFO: Safe terminal exit routine (Tied to pressing 'q' inside normal mode)
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

----------------------------------------------------------------------------------------
-- INFO: Unified Full-Width Bottom Terminal Spawner (Pure Native Floating Engine)
function M.ToggleTerminal(command, terminal_type)
  -- 1. Title evaluated immediately at the top to ensure correct recall headers
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

  -- 2. MUTUAL EXCLUSION: If the opponent window is currently open, hide it first
  if other_win and vim.api.nvim_win_is_valid(other_win) then
    vim.api.nvim_win_close(other_win, true)
    if terminal_type == 'monitor' then
      pio_cli_win = nil
    else
      pio_mon_win = nil
    end
  end

  -- 3. TOGGLE ACTION: If our target terminal window is already open on screen, close it
  if target_win and vim.api.nvim_win_is_valid(target_win) then
    vim.api.nvim_win_close(target_win, true)
    if terminal_type == 'monitor' then
      pio_mon_win = nil
    else
      pio_cli_win = nil
    end
    return
  end

  -- 4. BUFFER COUPLING OR PROCESS INITIALIZATION (Unlisted scratch buffer)
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

  -- 5. ABSOLUTE GEOMETRIC CONFIGURATION BOUNDS:
  local target_height = math.ceil(vim.o.lines * 0.28)
  local cmdheight = vim.o.cmdheight or 1

  local win_opts = {
    relative = 'editor', -- Anchors bounds to the screen frame grid, bypassing splits!
    style = 'minimal', -- Strips borders, columns, and layout shifting overhead
    focusable = true, -- Keeps keyboard cursor typing responsive
    width = vim.o.columns,
    height = target_height,
    row = vim.o.lines - target_height - cmdheight - 1,
    col = 0,
  }

  -- 6. DRAW THE PERMANENT HORIZONTAL LAYER
  local new_win = vim.api.nvim_open_win(target_buf, true, win_opts)
  if terminal_type == 'monitor' then
    pio_mon_win = new_win
  else
    pio_cli_win = new_win
  end

  -- 7. HARD-LOCK LAYOUT PROPERTIES
  vim.cmd('setlocal nonumber norelativenumber signcolumn=no')
  vim.api.nvim_set_option_value('winfixheight', true, { scope = 'local', win = new_win })

  -- 8. VISUAL STYLING AND FIXED WINBAR HEADER
  local hl = { bg = '#80a3d4', fg = '#000000' }
  vim.api.nvim_set_hl(0, 'MyWinBar', { bg = hl.bg, fg = hl.fg })
  local winBartitle = '%#MyWinBar# ' .. title .. ' [Press q to hide]%*'
  vim.api.nvim_set_option_value('winbar', winBartitle, { scope = 'local', win = new_win })

  -----------------------------------------------------------------------------
  -- LOCAL MAPS (Scoped to this native buffer instance)
  -----------------------------------------------------------------------------
  vim.keymap.set('t', '<Esc>', [[<C-\><C-n>]], { buffer = target_buf })
  vim.keymap.set('n', 'q', function()
    HideTerminalWindow(terminal_type)
  end, { buffer = target_buf })

  -- Escape path out of the terminal overlay back UP to code files
  vim.keymap.set({ 'n', 't' }, '<C-k>', function()
    if vim.api.nvim_get_mode().mode == 't' then
      local esc = vim.api.nvim_replace_termcodes([[<C-\><C-n>]], true, true, true)
      vim.api.nvim_feedkeys(esc, 'n', false)
    end
    vim.schedule(function()
      vim.cmd('wincmd k')
    end)
  end, { buffer = target_buf, silent = true })

  -- NEW TAB SWITCHING HOOK: Instantly jumps between CLI and Monitor panels!
  vim.keymap.set({ 'n', 't' }, '<Tab>', function()
    -- 1. Safely drop out of terminal input mode if typing
    if vim.api.nvim_get_mode().mode == 't' then
      local esc = vim.api.nvim_replace_termcodes([[<C-\><C-n>]], true, true, true)
      vim.api.nvim_feedkeys(esc, 'n', false)
    end

    -- 2. Figure out the other terminal type we want to switch to
    local next_type = (terminal_type == 'monitor') and 'cli' or 'monitor'
    local next_win = (next_type == 'monitor') and pio_mon_win or pio_cli_win

    -- 3. Micro-schedule the jump so Neovim drops insert mode before shifting windows
    vim.schedule(function()
      if next_win and vim.api.nvim_win_is_valid(next_win) then
        -- If the other terminal window is open, glide focus into it immediately
        vim.api.nvim_set_current_win(next_win)
        vim.cmd('startinsert')
      else
        -- If it's hidden, trigger your Toggle Terminal function to pull it up
        M.ToggleTerminal('', next_type)
      end
    end)
  end, { buffer = target_buf, silent = true, desc = 'Switch between PlatformIO terminals' })
  -----------------------------------------------------------------------------
  -- GLOBAL NAVIGATION & RECALL SHORTCUTS
  -----------------------------------------------------------------------------
  vim.keymap.set('n', '<C-h>', '<C-w>h')
  vim.keymap.set('n', '<C-l>', '<C-w>l')

  -- Intercepts Ctrl-J everywhere and drops cursor directly into this layout win ID
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
