local M = {}

-- Background memory tracking slots for running shell terminal processes
local pio_cli_buf = nil
local pio_mon_buf = nil

-- Display window handles (Kept global inside the file scope)
local pio_cli_win = nil
local pio_mon_win = nil

-- Memory slots to track the active job channels for streaming commands
local pio_cli_chan = nil
local pio_mon_chan = nil

----------------------------------------------------------------------------------------
-- INFO: Safe Window Closure Logic (Triggered on 'q' or when toggling off)
local function HideTerminalWindow(terminal_type)
  local win_id = (terminal_type == 'monitor') and pio_mon_win or pio_cli_win
  if win_id and vim.api.nvim_win_is_valid(win_id) then
    vim.api.nvim_win_close(win_id, true)
  end
  if terminal_type == 'monitor' then
    pio_mon_win = nil
  else
    pio_cli_win = nil
  end
end

----------------------------------------------------------------------------------------
-- INFO: Core Layout Spawner (Global Canvas Layer Architecture)
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

  -- 3. TOGGLE WINDOW ACTION: If this window is open, hide it
  if target_win and vim.api.nvim_win_is_valid(target_win) then
    vim.api.nvim_win_close(target_win, true)
    if terminal_type == 'monitor' then
      pio_mon_win = nil
    else
      pio_cli_win = nil
    end
    return
  end

  -- 4. PROCESS PERSISTENCE: Pure modern Lua channel spawning architecture
  if not target_buf or not vim.api.nvim_buf_is_valid(target_buf) then
    -- Create a hidden scratch buffer that is strictly unlisted
    target_buf = vim.api.nvim_create_buf(false, true)
    if terminal_type == 'monitor' then
      pio_mon_buf = target_buf
    else
      pio_cli_buf = target_buf
    end

    -- FIXED: We let jobstart handle the term channel attachment natively on an unmodified buffer.
    -- This eliminates the "requires unmodified buffer" Neovim runtime crash.
    vim.api.nvim_buf_call(target_buf, function()
      local job_id = vim.fn.jobstart(vim.o.shell, {
        term = true,
        -- Automatically drops the cursor back into insertion mode when re-focusing
        on_exit = function()
          if terminal_type == 'monitor' then
            pio_mon_chan = nil
          else
            pio_cli_chan = nil
          end
        end,
      })

      -- Cache the native terminal channel pointer globally for your command execution streams
      if terminal_type == 'monitor' then
        pio_mon_chan = job_id
      else
        pio_cli_chan = job_id
      end
    end)
  end
  -- 5. ABSOLUTE GEOMETRIC GRID PLACEMENT:
  local target_height = math.ceil(vim.o.lines * 0.28)
  local cmdheight = vim.o.cmdheight or 1

  local win_opts = {
    relative = 'editor', -- Breaks completely out of vertical pillar layouts
    style = 'minimal',
    focusable = true,
    width = vim.o.columns,
    height = target_height,
    row = vim.o.lines - target_height - cmdheight - 1,
    col = 0,
  }

  -- 6. RENDER PANEL OVERLAY LAYER
  local new_win = vim.api.nvim_open_win(target_buf, true, win_opts)
  if terminal_type == 'monitor' then
    pio_mon_win = new_win
  else
    pio_cli_win = new_win
  end

  -- 7. SYSTEM OPTION DECORATIONS
  vim.cmd('setlocal nonumber norelativenumber signcolumn=no')
  vim.api.nvim_set_option_value('winfixheight', true, { scope = 'local', win = new_win })

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

  -- Automatically stream project compile command flags via the channel pipelines
  if command and command ~= '' then
    local active_job = (terminal_type == 'monitor') and pio_mon_chan or pio_cli_chan
    if active_job then
      -- Sends your PlatformIO macro instructions down to the running interactive shell thread
      vim.api.nvim_chan_send(active_job, command .. (vim.fn.has('win32') == 1 and '\r\n' or '\n'))
    end
  end
  vim.cmd('startinsert')
end

return M
