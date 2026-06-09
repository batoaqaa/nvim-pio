local M = {}

-- Immutable Platform Capabilities Caching Engine
local OS = {
  is_win = OS.is_win,
  newline = OS.eol,
}

-- 1. Default Public User Configuration Matrix
M.config = {
  panel_height = 0.25,
  winbar_bg = '#80a3d4',
  winbar_fg = '#000000',
  shell = OS.is_win and 'powershell.exe' or vim.api.nvim_get_option_value('shell', {}),
}

-- Bound and assigned dynamically at any time by your external sub-modules
M.stdout_callback = nil
M.exit_callback = nil

-- Unified Text History Stream Cache Registers
M.pio_buffer = ''
M.content = ''

-- The Absolute Encapsulated State Engine Matrix
local state = {
  cli = { buf = nil, win = nil, title = ' Pio CLI> ' },
  monitor = { buf = nil, win = nil, title = ' Pio Monitor ' },
}

----------------------------------------------------------------------------------------
-- 🌟 THE TERMINAL CLASS DEFINITION (PROTOTYPE ARCHITECTURE)
----------------------------------------------------------------------------------------
---@class Terminal
---@field job_id number The unique operating system process channel ID handle
---@field newline string The pre-cached cross-platform row carriage return delimiter
local Terminal = {}
Terminal.__index = Terminal

---Constructor: Instantiates and encapsulates individual channel properties
---@param job_id number The raw channel handle returned by jobstart
---@return Terminal|nil # Returns a new Terminal class instance object, or nil if invalid
function Terminal.new(job_id)
  if not job_id or job_id <= 0 then
    return nil
  end
  local self = setmetatable({}, Terminal)
  self.job_id = job_id
  self.newline = OS.newline
  return self
end

---Send a string command text string directly down the active job channel
---@param command string The shell text instruction payload to execute
function Terminal:send(command)
  if not self.job_id or self.job_id <= 0 then
    return
  end
  vim.fn.chansend(self.job_id, tostring(command or '') .. self.newline)
end

---Gracefully stop the background processing shell job and close visible window splits
function Terminal:close()
  if not self.job_id or self.job_id <= 0 then
    return
  end
  pcall(vim.fn.jobstop, self.job_id)

  for _, s in pairs(state) do
    if s.buf and vim.b[s.buf] and vim.b[s.buf].terminal_job_id == self.job_id then
      if s.win and vim.api.nvim_win_is_valid(s.win) then
        vim.api.nvim_win_close(s.win, true)
      end
      s.win = nil
      s.buf = nil
    end
  end
  self.job_id = -1
  vim.schedule(function()
    vim.cmd('wincmd =')
    M.UpdateWinbarTitles()
  end)
end

---Closes the split window layout viewport panel but preserves the background process job shell alive in cache memory
function Terminal:hide()
  for _, s in pairs(state) do
    if s.buf and vim.b[s.buf] and vim.b[s.buf].terminal_job_id == self.job_id then
      if s.win and vim.api.nvim_win_is_valid(s.win) then
        vim.api.nvim_win_close(s.win, true)
      end
      s.win = nil
    end
  end
  vim.schedule(function()
    vim.cmd('wincmd =')
    M.UpdateWinbarTitles()
  end)
end

---Re-splits open the bottom screen canvas panel instantly and focuses your active terminal prompt session back to view
---@return boolean # Returns true if the window split was successfully shown or refocused
function Terminal:show()
  for _, s in pairs(state) do
    if s.buf and vim.b[s.buf] and vim.b[s.buf].terminal_job_id == self.job_id then
      if s.win and vim.api.nvim_win_is_valid(s.win) then
        vim.api.nvim_set_current_win(s.win)
        return true
      end

      local target_h = math.ceil(vim.o.lines * M.config.panel_height)
      local win_opts = { split = 'below', win = -1, height = target_h }
      s.win = vim.api.nvim_open_win(s.buf, true, win_opts)

      vim.cmd('setlocal nonumber norelativenumber signcolumn=no')
      vim.api.nvim_set_option_value('winfixheight', true, { scope = 'local', win = s.win })

      M.UpdateWinbarTitles()
      vim.cmd('startinsert')
      return true
    end
  end
  return false
end

---Wipes your current console prompt screen completely clean, giving you a pristine empty prompt viewport layout row
function Terminal:clear()
  local clear_cmd = OS.is_win and 'Clear-Host' or 'clear'
  self:send(clear_cmd)
end

---Fetch the raw underlying Neovim buffer handle integer pointer
---@return number|nil # Returns the active buffer ID index value, or nil if closed
function Terminal:get_buf()
  for _, s in pairs(state) do
    if s.buf and vim.b[s.buf] and vim.b[s.buf].terminal_job_id == self.job_id then
      return s.buf
    end
  end
  return nil
end

---Fetch the raw underlying Neovim window split handle integer pointer
---@return number|nil # Returns the active window layout ID index value, or nil if closed
function Terminal:get_win()
  for _, s in pairs(state) do
    if s.buf and vim.b[s.buf] and vim.b[s.buf].terminal_job_id == self.job_id then
      return s.win
    end
  end
  return nil
end
----------------------------------------------------------------------------------------

local function IsTerminalWindowOpen(term_type)
  local s = state[term_type]
  return s.win and vim.api.nvim_win_is_valid(s.win) and vim.api.nvim_win_get_buf(s.win) == s.buf
end

function M.UpdateWinbarTitles()
  local cli_alive = state.cli.buf and vim.api.nvim_buf_is_valid(state.cli.buf)
  local mon_alive = state.monitor.buf and vim.api.nvim_buf_is_valid(state.monitor.buf)
  local hint = (cli_alive and mon_alive) and ' [;; Switch] ' or ' [; Hide] '

  vim.api.nvim_set_hl(0, 'PioWinBar', { bg = M.config.winbar_bg, fg = M.config.winbar_fg })

  for _, t in pairs({ 'cli', 'monitor' }) do
    local s = state[t]
    if s.win and vim.api.nvim_win_is_valid(s.win) then
      vim.api.nvim_set_option_value('winbar', '%#PioWinBar#' .. s.title .. hint .. '%*', { scope = 'local', win = s.win })
    end
  end
end

local function SafeCloseTerminal(term_type)
  local s = state[term_type]
  if s.win and vim.api.nvim_win_is_valid(s.win) then
    vim.api.nvim_win_close(s.win, true)
  end
  s.win = nil
  vim.schedule(function()
    vim.cmd('wincmd =')
    M.UpdateWinbarTitles()
  end)
end

function M.IsTerminalOpen(term_type)
  return IsTerminalWindowOpen(term_type)
end

---Core window layout allocator and partition spawner namespace
---@param command string Initial command payload text instruction to pipe down channel
---@param terminal_type string Layout selection mode profile target ('cli' or 'monitor')
---@return Terminal|nil # Returns a typed OOP Terminal class object handle if calling a CLI lane
function M.PioTerminal(command, terminal_type)
  local cmd_str = tostring(command or '')
  if terminal_type ~= 'monitor' and terminal_type ~= 'cli' then
    terminal_type = cmd_str:find('monitor') and 'monitor' or 'cli'
  end

  local opposite_type = (terminal_type == 'monitor') and 'cli' or 'monitor'

  if IsTerminalWindowOpen(opposite_type) then
    SafeCloseTerminal(opposite_type)
    return M.PioTerminal(command, terminal_type)
  end

  -- Step 3: Always Open Target View Recycle Pass
  if IsTerminalWindowOpen(terminal_type) then
    vim.api.nvim_set_current_win(state[terminal_type].win)
    local target_h = math.ceil(vim.o.lines * M.config.panel_height)
    pcall(vim.api.nvim_win_set_height, state[terminal_type].win, target_h)

    local job_id = vim.b[state[terminal_type].buf].terminal_job_id
    if command and command ~= '' then
      if job_id then
        vim.fn.chansend(job_id, command .. OS.newline)
      end
    end
    return (terminal_type == 'cli') and Terminal.new(job_id) or nil
  end

  -- Step 4: Scratch Buffer Allocation Provision Pass
  local current = state[terminal_type]
  local is_new_buffer = false
  if not current.buf or not vim.api.nvim_buf_is_valid(current.buf) then
    current.buf = vim.api.nvim_create_buf(false, true)
    is_new_buffer = true
  end

  -- Step 5: Screen Split Window Layout Spawner
  local target_h = math.ceil(vim.o.lines * M.config.panel_height)
  local win_opts = { split = 'below', win = -1, height = target_h }
  current.win = vim.api.nvim_open_win(current.buf, true, win_opts)

  if is_new_buffer then
    local spawned_job_id = vim.fn.jobstart(M.config.shell, {
      term = true,
      on_stdout = function(j, d, e)
        if terminal_type == 'cli' and type(M.stdout_callback) == 'function' then
          M.stdout_callback(j, d, e)
        end
      end,
      on_stderr = function(j, d, e)
        if terminal_type == 'cli' and type(M.stdout_callback) == 'function' then
          M.stdout_callback(j, d, e)
        end
      end,
      on_exit = function()
        if type(M.exit_callback) == 'function' then
          M.exit_callback()
        end
      end,
    })
    vim.b[current.buf].terminal_job_id = spawned_job_id

    if OS.is_win then
      local init_enc = '[Console]::InputEncoding=[Console]::OutputEncoding=[System.Text.Encoding]::UTF8; Clear-Host;\r\n'
      vim.fn.chansend(spawned_job_id, init_enc)
    end

    local scroll_group = vim.api.nvim_create_augroup('PioAutoScroll_' .. current.buf, { clear = true })
    vim.api.nvim_create_autocmd({ 'TextChanged', 'TextChangedI' }, {
      group = scroll_group,
      buffer = current.buf,
      callback = function()
        local w = vim.fn.bufwinid(current.buf)
        if w and w ~= -1 and vim.api.nvim_win_is_valid(w) then
          vim.schedule(function()
            if vim.api.nvim_win_is_valid(w) then
              vim.api.nvim_win_call(w, function()
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
  vim.api.nvim_set_option_value('winfixheight', true, { scope = 'local', win = current.win })

  local pio_group = vim.api.nvim_create_augroup('PioFocusGuard_' .. current.buf, { clear = true })
  vim.api.nvim_create_autocmd('WinEnter', {
    group = pio_group,
    buffer = current.buf,
    callback = function()
      vim.schedule(function()
        if IsTerminalWindowOpen(terminal_type) then
          pcall(vim.api.nvim_win_set_height, current.win, target_h)
          if vim.api.nvim_get_mode().mode:sub(1, 1) ~= 't' then
            vim.cmd('normal! G')
          end
        end
      end)
    end,
  })

  M.UpdateWinbarTitles()

  vim.keymap.set('t', '<Esc>', [[<C-\><C-n>]], { buffer = current.buf })
  vim.keymap.set('n', 'q', function()
    SafeCloseTerminal(terminal_type)
  end, { buffer = current.buf })

  vim.keymap.set({ 'n', 't' }, '<C-k>', function()
    if vim.api.nvim_get_mode().mode == 't' then
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes([[<C-\><C-n>]], true, true, true), 'n', false)
    end
    vim.schedule(function()
      vim.cmd('wincmd k')
    end)
  end, { buffer = current.buf, silent = true })

  vim.keymap.set({ 'n', 't' }, ';;', function()
    if vim.api.nvim_get_mode().mode == 't' then
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes([[<C-\><C-n>]], true, true, true), 'n', false)
    end
    local current_winbar = vim.api.nvim_get_option_value('winbar', { scope = 'local' }) or ''
    if current_winbar:find('%[; Hide%]') then
      SafeCloseTerminal(terminal_type)
      return
    end
    SafeCloseTerminal(terminal_type)
    vim.schedule(function()
      M.PioTerminal('', opposite_type)
    end)
  end, { buffer = current.buf, silent = true })

  vim.keymap.set('n', '<C-h>', '<C-w>h')
  vim.keymap.set('n', '<C-l>', '<C-w>l')
  vim.keymap.set('n', '<C-j>', function()
    vim.schedule(function()
      if IsTerminalWindowOpen(terminal_type) then
        vim.api.nvim_set_current_win(current.win)
        pcall(vim.api.nvim_win_set_height, current.win, target_h)
        if vim.api.nvim_get_mode().mode:sub(1, 1) ~= 't' then
          vim.cmd('normal! G')
        end
      else
        vim.cmd('wincmd j')
      end
    end)
  end, { silent = true })

  local final_job_id = vim.b[current.buf].terminal_job_id
  if command and command ~= '' then
    if final_job_id then
      vim.fn.chansend(final_job_id, command .. OS.newline)
    end
  end

  return (terminal_type == 'cli') and Terminal.new(final_job_id) or nil
end

vim.keymap.set('n', [[<leader>\gm]], function()
  M.PioTerminal('pio device monitor', 'monitor')
end, { silent = true })
vim.keymap.set('n', [[<leader>\t]], function()
  M.PioTerminal('', 'cli')
end, { silent = true })

function M.setup(opts)
  M.config = vim.tbl_deep_extend('force', M.config, opts or {})
end

return M
