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
      vim.cmd('wincmd =')
    end
  end
end

----------------------------------------------------------------------------------------
-- INFO: Unified Full-Width Bottom Terminal Spawner (Pure Native Engine)
function M.ToggleTerminal(command, terminal_type)
  -- 1. FIXED LOGIC CORE: Normalize the target strings immediately at the top
  -- This fixes the bug where recalling an active terminal printed the old cached title
  local title = ''
  if terminal_type == 'monitor' or (command and string.find(command, ' monitor')) then
    title = 'Pio Monitor'
    terminal_type = 'monitor'
  else
    title = 'Pio CLI>'
    terminal_type = 'cli'
  end

  -- 2. Determine target buffer context arrays
  local target_buf = (terminal_type == 'monitor') and pio_mon_buf or pio_cli_buf
  local other_buf = (terminal_type == 'monitor') and pio_cli_buf or pio_mon_buf

  -- 3. MUTUAL EXCLUSION: If the opponent window is currently open, hide it first
  if other_buf and vim.api.nvim_buf_is_valid(other_buf) then
    local other_win = vim.fn.bufwinid(other_buf)
    if other_win and other_win ~= -1 and vim.api.nvim_win_is_valid(other_win) then
      vim.api.nvim_win_close(other_win, true)
    end
  end

  -- 4. TOGGLE ACTION: If our target terminal window is already open on screen, close it
  if target_buf and vim.api.nvim_buf_is_valid(target_buf) then
    local target_win = vim.fn.bufwinid(target_buf)
    if target_win and target_win ~= -1 and vim.api.nvim_win_is_valid(target_win) then
      vim.api.nvim_win_close(target_win, true)
      vim.cmd('wincmd =')
      return
    end
  end

  -- 5. SPAWN STRATEGY: Initialize a native window pane layout at the bottom edge
  local target_height = math.ceil(vim.o.lines * 0.28)
  vim.cmd('botright ' .. target_height .. 'split')
  local new_win = vim.api.nvim_get_current_win()

  -- 6. BUFFER COUPLING OR PROCESS INITIALIZATION
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

  -- 7. HARD-LOCK LAYOUT PROPERTIES
  vim.cmd('setlocal nonumber norelativenumber signcolumn=no')
  vim.api.nvim_set_option_value('winfixheight', true, { scope = 'local', win = new_win })

  -- 8. THE BUFFER OVERWRITE GUARD
  -- If a user hits a file inside neo-tree/aerial while focus is here, this interceptor
  -- kicks the incoming code file up to the main pane and preserves your terminal at the bottom.
  local platformio_group = vim.api.nvim_create_augroup('PioGuard_' .. target_buf, { clear = true })
  vim.api.nvim_create_autocmd('BufLeave', {
    group = platformio_group,
    buffer = target_buf,
    callback = function()
      vim.schedule(function()
        local win_id = vim.fn.bufwinid(target_buf)
        if win_id and win_id ~= -1 and vim.api.nvim_win_is_valid(win_id) then
          local current_buf = vim.api.nvim_win_get_buf(win_id)
          if current_buf ~= target_buf then
            local stolen_file_buf = current_buf
            vim.api.nvim_win_set_buf(win_id, target_buf)

            local cur_win = vim.api.nvim_get_current_win()
            vim.cmd('wincmd k')
            vim.api.nvim_set_current_buf(stolen_file_buf)
            vim.api.nvim_set_current_win(cur_win)
          end
        end
      end)
    end,
  })

  -- 9. THE GRID RE-ANCHOR HOOK
  vim.schedule(function()
    if vim.api.nvim_win_is_valid(new_win) then
      vim.api.nvim_win_call(new_win, function()
        vim.cmd('wincmd J')
      end)
    end
  end)

  -- 10. VISUAL STYLING AND FIXED WINBAR HEADER
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

  -- Escape path out of the terminal pane back UP to code workspace files without crashes
  vim.keymap.set({ 'n', 't' }, '<C-k>', function()
    if vim.api.nvim_get_mode().mode == 't' then
      local esc = vim.api.nvim_replace_termcodes([[<C-\><C-n>]], true, true, true)
      vim.api.nvim_feedkeys(esc, 'n', false)
    end
    vim.schedule(function()
      vim.cmd('wincmd k')
    end)
  end, { buffer = target_buf, silent = true })

  -----------------------------------------------------------------------------
  -- GLOBAL RECALL KEYS (Re-bound with block string text brackets to avoid escape typos)
  -----------------------------------------------------------------------------
  vim.keymap.set('n', '<C-h>', '<C-w>h')
  vim.keymap.set('n', '<C-l>', '<C-w>l')

  -- Intercepts Ctrl-J everywhere and drops cursor directly into our active terminal row split
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
