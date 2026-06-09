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
  shell = OS.is_win and {
    'pwsh.exe',
    '-NoExit',
    '-NoLogo',
    '-NoProfile',
    '-ExecutionPolicy',
    'Bypass',
    '-Command',
    '[Console]::InputEncoding=[Console]::OutputEncoding=[System.Text.Encoding]::UTF8;',
  } or (function()
    local default_shell = vim.api.nvim_get_option_value('shell', {})
    -- If the Mac user defaults to zsh, pass the -f flag to bypass profile script leaks
    if default_shell:find('zsh') then
      return { default_shell, '-f' }
    end
    return default_shell
  end)(),
}

M.stdout_callback = nil
M.exit_callback = nil

M.pio_buffer = ''
M.content = ''

-- The Immutable Global State Registry Core Matrix
local state = {
  cli = { buf = nil, win = nil, job_id = nil, instance = nil, title = ' Pio CLI> ' },
  monitor = { buf = nil, win = nil, job_id = nil, instance = nil, title = ' Pio Monitor ' },
}

----------------------------------------------------------------------------------------
-- 🌟 RIGID SINGLETON TERMINAL CLASS ARCHITECTURE
----------------------------------------------------------------------------------------
---@class Terminal
---@field type string The type of terminal instance ('cli' or 'monitor')
---@field newline string Pre-cached row delimiter row ends
local Terminal = {}
Terminal.__index = Terminal

---Constructor: Enforces strict structural isolation and data field validation
---@param term_type string The target engine lane selection ('cli' or 'monitor')
---@return Terminal
function Terminal.new(term_type)
  local self = setmetatable({}, Terminal)
  self.type = term_type
  self.newline = OS.newline
  return self
end

---Rigid Method 1: Send a string command text string directly with carriage return guards
---@param command string The instruction text payload line to pipe down the channel
function Terminal:send(command)
  local s = state[self.type]
  if not s or not s.job_id or s.job_id <= 0 then
    return
  end
  local cmd_str = tostring(command or '')

  -- CARRIAGE RETURN GUARD: Smash out of any accidental multi-line input locks instantly!
  if cmd_str ~= '' then
    vim.fn.chansend(s.job_id, self.newline)
  end
  vim.fn.chansend(s.job_id, cmd_str .. self.newline)
end

---Rigid Method 2: Gracefully stop background job and tear down split windows safely
function Terminal:close()
  local s = state[self.type]
  if not s or not s.job_id or s.job_id <= 0 then
    return
  end
  pcall(vim.fn.jobstop, s.job_id)

  if s.win and vim.api.nvim_win_is_valid(s.win) then
    vim.api.nvim_win_close(s.win, true)
  end
  s.win = nil
  s.buf = nil
  s.job_id = nil
  s.instance = nil -- Flush singleton reference on full process death block

  vim.schedule(function()
    vim.cmd('wincmd =')
    M.UpdateWinbarTitles()
  end)
end

---Rigid Method 3: Pure Hide Pass - Closes the split window layout viewport panel cleanly
function Terminal:hide()
  local s = state[self.type]
  if s and s.win and vim.api.nvim_win_is_valid(s.win) then
    vim.api.nvim_win_close(s.win, true)
  end
  if s then
    s.win = nil
  end
  vim.schedule(function()
    vim.cmd('wincmd =')
    M.UpdateWinbarTitles()
  end)
end

---Rigid Method 4: Pure Show Pass - Re-splits open the bottom panel row layout instantly
---@return boolean # True if the split window canvas layout was drawn successfully
function Terminal:show()
  local s = state[self.type]
  if not s or not s.buf or not vim.api.nvim_buf_is_valid(s.buf) then
    return false
  end

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

---Rigid Method 5: Clear console screen prompt clean natively across platforms
function Terminal:clear()
  local clear_cmd = OS.is_win and 'Clear-Host' or 'clear'
  self:send(clear_cmd)
end

---Rigid Method 6: Fetch raw underlying buffer handle pointer index
---@return number|nil
function Terminal:get_buf()
  return state[self.type].buf
end

---Rigid Method 7: Fetch raw underlying window split handle pointer index
---@return number|nil
function Terminal:get_win()
  return state[self.type].win
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
  end

  -- Step 3: Always Open Target View Recycle Pass
  if IsTerminalWindowOpen(terminal_type) then
    local current = state[terminal_type]
    vim.api.nvim_set_current_win(current.win)

    local target_h = math.ceil(vim.o.lines * M.config.panel_height)
    pcall(vim.api.nvim_win_set_height, current.win, target_h)

    if command and command ~= '' then
      if current.job_id and current.job_id > 0 then
        vim.fn.chansend(current.job_id, command .. OS.newline)
      end
    end

    -- 🌟 RIGID RETRIEVAL: Returns the single, permanent instance. 0% duplication risk!
    return (terminal_type == 'cli') and current.instance or nil
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
    current.job_id = spawned_job_id

    -- 🌟 RIGID SPAWN: Instantiates the class EXACTLY ONCE on channel initialization pass!
    current.instance = Terminal.new(terminal_type)

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

  if command and command ~= '' then
    if current.job_id then
      vim.fn.chansend(current.job_id, command .. OS.newline)
    end
  end

  -- 🌟 RIGID ASSIGNMENT: Delivers the single immutable class instance safely
  return (terminal_type == 'cli') and current.instance or nil
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
