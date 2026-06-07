local M = {}

-- Background tracking slots for running buffers and window handles
local pio_cli_buf = nil
local pio_mon_buf = nil
local pio_cli_win = nil
local pio_mon_win = nil
local last_active_editor_win = nil

-- Memory slots to track active job channel IDs for clean input sending
local pio_cli_chan = nil
local pio_mon_chan = nil

----------------------------------------------------------------------------------------
-- SAFELY ESCAPE SIDEBARS: Finds a normal code window to preserve layout geometry
local function find_valid_editor_window()
  local wins = vim.api.nvim_tabpage_list_wins(0)
  for _, win in ipairs(wins) do
    if vim.api.nvim_win_is_valid(win) and win ~= pio_cli_win and win ~= pio_mon_win then
      local buf = vim.api.nvim_win_get_buf(win)
      local ft = vim.api.nvim_get_option_value('filetype', { buf = buf })
      local bt = vim.api.nvim_get_option_value('buftype', { buf = buf })
      if ft ~= 'neo-tree' and ft ~= 'aerial' and bt ~= 'terminal' and bt ~= 'nofile' then
        return win
      end
    end
  end
  return nil
end

----------------------------------------------------------------------------------------
-- CLEAN EXIT LOGIC: Closes structural split viewports cleanly and restores focus
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
-- CORE STRUCTURAL RUNNER
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

  -- 1. MUTUAL EXCLUSION: Close opposition split instantly
  if other_win and vim.api.nvim_win_is_valid(other_win) then
    vim.api.nvim_win_close(other_win, true)
    if terminal_type == 'monitor' then
      pio_cli_win = nil
    else
      pio_mon_win = nil
    end
  end

  -- 2. TOGGLE LOGIC: If split panel is currently open, hide it
  if target_win and vim.api.nvim_win_is_valid(target_win) then
    HideTerminalWindow(terminal_type)
    return
  end

  -- 3. MODERN UNLISTED INTERACTIVE PTY TERMINAL (DEPRECATION FREE)
  if not target_buf or not vim.api.nvim_buf_is_valid(target_buf) then
    target_buf = vim.api.nvim_create_buf(false, true)
    if terminal_type == 'monitor' then
      pio_mon_buf = target_buf
    else
      pio_cli_buf = target_buf
    end

    local term_chan_id = vim.api.nvim_open_term(target_buf, {
      on_input = function(_, _, _, data)
        local active_job = (terminal_type == 'monitor') and pio_mon_chan or pio_cli_chan
        if active_job then
          vim.api.nvim_chan_send(active_job, data)
        end
      end,
    })

    local shell_cmd = { vim.o.shell }
    if vim.fn.has('win32') == 1 then
      shell_cmd = { 'powershell.exe', '-NoLogo', '-ExecutionPolicy', 'Bypass' }
    end

    local job_id = vim.fn.jobstart(shell_cmd, {
      pty = true,
      on_stdout = function(_, data)
        if vim.api.nvim_buf_is_valid(target_buf) and data then
          local lines = {}
          for _, line in ipairs(data) do
            local is_garbage = line:find('|| Processing')
              or line:find('--- forcing')
              or line:find('--- Terminal')
              or line:find('--- Available filters')
              or line:find('--- More details')
              or line:find('--- Quit:')

            if not is_garbage then
              table.insert(lines, line)
            end
          end
          if #lines > 0 then
            local output = table.concat(lines, '\r\n')
            vim.api.nvim_chan_send(term_chan_id, output)
          end
        end
      end,
      on_stderr = function(_, data)
        if vim.api.nvim_buf_is_valid(target_buf) and data then
          vim.api.nvim_chan_send(term_chan_id, table.concat(data, '\r\n'))
        end
      end,
      on_exit = function()
        if terminal_type == 'monitor' then
          pio_mon_chan = nil
          pio_mon_buf = nil
        else
          pio_cli_chan = nil
          pio_cli_buf = nil
        end
      end,
    })

    if terminal_type == 'monitor' then
      pio_mon_chan = job_id
    else
      pio_cli_chan = job_id
    end
  end

  -- 4. THE UNBEATABLE BOTTOM PANEL TILE ANCHOR
  local target_height = math.ceil(vim.o.lines * 0.28)

  -- Escape to a neutral code pane context window to execute the split pass cleanly
  local neutral_win = find_valid_editor_window()
  if neutral_win then
    vim.api.nvim_set_current_win(neutral_win)
  end

  vim.cmd('new')
  local new_win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(new_win, target_buf)

  -- Force layout container to stretch edge-to-edge horizontally along the bottom row
  vim.cmd('wincmd J')
  vim.api.nvim_win_set_height(new_win, target_height)

  if terminal_type == 'monitor' then
    pio_mon_win = new_win
  else
    pio_cli_win = new_win
  end

  -- 5. WINDOW PANE DECORATIONS
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

  vim.keymap.set({ 'n', 't' }, '<C-k>', function()
    if vim.api.nvim_get_mode().mode == 't' then
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes([[<C-\><C-n>]], true, true, true), 'n', false)
    end
    vim.schedule(function()
      local target = find_valid_editor_window() or last_active_editor_win
      if target and vim.api.nvim_win_is_valid(target) then
        vim.api.nvim_set_current_win(target)
      else
        vim.cmd('wincmd k')
      end
    end)
  end, { buffer = target_buf, silent = true })

  vim.keymap.set({ 'n', 't' }, ';;', function()
    if vim.api.nvim_get_mode().mode == 't' then
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes([[<C-\><C-n>]], true, true, true), 'n', false)
    end
    local next_type = (terminal_type == 'monitor') and 'cli' or 'monitor'
    vim.schedule(function()
      M.ToggleTerminal('', next_type)
    end)
  end, { buffer = target_buf, silent = true })

  -- 7. EXECUTE COMMAND STRING IF PRESENT
  if command and command ~= '' then
    local active_chan = (terminal_type == 'monitor') and pio_mon_chan or pio_cli_chan
    if active_chan then
      vim.api.nvim_chan_send(active_chan, command .. '\r\n')
    end
  end

  vim.cmd('startinsert')
end

----------------------------------------------------------------------------------------
-- 🛡️ THE UNBREAKABLE WINDOW INTERCEPTOR AUTOCMAND SHIELD
----------------------------------------------------------------------------------------
local layout_shield_group = vim.api.nvim_create_augroup('PioTerminalLayoutShield', { clear = true })
vim.api.nvim_create_autocmd('WinNew', {
  group = layout_shield_group,
  callback = function()
    vim.schedule(function()
      local cur_win = vim.api.nvim_get_current_win()
      if cur_win == pio_cli_win or cur_win == pio_mon_win then
        local valid_editor = find_valid_editor_window()
        if valid_editor then
          local rogue_buf = vim.api.nvim_win_get_buf(cur_win)
          vim.api.nvim_win_set_buf(valid_editor, rogue_buf)
          vim.api.nvim_set_current_win(valid_editor)
          vim.api.nvim_win_close(cur_win, true)

          local active_term_win = pio_cli_win or pio_mon_win
          local target_height = math.ceil(vim.o.lines * 0.28)
          if active_term_win and vim.api.nvim_win_is_valid(active_term_win) then
            vim.api.nvim_win_set_height(active_term_win, target_height)
          end
        end
      end
    end)
  end,
})

----------------------------------------------------------------------------------------
-- 🥇 CLEAN OUT-OF-THE-BOX GLOBAL SHORTCUT INITIALIZATIONS
----------------------------------------------------------------------------------------
vim.keymap.set('n', '<C-h>', '<C-w>h', { silent = true })
vim.keymap.set('n', '<C-l>', '<C-w>l', { silent = true })

-- SMART DOWNWARD ACCELERATOR MAP: Focused cursor navigation straight to active panel
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

-- LEADER BACKSLASH HOTKEYS: Fixed tracking pointers for instant spawns
vim.keymap.set('n', [[<leader>\gm]], function()
  M.ToggleTerminal('', 'monitor')
end, { silent = true })
vim.keymap.set('n', [[\t]], function()
  M.ToggleTerminal('', 'cli')
end, { silent = true })

return M
