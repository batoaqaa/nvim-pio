local M = {}

local pio_cli_buf = nil
local pio_mon_buf = nil
local pio_cli_win = nil
local pio_mon_win = nil
local last_active_editor_win = nil
local pio_cli_chan = nil
local pio_mon_chan = nil

local function get_target_height()
  return math.ceil(vim.o.lines * 0.28)
end

local function HideTerminalWindow(terminal_type)
  local win_id = (terminal_type == 'monitor') and pio_mon_win or pio_cli_win

  -- FALLBACK: Scan all visible windows if the tracker variable is out of sync
  if not win_id or not vim.api.nvim_win_is_valid(win_id) then
    local target_buf = (terminal_type == 'monitor') and pio_mon_buf or pio_cli_buf
    for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
      if vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) == target_buf then
        win_id = win
        break
      end
    end
  end

  if win_id and vim.api.nvim_win_is_valid(win_id) then
    local safe_target_win = nil
    if last_active_editor_win and vim.api.nvim_win_is_valid(last_active_editor_win) and last_active_editor_win ~= win_id then
      local buf = vim.api.nvim_win_get_buf(last_active_editor_win)
      if vim.bo[buf].filetype ~= 'neo-tree' and vim.bo[buf].filetype ~= 'aerial' then
        safe_target_win = last_active_editor_win
      end
    end

    if not safe_target_win then
      for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
        if win ~= win_id and vim.api.nvim_win_is_valid(win) then
          local buf = vim.api.nvim_win_get_buf(win)
          if vim.bo[buf].filetype ~= 'neo-tree' and vim.bo[buf].filetype ~= 'aerial' and vim.bo[buf].buftype == '' then
            safe_target_win = win
            break
          end
        end
      end
    end

    if safe_target_win then
      vim.api.nvim_set_current_win(safe_target_win)
    end

    vim.api.nvim_set_option_value('winfixbuf', false, { scope = 'local', win = win_id })
    vim.api.nvim_win_close(win_id, true)
  end

  if terminal_type == 'monitor' then
    pio_mon_win = nil
  else
    pio_cli_win = nil
  end
end

function M.ToggleTerminal(command, terminal_type)
  local active_win = vim.api.nvim_get_current_win()
  if active_win ~= pio_cli_win and active_win ~= pio_mon_win then
    last_active_editor_win = active_win
  end

  if terminal_type == 'monitor' or (command and string.find(command, ' monitor')) then
    terminal_type = 'monitor'
  else
    terminal_type = 'cli'
  end

  -- 🔥 FIX: Pre-emptively scan open windows to catch terminals and sync tracking registers
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.api.nvim_win_is_valid(win) then
      local b = vim.api.nvim_win_get_buf(win)
      if b == pio_cli_buf then
        pio_cli_win = win
      end
      if b == pio_mon_buf then
        pio_mon_win = win
      end
    end
  end

  local target_win = (terminal_type == 'monitor') and pio_mon_win or pio_cli_win
  local other_win = (terminal_type == 'monitor') and pio_cli_win or pio_mon_win
  local target_buf = (terminal_type == 'monitor') and pio_mon_buf or pio_cli_buf

  if other_win and vim.api.nvim_win_is_valid(other_win) then
    local other_type = (terminal_type == 'monitor') and 'cli' or 'monitor'
    HideTerminalWindow(other_type)
  end

  if target_win and vim.api.nvim_win_is_valid(target_win) then
    HideTerminalWindow(terminal_type)
    return
  end

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

    local shell_cmd = vim.fn.has('win32') == 1 and { 'powershell.exe', '-NoLogo', '-ExecutionPolicy', 'Bypass' } or { vim.o.shell }
    local job_id = vim.fn.jobstart(shell_cmd, {
      pty = true,
      on_stdout = function(_, data)
        if vim.api.nvim_buf_is_valid(target_buf) and data then
          local lines = {}
          for _, line in ipairs(data) do
            if not (line:find('|| Processing') or line:find('--- forcing') or line:find('--- Terminal')) then
              table.insert(lines, line)
            end
          end
          if #lines > 0 then
            vim.api.nvim_chan_send(term_chan_id, table.concat(lines, '\r\n'))
          end
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

  local prev_win = vim.api.nvim_get_current_win()

  local old_splitbelow = vim.o.splitbelow
  vim.o.splitbelow = true

  local new_win = vim.api.nvim_open_win(target_buf, true, {
    split = 'below',
    win = 0,
    height = get_target_height(),
  })

  vim.o.splitbelow = old_splitbelow

  if terminal_type == 'monitor' then
    pio_mon_win = new_win
  else
    pio_cli_win = new_win
  end

  vim.cmd('setlocal nonumber norelativenumber signcolumn=no')
  vim.api.nvim_set_option_value('winfixheight', true, { scope = 'local', win = new_win })
  vim.api.nvim_set_option_value('winfixbuf', true, { scope = 'local', win = new_win })

  local title = (terminal_type == 'monitor') and 'Pio Monitor' or 'Pio CLI>'
  local hl = { bg = '#80a3d4', fg = '#000000' }
  vim.api.nvim_set_hl(0, 'MyWinBar', { bg = hl.bg, fg = '#000000' })
  local winBartitle = '%#MyWinBar# ' .. title .. ' [Press ;; to Switch | Press q to hide]%*'
  vim.api.nvim_set_option_value('winbar', winBartitle, { scope = 'local', win = new_win })

  if prev_win and vim.api.nvim_win_is_valid(prev_win) and prev_win ~= new_win then
    vim.api.nvim_set_current_win(prev_win)
  end

  vim.keymap.set('t', '<Esc>', [[<C-\><C-n>]], { buffer = target_buf })
  vim.keymap.set('n', 'q', function()
    HideTerminalWindow(terminal_type)
  end, { buffer = target_buf })
  vim.keymap.set({ 'n', 't' }, '<C-k>', function()
    if vim.api.nvim_get_mode().mode == 't' then
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes([[<C-\><C-n>]], true, true, true), 'n', false)
    end
    vim.schedule(function()
      vim.cmd('wincmd k')
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

  if command and command ~= '' then
    local active_chan = (terminal_type == 'monitor') and pio_mon_chan or pio_cli_chan
    if active_chan then
      vim.api.nvim_chan_send(active_chan, command .. '\r\n')
    end
  end

  vim.cmd('startinsert')
end

vim.keymap.set('n', '<C-h>', '<C-w>h', { silent = true })
vim.keymap.set('n', '<C-l>', '<C-w>l', { silent = true })

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
