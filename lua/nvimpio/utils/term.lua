local M = {}

-- Memory trackers for your two persistent plugin terminal buffers
local pio_cli_buf = nil
local pio_mon_buf = nil

----------------------------------------------------------------------------------------
-- INFO: Safe terminal exit routine (Tied to pressing 'q' inside normal mode)
local function SafeCloseTerminal(buf_id)
  if buf_id and vim.api.nvim_buf_is_valid(buf_id) then
    local win_id = vim.fn.bufwinid(buf_id)
    if win_id and win_id ~= -1 and vim.api.nvim_win_is_valid(win_id) then
      vim.api.nvim_win_close(win_id, true)
      -- Equalize other windows to reclaim the vertical space cleanly when closed
      vim.cmd('wincmd =')
    end
  end
end

----------------------------------------------------------------------------------------
-- INFO: Unified Full-Width Bottom Terminal Spawner (Pure Split Architecture)
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

  -- Determine target buffer context arrays
  local target_buf = (terminal_type == 'monitor') and pio_mon_buf or pio_cli_buf
  local other_buf = (terminal_type == 'monitor') and pio_cli_buf or pio_mon_buf

  -- 2. MUTUAL EXCLUSION: If the opponent window is currently open, hide it first
  if other_buf and vim.api.nvim_buf_is_valid(other_buf) then
    local other_win = vim.fn.bufwinid(other_buf)
    if other_win and other_win ~= -1 and vim.api.nvim_win_is_valid(other_win) then
      vim.api.nvim_win_close(other_win, true)
    end
  end

  -- 3. TOGGLE ACTION: If our target terminal window is already open on screen, close it
  if target_buf and vim.api.nvim_buf_is_valid(target_buf) then
    local target_win = vim.fn.bufwinid(target_buf)
    if target_win and target_win ~= -1 and vim.api.nvim_win_is_valid(target_win) then
      vim.api.nvim_win_close(target_win, true)
      vim.cmd('wincmd =')
      return
    end
  end

  -- 4. FIXED LAYOUT MECHANIC: Initialize a native horizontal split pane at the bottom edge.
  -- 'botright split' cuts Neovim's layout tree at the root screen layer, forcing it to span
  -- 100% horizontally underneath BOTH code windows AND sidebars (Aerial/Neo-tree).
  local target_height = math.ceil(vim.o.lines * 0.28)
  vim.cmd('botright ' .. target_height .. 'split')
  local new_win = vim.api.nvim_get_current_win()

  -- 5. BUFFER COUPLING OR PROCESS INITIALIZATION
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

  -- 6. HARD-LOCK LAYOUT PROPERTIES
  -- Set style options and tell Neovim that your terminal window size is rigid
  vim.cmd('setlocal nonumber norelativenumber signcolumn=no')
  vim.api.nvim_set_option_value('winfixheight', true, { scope = 'local', win = new_win })

  -- 7. THE AUTOMATED LAYOUT PRESERVER GUARD
  -- This autocmd watches the whole Neovim session. The exact millisecond any sidebar (like Aerial)
  -- opens and tries to distort the window tree, this loop flattens the terminal back to the bottom
  -- row, re-adjusts the code panels above it, and instantly returns user cursor focus.
  local platformio_group = vim.api.nvim_create_augroup('PioGuard_' .. target_buf, { clear = true })
  vim.api.nvim_create_autocmd({ 'WinNew', 'BufWinEnter' }, {
    group = platformio_group,
    callback = function()
      local term_win = vim.fn.bufwinid(target_buf)
      if term_win and term_win ~= -1 and vim.api.nvim_win_is_valid(term_win) then
        vim.schedule(function()
          if vim.api.nvim_win_is_valid(term_win) then
            local cur_win = vim.api.nvim_get_current_win()
            vim.api.nvim_set_current_win(term_win)

            vim.cmd('wincmd J') -- Flatten back across the bottom row safely
            vim.cmd('wincmd =') -- Auto-resize code windows above it so no text is hidden!

            if cur_win and vim.api.nvim_win_is_valid(cur_win) then
              vim.api.nvim_set_current_win(cur_win)
            end
          end
        end)
      end
    end,
  })

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
    SafeCloseTerminal(target_buf)
  end, { buffer = target_buf })

  -- Escape path out of the terminal pane back UP to code files without crashes
  vim.keymap.set({ 'n', 't' }, '<C-k>', function()
    if vim.api.nvim_get_mode().mode == 't' then
      local esc = vim.api.nvim_replace_termcodes([[<C-\><C-n>]], true, true, true)
      vim.api.nvim_feedkeys(esc, 'n', false)
    end
    vim.schedule(function()
      vim.cmd('wincmd k')
    end)
  end, { buffer = target_buf, silent = true })

  -- HOME-ROW CROSS SWITCHER: Double tap semi-colon (;;) to swap panels instantly!
  vim.keymap.set({ 'n', 't' }, ';;', function()
    if vim.api.nvim_get_mode().mode == 't' then
      local esc = vim.api.nvim_replace_termcodes([[<C-\><C-n>]], true, true, true)
      vim.api.nvim_feedkeys(esc, 'n', false)
    end

    local next_type = (terminal_type == 'monitor') and 'cli' or 'monitor'
    local next_win = (next_type == 'monitor') and pio_mon_buf or pio_cli_buf

    vim.schedule(function()
      local next_win_id = next_win and vim.fn.bufwinid(next_win) or -1
      if next_win_id ~= -1 and vim.api.nvim_win_is_valid(next_win_id) then
        vim.api.nvim_set_current_win(next_win_id)
        vim.cmd('startinsert')
      else
        M.ToggleTerminal('', next_type)
      end
    end)
  end, { buffer = target_buf, silent = true, desc = 'Switch between PlatformIO terminals' })

  -----------------------------------------------------------------------------
  -- GLOBAL NAVIGATION & RECALL SHORTCUTS
  -----------------------------------------------------------------------------
  vim.keymap.set('n', '<C-h>', '<C-w>h')
  vim.keymap.set('n', '<C-l>', '<C-w>l')

  -- Intercepts Ctrl-J everywhere and drops cursor directly into this active terminal split row
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

  -- Clean out cleanup pass handlers when terminal exits
  vim.api.nvim_create_autocmd('BufUnload', {
    group = platformio_group,
    buffer = target_buf,
    callback = function()
      pcall(vim.api.nvim_clear_autocmds, { group = 'PioGuard_' .. target_buf })
    end,
  })

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
