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

-- Layout scroll offset trackers to prevent text overlapping
local original_scrolloff = nil
local active_parent_win = nil

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

  -- Restore the user's personal scroll configuration cleanly when terminal exits
  if active_parent_win and vim.api.nvim_win_is_valid(active_parent_win) and original_scrolloff then
    vim.wo[active_parent_win].scrolloff = original_scrolloff
    original_scrolloff = nil
    active_parent_win = nil
  end
  vim.cmd('redraw!')
end

----------------------------------------------------------------------------------------
-- INFO: Core Layout Spawner (Global Dependency-Free Architecture)
function M.ToggleTerminal(command, terminal_type)
  -- 1. Normalize variables and titles right at the top
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

  -- 2. MUTUAL EXCLUSION: If the opponent window is visible, hide it first
  if other_win and vim.api.nvim_win_is_valid(other_win) then
    local other_type = (terminal_type == 'monitor') and 'cli' or 'monitor'
    HideTerminalWindow(other_type)
  end

  -- 3. TOGGLE ACTION: If our target window is already open, close it
  if target_win and vim.api.nvim_win_is_valid(target_win) then
    HideTerminalWindow(terminal_type)
    return
  end

  -- Cache the user's active code file window handle right before we spawn the split
  local parent_file_win = vim.api.nvim_get_current_win()

  -- 4. CLEAN PROCESS PERSISTENCE: Pure native unlisted scratch buffer generation
  if not target_buf or not vim.api.nvim_buf_is_valid(target_buf) then
    target_buf = vim.api.nvim_create_buf(false, true) -- Unlisted scratch buffer
    if terminal_type == 'monitor' then
      pio_mon_buf = target_buf
    else
      pio_cli_buf = target_buf
    end

    -- Hardlock PowerShell natively on Windows platforms to fix typing line feeds
    local target_shell = vim.o.shell
    if vim.fn.has('win32') == 1 then
      target_shell = 'powershell.exe'
    end

    -- Launch the terminal natively inside a buffer context call loop [INDEX]
    vim.api.nvim_buf_call(target_buf, function()
      vim.fn.termopen(target_shell, {
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

  -- 5. BUFFER-RELATIVE GEOMETRY CONFIGURATION
  local file_win_width = vim.api.nvim_win_get_width(parent_file_win)
  local file_win_height = vim.api.nvim_win_get_height(parent_file_win)
  local target_height = math.ceil(file_win_height * 0.32)

  local win_opts = {
    relative = 'win', -- Hard-locks to the active text viewport branch
    win = parent_file_win, -- Anchors coordinate boundaries to the code file window frame
    style = 'minimal', -- Strips margins, gutters, and borders
    focusable = true, -- Keeps keyboard layout inputs active
    width = file_win_width, -- Stretches exactly across the width of the code pane
    height = target_height,
    row = file_win_height - target_height, -- Clamps precisely to the bottom of the active file view
    col = 0,
  }

  -- 6. SHUN OVERLAP SCROLL PADDING: Force file text to compress upward [INDEX]
  if not original_scrolloff and vim.api.nvim_win_is_valid(parent_file_win) then
    original_scrolloff = vim.wo[parent_file_win].scrolloff
    active_parent_win = parent_file_win
    vim.wo[parent_file_win].scrolloff = target_height + 2

    -- Forces an immediate text reflow so no code rows stay hidden behind the overlay
    vim.api.nvim_win_call(parent_file_win, function()
      vim.cmd('normal! zz')
    end)
  end

  -- 7. RENDER THE SECURE horizont PANEL OVERLAY
  local new_win = vim.api.nvim_open_win(target_buf, true, win_opts)
  if terminal_type == 'monitor' then
    pio_mon_win = new_win
  else
    pio_cli_win = new_win
  end

  -- 8. PANE OPTION DECORATIONS
  vim.cmd('setlocal nonumber norelativenumber signcolumn=no')
  vim.api.nvim_set_option_value('winfixheight', true, { scope = 'local', win = new_win })

  -- 9. VISUAL WINBAR DECORATIONS
  local hl = { bg = '#80a3d4', fg = '#000000' }
  vim.api.nvim_set_hl(0, 'MyWinBar', { bg = hl.bg, fg = hl.fg })
  local winBartitle = '%#MyWinBar#' .. title .. '%*'
  vim.api.nvim_set_option_value('winbar', winBartitle, { scope = 'local', win = new_win })

  -----------------------------------------------------------------------------
  -- LOCAL MAPS (Scoped strictly to this terminal buffer layer instance)
  -----------------------------------------------------------------------------
  vim.keymap.set('t', '<Esc>', [[<C-\><C-n>]], { buffer = target_buf })
  vim.keymap.set('n', 'q', function()
    HideTerminalWindow(terminal_type)
  end, { buffer = target_buf })

  -- Crash-free Upward focus vector escape path out of the terminal back to your file code buffer
  vim.keymap.set({ 'n', 't' }, '<C-k>', function()
    if vim.api.nvim_get_mode().mode == 't' then
      local esc_seq = vim.api.nvim_replace_termcodes([[<C-\><C-n>]], true, true, true)
      vim.api.nvim_feedkeys(esc_seq, 'n', false)
    end
    vim.schedule(function()
      if parent_file_win and vim.api.nvim_win_is_valid(parent_file_win) then
        vim.api.nvim_set_current_win(parent_file_win)
      end
    end)
  end, { buffer = target_buf, silent = true })

  -- Cross-Fading Panel Switcher: Tap double semi-colon (;;) to cross-fade panels instantly!
  vim.keymap.set({ 'n', 't' }, ';;', function()
    if vim.api.nvim_get_mode().mode == 't' then
      local esc_seq = vim.api.nvim_replace_termcodes([[<C-\><C-n>]], true, true, true)
      vim.api.nvim_feedkeys(esc_seq, 'n', false)
    end
    local next_type = (terminal_type == 'monitor') and 'cli' or 'monitor'
    vim.schedule(function()
      M.ToggleTerminal('', next_type)
    end)
  end, { buffer = target_buf, silent = true })

  -----------------------------------------------------------------------------
  -- GLOBAL NAVIGATION & RECALL SHORTCUTS
  -----------------------------------------------------------------------------
  vim.keymap.set('n', '<C-h>', '<C-w>h')
  vim.keymap.set('n', '<C-l>', '<C-w>l')

  -- GLOBAL INTERCEPT DOWNWARD MOVEMENT KEY:
  vim.keymap.set('n', '<C-j>', function()
    local cur_win = (terminal_type == 'monitor') and pio_mon_win or pio_cli_win
    if cur_win and vim.api.nvim_win_is_valid(cur_win) then
      vim.api.nvim_set_current_win(cur_win)
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

  -- Pass PlatformIO command strings directly through the native channel
  if command and command ~= '' then
    local chan_id = vim.b[target_buf].terminal_job_id
    if chan_id then
      vim.fn.chansend(chan_id, command .. (vim.fn.has('win32') == 1 and '\r\n' or '\n'))
    end
  end

  vim.cmd('startinsert')
end

return M
