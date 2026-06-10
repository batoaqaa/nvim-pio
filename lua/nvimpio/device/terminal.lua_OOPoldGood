local M = {}

-- Static Cross-Platform Environmental Cache Matrix
local OS = {
  is_win = vim.fn.has('win32') == 1,
  eol = vim.fn.has('win32') == 1 and '\r\n' or '\n',
}

-- 1. Default Public User Configuration Matrix
M.config = {
  panel_height = 0.25,
  winbar_bg = '#80a3d4',
  winbar_fg = '#000000',
  shell = OS.is_win and {
    'pwsh.exe',
    '-NoExit',
    '-NoLogo',
    '-NoProfile',
    '-ExecutionPolicy',
    'Bypass',
  } or (function()
    local default_shell = vim.api.nvim_get_option_value('shell', {})
    if default_shell:find('zsh') then
      return { default_shell, '-f' }
    end
    return default_shell
  end)(),
}

M.stdout_callback = nil
M.exit_callback = nil

-- The Absolute Encapsulated State Engine Matrix
local state = {
  cli = { buf = nil, win = nil, job_id = nil, title = ' Pio CLI> ' },
  monitor = { buf = nil, win = nil, job_id = nil, title = ' Pio Monitor ' },
}

local function SafeCloseTerminal(term_type)
  local current_state = state[term_type]
  if not current_state then
    return
  end
  if current_state.win and vim.api.nvim_win_is_valid(current_state.win) then
    vim.api.nvim_win_close(current_state.win, true)
  end
  current_state.win = nil
  vim.schedule(function()
    vim.cmd('wincmd =')
    M.UpdateWinbarTitles()
  end)
end

function M.UpdateWinbarTitles()
  local is_cli_buffer_valid = state.cli.buf and vim.api.nvim_buf_is_valid(state.cli.buf)
  local is_monitor_buffer_valid = state.monitor.buf and vim.api.nvim_buf_is_valid(state.monitor.buf)
  local status_hint_string = (is_cli_buffer_valid and is_monitor_buffer_valid) and ' [;; Switch] ' or ' [; Hide] '

  vim.api.nvim_set_hl(0, 'PioWinBar', { bg = M.config.winbar_bg, fg = M.config.winbar_fg })

  for _, current_lane_type in pairs({ 'cli', 'monitor' }) do
    local current_state = state[current_lane_type]
    if current_state.win and vim.api.nvim_win_is_valid(current_state.win) then
      vim.api.nvim_set_option_value('winbar', '%#PioWinBar#' .. current_state.title .. status_hint_string .. '%*', { scope = 'local', win = current_state.win })
    end
  end
end

----------------------------------------------------------------------------------------
-- 🌟 THE AUTONOMOUS TERMINAL CLASS ARCHITECTURE
----------------------------------------------------------------------------------------
---@class Terminal
---@field type string The type of terminal instance ('cli' or 'monitor')
---@field newline string Pre-cached row delimiter row ends
local Terminal = {}
Terminal.__index = Terminal

function Terminal.new(term_type)
  local self = setmetatable({}, Terminal)
  self.type = term_type
  self.newline = OS.eol
  return self
end

function Terminal:send(command)
  local current_state = state[self.type]
  local command_string = tostring(command or '')

  -- Re-spawns window layout autonomously using your clean class infrastructure
  if not current_state.job_id or current_state.job_id <= 0 or not current_state.win or not vim.api.nvim_win_is_valid(current_state.win) then
    self:show()
  end

  if not current_state.job_id or current_state.job_id <= 0 then
    return
  end
  if command_string ~= '' then
    vim.fn.chansend(current_state.job_id, self.newline)
  end
  vim.fn.chansend(current_state.job_id, command_string .. self.newline)
end

function Terminal:close()
  local current_state = state[self.type]
  if not current_state or not current_state.job_id or current_state.job_id <= 0 then
    return
  end
  pcall(vim.fn.jobstop, current_state.job_id)

  if current_state.win and vim.api.nvim_win_is_valid(current_state.win) then
    vim.api.nvim_win_close(current_state.win, true)
  end
  current_state.win = nil
  current_state.buf = nil
  current_state.job_id = nil

  vim.schedule(function()
    vim.cmd('wincmd =')
    M.UpdateWinbarTitles()
  end)
end

function Terminal:hide()
  local current_state = state[self.type]
  if current_state and current_state.win and vim.api.nvim_win_is_valid(current_state.win) then
    vim.api.nvim_win_close(current_state.win, true)
  end
  if current_state then
    current_state.win = nil
  end
  vim.schedule(function()
    vim.cmd('wincmd =')
    M.UpdateWinbarTitles()
  end)
end

function Terminal:show()
  local current_state = state[self.type]
  local opposite_type = (self.type == 'monitor') and 'cli' or 'monitor'
  local opposite_state = state[opposite_type]

  if opposite_state.win and vim.api.nvim_win_is_valid(opposite_state.win) then
    vim.api.nvim_win_close(opposite_state.win, true)
    opposite_state.win = nil
  end

  if current_state.win and vim.api.nvim_win_is_valid(current_state.win) then
    vim.api.nvim_set_current_win(current_state.win)
    return true
  end

  local is_new_buffer = false
  if not current_state.buf or not vim.api.nvim_buf_is_valid(current_state.buf) then
    current_state.buf = vim.api.nvim_create_buf(false, true)
    is_new_buffer = true
  end

  local calculated_panel_height = math.ceil(vim.o.lines * M.config.panel_height)
  local window_spawn_options = { split = 'below', win = -1, height = calculated_panel_height }
  current_state.win = vim.api.nvim_open_win(current_state.buf, true, window_spawn_options)

  if is_new_buffer then
    local active_channel_id = vim.fn.jobstart(M.config.shell, {
      term = true,
      on_stdout = function(j, d, e)
        if self.type == 'cli' and type(M.stdout_callback) == 'function' then
          M.stdout_callback(j, d, e)
        end
      end,
      on_stderr = function(j, d, e)
        if self.type == 'cli' and type(M.stdout_callback) == 'function' then
          M.stdout_callback(j, d, e)
        end
      end,
      on_exit = function()
        if type(M.exit_callback) == 'function' then
          M.exit_callback()
        end
      end,
    })
    vim.b[current_state.buf].terminal_job_id = active_channel_id
    current_state.job_id = active_channel_id

    if OS.is_win then
      local encoding_initialization_string = '[Console]::InputEncoding=[Console]::OutputEncoding=[System.Text.Encoding]::UTF8; Clear-Host;'
      vim.fn.chansend(active_channel_id, encoding_initialization_string .. OS.eol)
    end

    local autoscroll_event_group = vim.api.nvim_create_augroup('PioAutoScroll_' .. current_state.buf, { clear = true })
    vim.api.nvim_create_autocmd({ 'TextChanged', 'TextChangedI' }, {
      group = autoscroll_event_group,
      buffer = current_state.buf,
      callback = function()
        local active_window_handle = vim.fn.bufwinid(current_state.buf)
        if active_window_handle and active_window_handle ~= -1 and vim.api.nvim_win_is_valid(active_window_handle) then
          vim.schedule(function()
            if vim.api.nvim_win_is_valid(active_window_handle) then
              vim.api.nvim_win_call(active_window_handle, function()
                if vim.api.nvim_get_mode().mode:sub(1, 1) ~= 't' then
                  vim.cmd('normal! G')
                end
              end)
            end
          end)
        end
      end,
    })
  end

  vim.cmd('setlocal nonumber norelativenumber signcolumn=no')
  vim.api.nvim_set_option_value('winfixheight', true, { scope = 'local', win = current_state.win })

  local focus_guard_event_group = vim.api.nvim_create_augroup('PioFocusGuard_' .. current_state.buf, { clear = true })
  vim.api.nvim_create_autocmd('WinEnter', {
    group = focus_guard_event_group,
    buffer = current_state.buf,
    callback = function()
      vim.schedule(function()
        if current_state.win and vim.api.nvim_win_is_valid(current_state.win) then
          pcall(vim.api.nvim_win_set_height, current_state.win, calculated_panel_height)
          if vim.api.nvim_get_mode().mode:sub(1, 1) ~= 't' then
            vim.cmd('normal! G')
          end
        end
      end)
    end,
  })

  M.UpdateWinbarTitles()

  vim.keymap.set('t', '<Esc>', [[<C-\><C-n>]], { buffer = current_state.buf })
  vim.keymap.set('n', 'q', function()
    SafeCloseTerminal(self.type)
  end, { buffer = current_state.buf })

  vim.keymap.set({ 'n', 't' }, '<C-k>', function()
    if vim.api.nvim_get_mode().mode == 't' then
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes([[<C-\><C-n>]], true, true, true), 'n', false)
    end
    vim.schedule(function()
      vim.cmd('wincmd k')
    end)
  end, { buffer = current_state.buf, silent = true })

  -- 🌟 FIXED SCOPE ENCLOSURE: Captures the unique runtime tracks for smooth layout flips
  local captured_lane_type = self.type
  vim.keymap.set({ 'n', 't' }, ';;', function()
    if vim.api.nvim_get_mode().mode == 't' then
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes([[<C-\><C-n>]], true, true, true), 'n', false)
    end
    local current_winbar_option = vim.api.nvim_get_option_value('winbar', { scope = 'local' }) or ''
    if current_winbar_option:find('%[; Hide%]') then
      SafeCloseTerminal(captured_lane_type)
      return
    end
    SafeCloseTerminal(captured_lane_type)
    vim.schedule(function()
      M[opposite_type]:show()
    end)
  end, { buffer = current_state.buf, silent = true })

  vim.keymap.set('n', '<C-h>', '<C-w>h')
  vim.keymap.set('n', '<C-l>', '<C-w>l')
  vim.keymap.set('n', '<C-j>', function()
    vim.schedule(function()
      if current_state.win and vim.api.nvim_win_is_valid(current_state.win) then
        vim.api.nvim_set_current_win(current_state.win)
        pcall(vim.api.nvim_win_set_height, current_state.win, calculated_panel_height)
        if vim.api.nvim_get_mode().mode:sub(1, 1) ~= 't' then
          vim.cmd('normal! G')
        end
      else
        vim.cmd('wincmd j')
      end
    end)
  end, { silent = true })

  if is_new_buffer then
    vim.cmd('startinsert')
  end
  return true
end

function Terminal:clear()
  local system_clear_command = OS.is_win and 'Clear-Host' or 'clear'
  self:send(system_clear_command)
end

function Terminal:get_buf()
  return state[self.type].buf
end
function Terminal:get_win()
  return state[self.type].win
end

---@type Terminal
M.cli = Terminal.new('cli')
---@type Terminal
M.monitor = Terminal.new('monitor')

vim.keymap.set('n', [[<leader>\gm]], function()
  M.monitor:show()
  M.monitor:send('pio device monitor')
end, { silent = true })
vim.keymap.set('n', [[<leader>\t]], function()
  M.cli:show()
end, { silent = true })

function M.setup(user_configuration_options)
  M.config = vim.tbl_deep_extend('force', M.config, user_configuration_options or {})
end

return M
