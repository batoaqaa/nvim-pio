local M = {}

-- Default User Configurations Matrix
M.config = {
  panel_height = 0.2,
  winbar_bg = '#80a3d4',
  winbar_fg = '#000000',
  shell = vim.o.shell,
  keymaps = {
    hide_pane = 'q',
    switch_pane = '<Tab>',
    escape_term = '<Esc>',
    move_up = '<C-k>',
    move_down = '<C-j>',
    move_left = '<C-h>',
    move_right = '<C-l>',
  },
}

M.stdout_callback = nil
M.exit_callback = nil

--- Safe window teardown coordinator
---@param instance Terminal Target object to close down cleanly.
local function SafeCloseTerminal(instance)
  if not instance then
    return
  end

  -- Restore active cursor to the originating code file split before window destruction
  if instance.last_win and vim.api.nvim_win_is_valid(instance.last_win) then
    vim.api.nvim_set_current_win(instance.last_win)
  else
    vim.cmd('wincmd k')
  end

  if instance.win and vim.api.nvim_win_is_valid(instance.win) then
    vim.api.nvim_win_close(instance.win, true)
  end
  instance.win = nil
  instance.last_win = nil

  vim.schedule(function()
    vim.cmd('wincmd =')
    M.UpdateWinbarTitles()
  end)
end

--- Structural Winbar Title Renderer
function M.UpdateWinbarTitles()
  local cli_alive = M.cli.buf and vim.api.nvim_buf_is_valid(M.cli.buf)
  local mon_alive = M.mon.buf and vim.api.nvim_buf_is_valid(M.mon.buf)
  local maps = M.config.keymaps

  local hint = (cli_alive and mon_alive) and string.format('[ %s  Switch;  %s  Hide; :q! Quit ] ', maps.switch_pane, maps.hide_pane)
    or string.format('[ %s  Hide; :q! Quit ] ', maps.hide_pane)

  vim.api.nvim_set_hl(0, 'PioWinBar', { bg = M.config.winbar_bg, fg = M.config.winbar_fg })

  for _, instance in pairs({ M.cli, M.mon }) do
    if instance and instance.win and vim.api.nvim_win_is_valid(instance.win) then
      vim.api.nvim_set_option_value('winbar', '%#PioWinBar#' .. instance.title .. hint .. '%*', { scope = 'local', win = instance.win })
    end
  end
end

----------------------------------------------------------------------------------------
-- OBJECT ORIENTED TERMINAL CLASS ENCAPSULATION
----------------------------------------------------------------------------------------
---@class Terminal
---@field term_type string Tracking tag ('cli' or 'monitor')
---@field title string The visual text drawn on the winbar header
---@field buf number|nil Native Neovim buffer ID handle
---@field win number|nil Native Neovim window ID layout handle
---@field last_win number|nil Originating code split window ID pointer
---@field job number|nil Asynchronous process stream channel ID handle
---@field newline string Pre-cached newline carriage return delimiter
---@field filetype string Fixed text-domain category tracking tag
local Terminal = {
  term_type = '',
  title = '',
  buf = nil,
  win = nil,
  last_win = nil,
  job = nil,
  newline = '\n',
  filetype = 'pio_terminal',
}
Terminal.__index = Terminal

--- Constructor Factory
function Terminal.new(term_type, panel_title)
  local self = setmetatable({}, Terminal)
  self.term_type = term_type
  self.title = panel_title
  return self
end

--- Spawn process channels strictly inside our pre-rendered split window container
function Terminal:_spawn(target_height)
  -- Run termopen natively inside the already allocated window viewport context
  local channel_id = vim.fn.termopen(M.config.shell, {
    on_stdout = function(j, d, e)
      if self.term_type == 'cli' and type(M.stdout_callback) == 'function' then
        M.stdout_callback(j, d, e)
      end
    end,
    on_stderr = function(j, d, e)
      if self.term_type == 'cli' and type(M.stdout_callback) == 'function' then
        M.stdout_callback(j, d, e)
      end
    end,
    on_exit = function()
      if type(M.exit_callback) == 'function' then
        M.exit_callback()
      end
    end,
  })

  if not channel_id or channel_id <= 0 then
    return
  end
  self.job = channel_id

  -- Stamp properties safely
  vim.api.nvim_set_option_value('filetype', self.filetype, { buf = self.buf })

  self:_attach_events(target_height)
  self:_attach_keymaps(target_height)
end

function Terminal:send(command)
  local cmd_str = tostring(command or '')
  if not self.win or not vim.api.nvim_win_is_valid(self.win) then
    self:show()
  end
  if not self.job or self.job <= 0 then
    return
  end
  vim.fn.chansend(self.job, cmd_str .. self.newline)
end

function Terminal:close()
  if not self.job or self.job <= 0 then
    return
  end
  pcall(vim.fn.jobstop, self.job)

  if self.last_win and vim.api.nvim_win_is_valid(self.last_win) then
    vim.api.nvim_set_current_win(self.last_win)
  else
    vim.cmd('wincmd k')
  end

  if self.win and vim.api.nvim_win_is_valid(self.win) then
    vim.api.nvim_win_close(self.win, true)
  end
  self.win = nil
  self.buf = nil
  self.job = nil
  self.last_win = nil

  vim.schedule(function()
    vim.cmd('wincmd =')
    M.UpdateWinbarTitles()
  end)
end

function Terminal:hide()
  if self.last_win and vim.api.nvim_win_is_valid(self.last_win) then
    vim.api.nvim_set_current_win(self.last_win)
  else
    vim.cmd('wincmd k')
  end

  if self.win and vim.api.nvim_win_is_valid(self.win) then
    vim.api.nvim_win_close(self.win, true)
  end
  self.win = nil
  self.last_win = nil

  vim.schedule(function()
    vim.cmd('wincmd =')
    M.UpdateWinbarTitles()
  end)
end

--- Native Layout Renderer and Smooth Buffer Swapper
---@return boolean
function Terminal:show()
  local active_win = vim.api.nvim_get_current_win()

  -- Rigid Workspace Capture: Lock focus window to real files, ignoring sidebar layouts
  if vim.api.nvim_win_is_valid(active_win) then
    local active_buf = vim.api.nvim_win_get_buf(active_win)
    local active_ft = vim.api.nvim_get_option_value('filetype', { buf = active_buf })
    local win_type = vim.fn.win_gettype(active_win)

    if active_ft ~= self.filetype and win_type == '' and active_ft ~= 'neo-tree' then
      self.last_win = active_win
    end
  end

  local opposite_instance = (self.term_type == 'monitor') and M.cli or M.mon
  local target_height = math.ceil(vim.o.lines * (M.config.panel_height or 0.25))

  -- 🌟 FLICKER-FREE REUSE MECHANISM
  if opposite_instance.win and vim.api.nvim_win_is_valid(opposite_instance.win) then
    self.win = opposite_instance.win
    self.last_win = opposite_instance.last_win or self.last_win
    opposite_instance.win = nil

    -- 🌟 BUG FIX: If our own buffer hasn't been instantiated yet, generate it now!
    -- This enforces that self.buf is a valid Lua number before win_set_buf runs.
    if not self.buf or not vim.api.nvim_buf_is_valid(self.buf) then
      -- Temporarily swap layout focus into our sibling window so botright split runs safely inside it
      vim.api.nvim_set_current_win(self.win)
      vim.cmd('botright ' .. target_height .. 'split')
      local temp_win = vim.api.nvim_get_current_win()
      self.buf = vim.api.nvim_get_current_buf()
      self:_spawn(target_height)
      vim.api.nvim_win_close(temp_win, true) -- Tear down the temporary creation lane
    end

    -- Swap buffer seamlessly without destroying or altering any window splits
    vim.api.nvim_win_set_buf(self.win, self.buf)
    M.UpdateWinbarTitles()
    vim.cmd('startinsert')
    return true
  end

  -- Fast-path return if target canvas split viewport is already open and valid
  if self.win and vim.api.nvim_win_is_valid(self.win) then
    vim.api.nvim_set_current_win(self.win)
    return true
  end

  -- Bulletproof Native Window Split Allocation Creation Routine
  vim.cmd('botright ' .. target_height .. 'split')
  self.win = vim.api.nvim_get_current_win()

  local is_new_buffer = false
  if not self.buf or not vim.api.nvim_buf_is_valid(self.buf) then
    self.buf = vim.api.nvim_get_current_buf()
    is_new_buffer = true
  end

  if is_new_buffer then
    self:_spawn(target_height)
  else
    vim.api.nvim_win_set_buf(self.win, self.buf)
  end

  vim.cmd('setlocal nonumber norelativenumber signcolumn=no')
  pcall(vim.api.nvim_set_option_value, 'winfixheight', true, { scope = 'local', win = self.win })
  M.UpdateWinbarTitles()

  vim.cmd('startinsert')
  return true
end

function Terminal:_attach_events(target_height)
  local scroll_group = vim.api.nvim_create_augroup('PioScroll_' .. self.buf, { clear = true })
  vim.api.nvim_create_autocmd({ 'TextChanged', 'TextChangedI' }, {
    group = scroll_group,
    buffer = self.buf,
    callback = function()
      local win_handle = vim.fn.bufwinid(self.buf)
      if win_handle and win_handle ~= -1 and vim.api.nvim_win_is_valid(win_handle) then
        vim.schedule(function()
          if vim.api.nvim_win_is_valid(win_handle) then
            vim.api.nvim_win_call(win_handle, function()
              if vim.api.nvim_get_mode().mode:sub(1, 1) ~= 't' then
                vim.cmd('normal! G')
              end
            end)
          end
        end)
      end
    end,
  })

  local guard_group = vim.api.nvim_create_augroup('PioGuard_' .. self.buf, { clear = true })
  vim.api.nvim_create_autocmd('WinEnter', {
    group = guard_group,
    buffer = self.buf,
    callback = function()
      vim.schedule(function()
        local current_win = vim.api.nvim_get_current_win()
        if current_win == self.win and self.win and vim.api.nvim_win_is_valid(self.win) then
          pcall(vim.api.nvim_win_set_height, self.win, target_height)
          if vim.api.nvim_get_mode().mode:sub(1, 1) ~= 't' then
            vim.cmd('normal! G')
            vim.cmd('startinsert')
          end
        end
      end)
    end,
  })

  -- Catch explicit typed manual command layout escapes like :q or :q!
  local quit_group = vim.api.nvim_create_augroup('PioQuit_' .. self.buf, { clear = true })
  vim.api.nvim_create_autocmd('BufWinLeave', {
    group = quit_group,
    buffer = self.buf,
    callback = function()
      vim.schedule(function()
        if self.last_win and vim.api.nvim_win_is_valid(self.last_win) then
          vim.api.nvim_set_current_win(self.last_win)
        end
        self.win = nil
        self.last_win = nil
      end)
    end,
  })
end

function Terminal:_attach_keymaps(target_height)
  local maps = M.config.keymaps
  local opposite_instance = (self.term_type == 'monitor') and M.cli or M.mon

  vim.keymap.set('t', maps.escape_term, [[<C-\><C-n>]], { buffer = self.buf })
  vim.keymap.set('n', maps.hide_pane, function()
    SafeCloseTerminal(self)
  end, { buffer = self.buf })

  vim.keymap.set({ 'n', 't' }, maps.move_up, function()
    if vim.api.nvim_get_mode().mode == 't' then
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes([[<C-\><C-n>]], true, true, true), 'n', false)
    end
    vim.schedule(function()
      vim.cmd('wincmd k')
    end)
  end, { buffer = self.buf, silent = true })

  vim.keymap.set('n', maps.switch_pane, function()
    if vim.api.nvim_get_mode().mode == 't' then
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes([[<C-\><C-n>]], true, true, true), 'n', false)
    end

    local current_winbar = vim.api.nvim_get_option_value('winbar', { scope = 'local' }) or ''
    if current_winbar:find('%[; Hide%]') or current_winbar:find('%[' .. maps.hide_pane .. ' Hide%]') then
      SafeCloseTerminal(self)
      return
    end

    opposite_instance.last_win = self.last_win
    vim.schedule(function()
      opposite_instance:show()
    end)
  end, { buffer = self.buf, silent = true })

  vim.keymap.set('n', maps.move_left, '<C-w>h', { buffer = self.buf })
  vim.keymap.set('n', maps.move_right, '<C-w>l', { buffer = self.buf })

  vim.keymap.set('n', maps.move_down, function()
    vim.schedule(function()
      local open_check = self.win and vim.api.nvim_win_is_valid(self.win) and vim.api.nvim_win_get_buf(self.win) == self.buf
      if open_check then
        vim.api.nvim_set_current_win(self.win)
        pcall(vim.api.nvim_win_set_height, self.win, target_height)
        if vim.api.nvim_get_mode().mode:sub(1, 1) ~= 't' then
          vim.cmd('normal! G')
        end
      else
        vim.cmd('wincmd j')
      end
    end)
  end, { buffer = self.buf, silent = true })
end

--- Singletons Instantiations
M.cli = Terminal.new('cli', ' Pio CLI> ')
M.mon = Terminal.new('monitor', ' Pio Monitor ')

--- Core Plugin Configuration Merging Setup Gateway
function M.setup(opts)
  M.config = vim.tbl_deep_extend('force', M.config, opts or {})
end

return M
