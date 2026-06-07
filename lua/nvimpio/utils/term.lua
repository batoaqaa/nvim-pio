local M = {}

-- Memory trackers for your two persistent plugin terminal buffers
local pio_cli_buf = nil
local pio_mon_buf = nil

----------------------------------------------------------------------------------------
-- INFO: Safe terminal exit routine (Tied to pressing 'q' inside normal mode)
-- FIXED: Declared at the very top of the script so it is defined for all keymaps
local function SafeCloseTerminal(buf_id)
  if buf_id and vim.api.nvim_buf_is_valid(buf_id) then
    local win_id = vim.fn.bufwinid(buf_id)
    if win_id and win_id ~= -1 and vim.api.nvim_win_is_valid(win_id) then
      vim.api.nvim_win_close(win_id, true)
      -- Force standard workspace columns to balance their layout spacing evenly
      vim.cmd('wincmd =')
    end
  end
end

----------------------------------------------------------------------------------------
-- INFO: Unified Full-Width Bottom Terminal Spawner
function M.ToggleTerminal(command, terminal_type)
  -- 1. Determine which buffer slot we are managing
  local target_buf = (terminal_type == 'monitor') and pio_mon_buf or pio_cli_buf
  local other_buf = (terminal_type == 'monitor') and pio_cli_buf or pio_mon_buf

  -- 2. MUTUAL EXCLUSION: If the opponent window is currently open, hide it first
  if other_buf and vim.api.nvim_buf_is_valid(other_buf) then
    local other_win = vim.fn.bufwinid(other_buf)
    if other_win and other_win ~= -1 and vim.api.nvim_win_is_valid(other_win) then
      vim.api.nvim_win_close(other_win, true)
    end
  end

  -- 3. TOGGLE ACTION: If our target terminal window is already open, close it
  if target_buf and vim.api.nvim_buf_is_valid(target_buf) then
    local target_win = vim.fn.bufwinid(target_buf)
    if target_win and target_win ~= -1 and vim.api.nvim_win_is_valid(target_win) then
      vim.api.nvim_win_close(target_win, true)
      vim.cmd('wincmd =')
      return
    end
  end

  -- 4. SPAWN STRATEGY: Initialize a native window pane layout at the bottom edge
  -- 'botright split' tells Neovim to initialize a root split boundary across the horizontal plane
  local target_height = math.ceil(vim.o.lines * 0.28)
  vim.cmd('botright ' .. target_height .. 'split')
  local new_win = vim.api.nvim_get_current_win()

  -- 5. REUSE RUNNING STREAM OR GENERATE A FRESH TERMINAL PROCESS
  if target_buf and vim.api.nvim_buf_is_valid(target_buf) then
    vim.api.nvim_win_set_buf(new_win, target_buf)
  else
    vim.cmd('terminal')
    target_buf = vim.api.nvim_get_current_buf()
    if terminal_type == 'monitor' then
      pio_mon_buf = target_buf
    else
      pio_cli_buf = target_buf
    end
  end

  -- 6. THE GRID RE-ANCHOR HOOK:
  -- Forces the terminal pane out of local parent columns and flattens it across
  -- the bottom of your entire monitor underneath Neo-tree, your code file, and Aerial!
  vim.schedule(function()
    if vim.api.nvim_win_is_valid(new_win) then
      vim.api.nvim_win_call(new_win, function()
        vim.cmd('wincmd J')
      end)
      -- Hardlocks the height so sidebars are forbidden from resizing or shifting it
      vim.api.nvim_set_option_value('winfixheight', true, { scope = 'local', win = new_win })
    end
  end)

  -- 7. CLEAN LAYOUT FRAMEWORK STYLING
  vim.cmd('setlocal nonumber norelativenumber signcolumn=no')
  local hl = { bg = '#80a3d4', fg = '#000000' }
  vim.api.nvim_set_hl(0, 'MyWinBar', { bg = hl.bg, fg = hl.fg })
  local title = (terminal_type == 'monitor') and 'Pio Monitor' or 'Pio CLI>'
  local winBartitle = '%#MyWinBar# ' .. title .. ' [Press q to hide]%*'
  vim.api.nvim_set_option_value('winbar', winBartitle, { scope = 'local', win = new_win })

  -- 8. LOCAL KEYMAPS BOUND DIRECTLY TO THIS INSTANCE BUFFER
  -- <Esc> drops out of raw input mode, and 'q' safely executes the closure sequence
  vim.keymap.set('t', '<Esc>', [[<C-\><C-n>]], { buffer = target_buf })
  vim.keymap.set('n', 'q', function()
    SafeCloseTerminal(target_buf)
  end, { buffer = target_buf })

  -- Automatically run passed command strings via your platformio utilities callback strings
  if command and command ~= '' then
    local job_id = vim.b[target_buf].terminal_job_id
    if job_id then
      vim.fn.chansend(job_id, command .. (vim.fn.has('win32') == 1 and '\r\n' or '\n'))
    end
  end

  -- Automatically trigger input focus mode inside the terminal right away
  vim.cmd('startinsert')
end

return M
