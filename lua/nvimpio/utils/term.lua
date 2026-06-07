local M = {}

-- Memory trackers for your two persistent plugin terminal buffers
local pio_cli_buf = nil
local pio_mon_buf = nil

-- Simple string splitter helper (No complex symbols to protect code box formatting)
function M.get_part(str, index)
  local parts = vim.split(str, ':')
  return parts[index] or ''
end

----------------------------------------------------------------------------------------
-- INFO: Safe terminal exit routine (Tied to pressing 'q' or running ':q')
local function SafeCloseTerminal(buf_id)
  local win_id = vim.fn.bufwinid(buf_id)
  if win_id and win_id ~= -1 then
    vim.api.nvim_win_close(win_id, true)
    -- Balance layout heights seamlessly when closed
    vim.cmd('wincmd =')
  end
end

----------------------------------------------------------------------------------------
-- INFO: Unified Full-Width Bottom Terminal Spawner
function M.ToggleTerminal(command, terminal_type)
  -- 1. Determine which buffer slot we are managing
  local target_buf = (terminal_type == 'monitor') and pio_mon_buf or pio_cli_buf
  local other_buf = (terminal_type == 'monitor') and pio_cli_buf or pio_mon_buf

  -- 2. MUTUAL EXCLUSION: If the other terminal window is open, hide it first
  if other_buf and vim.api.nvim_buf_is_valid(other_buf) then
    local other_win = vim.fn.bufwinid(other_buf)
    if other_win and other_win ~= -1 then
      vim.api.nvim_win_close(other_win, true)
    end
  end

  -- 3. TOGGLE ACTION: If our target terminal window is already open, hide it
  if target_buf and vim.api.nvim_buf_is_valid(target_buf) then
    local target_win = vim.fn.bufwinid(target_buf)
    if target_win and target_win ~= -1 then
      vim.api.nvim_win_close(target_win, true)
      vim.cmd('wincmd =')
      return
    end
  end

  -- 4. SPAWN STRATEGY: Initialize the window pane layout natively at the absolute bottom
  -- 'botright split' forces it to span 100% horizontally underneath BOTH code and sidebars (Aerial/Neo-tree)
  local target_height = math.ceil(vim.o.lines * 0.30)
  vim.cmd('botright ' .. target_height .. 'split')
  local new_win = vim.api.nvim_get_current_win()

  -- 5. BUFFER BUFFER REUSE OR FRESH GENERATION
  if target_buf and vim.api.nvim_buf_is_valid(target_buf) then
    -- Reuse existing running session background buffer
    vim.api.nvim_win_set_buf(new_win, target_buf)
  else
    -- Open a fresh native terminal process pipeline
    vim.cmd('terminal')
    target_buf = vim.api.nvim_get_current_buf()

    -- Cache it in memory so it stays active across focus shifts
    if terminal_type == 'monitor' then
      pio_mon_buf = target_buf
    else
      pio_cli_buf = target_buf
    end
  end

  -- 6. HARD-LOCK LAYOUT FROM DEFORMING
  -- Sets styles to look like a clean layout pane and prevents sidebars from resizing it
  vim.cmd('setlocal nonumber norelativenumber signcolumn=no')
  vim.api.nvim_set_option_value('winfixheight', true, { scope = 'local', win = new_win })

  -- 7. VISUAL WINBAR INTEGRATION
  local hl = { bg = '#80a3d4', fg = '#000000' }
  vim.api.nvim_set_hl(0, 'MyWinBar', { bg = hl.bg, fg = hl.fg })
  local title = (terminal_type == 'monitor') and 'Pio Monitor' or 'Pio CLI>'
  local winBartitle = '%#MyWinBar# ' .. title .. ' [Press q to hide]%*'
  vim.api.nvim_set_option_value('winbar', winBartitle, { scope = 'local', win = new_win })

  -- 8. LOCAL KEYMAPS BOUND TO THE PANE
  vim.keymap.set('t', '<Esc>', [[<C-\><C-n>]], { buffer = target_buf })
  vim.keymap.set('n', 'q', function()
    SafeCloseTerminal(target_buf)
  end, { buffer = target_buf })

  -- Automatically run a command if passed (like your platformio utils triggers)
  if command and command ~= '' then
    vim.fn.chansend(vim.b.terminal_job_id, command .. (vim.fn.has('win32') == 1 and '\r\n' or '\n'))
  end

  -- Drop cursor directly into typing state
  vim.cmd('startinsert')
end

----------------------------------------------------------------------------------------
-- INFO: Trigger Both PIO Terminals Mutually Exclusive
function M.ToggleBoth()
  -- If you want them to behave sequentially, users trigger them one at a time via your maps
  M.ToggleTerminal('', 'cli')
end

return M
