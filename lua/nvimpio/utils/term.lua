local M = {}

-- Background tracking slots for running buffers and window handles
local pio_cli_buf = nil
local pio_mon_buf = nil
local pio_cli_win = nil
local pio_mon_win = nil
local last_active_editor_win = nil

----------------------------------------------------------------------------------------
-- CLEAN EXIT LOGIC: Destroys window frame handles and restores focus
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

  if last_active_editor_win and vim.api.nvim_win_is_valid(last_active_editor_win) then
    vim.api.nvim_set_current_win(last_active_editor_win)
  end
end

----------------------------------------------------------------------------------------
-- CORE PERSISTENT RUNNER
function M.ToggleTerminal(command, terminal_type)
  local active_win = vim.api.nvim_get_current_win()
  if active_win ~= pio_cli_win and active_win ~= pio_mon_win then
    last_active_editor_win = active_win
  end

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

  -- 1. MUTUAL EXCLUSION: Close opposition overlay instantly
  if other_win and vim.api.nvim_win_is_valid(other_win) then
    vim.api.nvim_win_close(other_win, true)
    if terminal_type == 'monitor' then
      pio_cli_win = nil
    else
      pio_mon_win = nil
    end
  end

  -- 2. TOGGLE LOGIC: If window is currently open, hide it
  if target_win and vim.api.nvim_win_is_valid(target_win) then
    HideTerminalWindow(terminal_type)
    return
  end

  -- 3. MODERN UNLISTED TERMINAL INITIALIZATION (DEPRECATION FREE)
  if not target_buf or not vim.api.nvim_buf_is_valid(target_buf) then
    -- Generate unlisted scratch buffer cleanly
    target_buf = vim.api.nvim_create_buf(false, true)
    if terminal_type == 'monitor' then
      pio_mon_buf = target_buf
    else
      pio_cli_buf = target_buf
    end

    -- Build command execution format based on operating system
    local cmd_str = command or vim.o.shell
    if command and command ~= '' then
      if vim.fn.has('win32') == 1 then
        cmd_str = string.format('cmd.exe /c "%s && pause"', command)
      else
        cmd_str = string.format('%s -c "%s; echo; read -p \'Press enter to exit...\'"', vim.o.shell, command)
      end
    end

    -- Run modern background job spawn wrapped cleanly inside the target buffer context
    vim.api.nvim_buf_call(target_buf, function()
      -- vim.cmd.terminal launches a full PTY streaming session natively on the buffer
      vim.cmd.terminal(cmd_str)

      -- Stop the buffer from auto-wiping on process completion so the compilation log stays readable
      local current_job_id = vim.b.terminal_job_id
      if current_job_id then
        vim.api.nvim_create_autocmd('TermClose', {
          buffer = target_buf,
          callback = function()
            if terminal_type == 'monitor' then
              pio_mon_buf = nil
            else
              pio_cli_buf = nil
            end
          end,
        })
      end
    end)
  end

  -- 4. GEOMETRIC DISPLAY MATHEMATICS
  local target_height = math.ceil(vim.o.lines * 0.28)
  local cmdheight = vim.o.cmdheight or 1
  local win_opts = {
    relative = 'editor',
    style = 'minimal',
    focusable = true,
    width = vim.o.columns,
    height = target_height,
    row = vim.o.lines - target_height - cmdheight - 1,
    col = 0,
  }

  local new_win = vim.api.nvim_open_win(target_buf, true, win_opts)
  if terminal_type == 'monitor' then
    pio_mon_win = new_win
  else
    pio_cli_win = new_win
  end

  -- 5. WINDOW VIEWPORT TWEAKS
  vim.cmd('setlocal nonumber norelativenumber signcolumn=no')
  vim.api.nvim_set_option_value('winfixheight', true, { scope = 'local', win = new_win })

  local hl = { bg = '#80a3d4', fg = '#000000' }
  vim.api.nvim_set_hl(0, 'MyWinBar', { bg = hl.bg, fg = hl.fg })
  local winBartitle = '%#MyWinBar# ' .. title .. ' [Press ;; to Switch | Press q to hide]%*'
  vim.api.nvim_set_option_value('winbar', winBartitle, { scope = 'local', win = new_win })

  -- 6. LOCAL SHORTCUTS BOUND ONLY TO THIS BUFFER
  vim.keymap.set('t', '<Esc>', [[<C-\><C-n>]], { buffer = target_buf })
  vim.keymap.set('n', 'q', function()
    HideTerminalWindow(terminal_type)
  end, { buffer = target_buf })

  -- Escape Floating Viewports safely back to your project file code block
  vim.keymap.set({ 'n', 't' }, '<C-k>', function()
    if vim.api.nvim_get_mode().mode == 't' then
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes([[<C-\><C-n>]], true, true, true), 'n', false)
    end
    vim.schedule(function()
      if last_active_editor_win and vim.api.nvim_win_is_valid(last_active_editor_win) then
        vim.api.nvim_set_current_win(last_active_editor_win)
      end
    end)
  end, { buffer = target_buf, silent = true })

  -- Smart Terminal Toggle
  vim.keymap.set({ 'n', 't' }, ';;', function()
    if vim.api.nvim_get_mode().mode == 't' then
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes([[<C-\><C-n>]], true, true, true), 'n', false)
    end
    local next_type = (terminal_type == 'monitor') and 'cli' or 'monitor'
    vim.schedule(function()
      M.ToggleTerminal('', next_type)
    end)
  end, { buffer = target_buf, silent = true })

  vim.cmd('startinsert')
end

----------------------------------------------------------------------------------------
-- GLOBAL KEYMAP REGISTRY (Saves memory allocations by executing exactly once)
----------------------------------------------------------------------------------------
vim.keymap.set('n', '<C-h>', '<C-w>h')
vim.keymap.set('n', '<C-l>', '<C-w>l')

vim.keymap.set('n', '<C-j>', function()
  if pio_cli_win and vim.api.nvim_win_is_valid(pio_cli_win) then
    vim.api.nvim_set_current_win(pio_cli_win)
    vim.cmd('startinsert')
  elseif pio_mon_win and vim.api.nvim_win_is_valid(pio_mon_win) then
    vim.api.nvim_set_current_win(pio_mon_win)
    vim.cmd('startinsert')
  else
    vim.cmd('wincmd j')
  end
end, { silent = true })

vim.keymap.set('n', [[<leader>\gm]], function()
  M.ToggleTerminal('', 'monitor')
end, { silent = true })
vim.keymap.set('n', [[<leader>\t]], function()
  M.ToggleTerminal('', 'cli')
end, { silent = true })

return M
