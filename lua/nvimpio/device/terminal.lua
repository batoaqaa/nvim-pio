local M = {}

-- Default Public User Configuration Matrix
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

--- Safe window manager close executor pass routine
---@param instance Terminal The specific object handle to clear down.
local function SafeCloseTerminal(instance)
  if not instance then
    return
  end

  -- 1. Close the dedicated terminal window pane viewport layout
  if instance.win and vim.api.nvim_win_is_valid(instance.win) then
    vim.api.nvim_win_close(instance.win, true)
  end
  instance.win = nil

  -- 2. Force focus back to your actual code window split, bypassing Neo-tree
  if instance.last_win and vim.api.nvim_win_is_valid(instance.last_win) then
    vim.api.nvim_set_current_win(instance.last_win)
  end
  instance.last_win = nil

  vim.schedule(function()
    vim.cmd('wincmd =')
    M.UpdateWinbarTitles()
  end)
end

--- Visual redrawing loop engine applying winbar header tags
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
-- OBJECT ORIENTED TERMINAL CLASS BLUEPRINT
----------------------------------------------------------------------------------------
---@class Terminal
---@field term_type string Unique lane configuration tracking tag ('cli' or 'monitor')
---@field title string The visual string printed on the window winbar header
---@field buf number|nil The native Neovim buffer ID handle for this panel split
---@field win number|nil The native Neovim window ID layout viewport handle
---@field last_win number|nil The exact originating window ID handle prior to open routines
---@field job number|nil The asynchronous terminal channel ID backend process loop handle
---@field newline string Pre-cached cross-platform row end carriage return delimiter
---@field filetype string Fixed text-domain category tracking tag
local Terminal = {
  term_type = '',
  title = '',
  buf = nil,
  win = nil,
  last_win = nil,
  job = nil,
  newline = '\r\n', -- 🌟 Cross-platform native terminal line terminator
  filetype = 'pio_terminal',
}
Terminal.__index = Terminal

function Terminal.new(term_type, panel_title)
  local self = setmetatable({}, Terminal)
  self.term_type = term_type
  self.title = panel_title
  return self
end

-- 🌟 FIXED EXECUTION ROUTINE
-- Guarantees the channel accepts inputs cleanly and triggers execution without hanging
function Terminal:send(command)
  local cmd_str = tostring(command or '')
  if not self.win or not vim.api.nvim_win_is_valid(self.win) then
    self:show()
  end
  if not self.job or self.job <= 0 then
    return
  end

  vim.schedule(function()
    if self.job and self.job > 0 then
      -- Clear any normal-mode locks inside the execution scheduler frame
      vim.api.nvim_set_current_win(self.win)
      vim.cmd('startinsert')

      -- Feed the text command payload with the native return break sequence
      vim.fn.chansend(self.job, cmd_str .. self.newline)

      -- Automatically return to Normal Mode safely after execution begins
      vim.schedule(function()
        if self.win and vim.api.nvim_win_is_valid(self.win) then
          vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes([[<C-\><C-n>]], true, true, true), 'n', false)
          vim.cmd('normal! G')
        end
      end)
    end
  end)
end

function Terminal:close()
  if not self.job or self.job <= 0 then
    return
  end
  pcall(vim.fn.jobstop, self.job)

  if self.win and vim.api.nvim_win_is_valid(self.win) then
    vim.api.nvim_win_close(self.win, true)
  end
  self.win = nil
  self.buf = nil
  self.job = nil

  if self.last_win and vim.api.nvim_win_is_valid(self.last_win) then
    vim.api.nvim_set_current_win(self.last_win)
  end
  self.last_win = nil

  vim.schedule(function()
    vim.cmd('wincmd =')
    M.UpdateWinbarTitles()
  end)
end

function Terminal:hide()
  if self.win and vim.api.nvim_win_is_valid(self.win) then
    vim.api.nvim_win_close(self.win, true)
  end
  self.win = nil

  if self.last_win and vim.api.nvim_win_is_valid(self.last_win) then
    vim.api.nvim_set_current_win(self.last_win)
  end
  self.last_win = nil

  vim.schedule(function()
    vim.cmd('wincmd =')
    M.UpdateWinbarTitles()
  end)
end

--- Pure Show Pass - Handles allocation and spawning natively via clean window toggling.
---@return boolean # True if the split window canvas layout was drawn successfully.
function Terminal:show()
  local active_win = vim.api.nvim_get_current_win()

  -- Cache active workspace window ID, rigidly filtering out sidebar panes like Neo-tree
  if vim.api.nvim_win_is_valid(active_win) then
    local active_buf = vim.api.nvim_win_get_buf(active_win)
    local active_ft = vim.api.nvim_get_option_value('filetype', { buf = active_buf })
    local win_type = vim.fn.win_gettype(active_win)

    if active_ft ~= self.filetype and win_type == '' and active_ft ~= 'neo-tree' then
      self.last_win = active_win
    end
  end

  local opposite_instance = (self.term_type == 'monitor') and M.cli or M.mon

  -- Simple Sibling Teardown: Close the other panel split window before opening ours
  if opposite_instance.win and vim.api.nvim_win_is_valid(opposite_instance.win) then
    self.last_win = opposite_instance.last_win or self.last_win
    vim.api.nvim_win_close(opposite_instance.win, true)
    opposite_instance.win = nil
  end

  -- Fast path return: If this exact split window is already alive, focus it
  if self.win and vim.api.nvim_win_is_valid(self.win) then
    vim.api.nvim_set_current_win(self.win)
    return true
  end

  local is_new_buffer = false
  if not self.buf or not vim.api.nvim_buf_is_valid(self.buf) then
    self.buf = vim.api.nvim_create_buf(false, true)
    is_new_buffer = true
  end

  if self.buf and vim.api.nvim_buf_is_valid(self.buf) then
    vim.api.nvim_set_option_value('filetype', self.filetype, { buf = self.buf })
  end

  -- Generate clean layout viewport directly below your code file workspace split
  local target_height = math.ceil(vim.o.lines * (M.config.panel_height or 0.25))
  self.win = vim.api.nvim_open_win(self.buf, true, { split = 'below', win = -1, height = target_height })

  if is_new_buffer then
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
    if channel_id and channel_id > 0 then
      self.job = channel_id
    end
    self:_attach_events(target_height, opposite_instance)
  end

  vim.cmd('setlocal nonumber norelativenumber signcolumn=no')
  pcall(vim.api.nvim_set_option_value, 'winfixheight', true, { scope = 'local', win = self.win })
  M.UpdateWinbarTitles()

  -- INITIAL OPEN STYLE: Drop cleanly into Normal mode immediately upon panel drawing
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes([[<C-\><C-n>]], true, true, true), 'n', false)
  return true
end

function Terminal:_attach_events(target_height, opposite_instance)
  local platformio = vim.api.nvim_create_augroup('PioEvents_' .. self.buf, { clear = true })

  -- INTERCEPT MANUAL CMDLINE EXITS (:q and :q!) BEFORE NEOTREE STEALS FOCUS
  vim.api.nvim_create_autocmd('CmdlineLeave', {
    group = platformio,
    buffer = self.buf,
    callback = function()
      if vim.v.event and not vim.v.event.abort and vim.v.event.cmdtype == ':' then
        local cmd = vim.fn.getcmdline()
        if cmd == 'q' or cmd == 'q!' then
          if cmd == 'q!' then
            if self.term_type == 'monitor' then
              vim.fn.chansend(self.job, vim.api.nvim_replace_termcodes('<C-C>exit\n', true, true, true))
            else
              vim.fn.chansend(self.job, 'exit\n')
            end
          end

          vim.schedule(function()
            if self.last_win and vim.api.nvim_win_is_valid(self.last_win) then
              vim.api.nvim_set_current_win(self.last_win)
            end
            self.win = nil
            self.last_win = nil
          end)
        end
      end
    end,
  })

  -- INTERCEPT LOST FOCUS EVENTS (Clicking away or escaping pane layout)
  vim.api.nvim_create_autocmd('BufLeave', {
    group = platformio,
    buffer = self.buf,
    callback = function()
      vim.schedule(function()
        M.UpdateWinbarTitles()
      end)
    end,
  })

  -- Clean Automatic Scroll Tracker: Follows terminal prints down safely without changing mode states
  vim.api.nvim_create_autocmd({ 'TextChanged', 'TextChangedI' }, {
    group = platformio,
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

  -- ALWAYS GAIN FOCUS WINDOW ENTRY STATE: Enforces normal mode on physical window entry clicks
  vim.api.nvim_create_autocmd('WinEnter', {
    group = platformio,
    buffer = self.buf,
    callback = function()
      vim.schedule(function()
        local current_win = vim.api.nvim_get_current_win()
        if current_win == self.win and self.win and vim.api.nvim_win_is_valid(self.win) then
          pcall(vim.api.nvim_win_set_height, self.win, target_height)

          -- Forces your cursor into clean Normal layout mode on every active window entry focus shift
          vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes([[<C-\><C-n>]], true, true, true), 'n', false)
          vim.cmd('normal! G')
        end
      end)
    end,
  })

  self:_attach_keymaps(target_height, opposite_instance)
end

function Terminal:_attach_keymaps(target_height, opposite_instance)
  local maps = M.config.keymaps

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

    if self.win and vim.api.nvim_win_is_valid(self.win) then
      vim.api.nvim_win_close(self.win, true)
    end
    self.win = nil

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
        vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes([[<C-\><C-n>]], true, true, true), 'n', false)
        vim.cmd('normal! G')
      else
        vim.cmd('wincmd j')
      end
    end)
  end, { buffer = self.buf, silent = true })
end

--- Singletons Instantiations
M.cli = Terminal.new('cli', ' Pio CLI> ')
M.mon = Terminal.new('monitor', ' Pio Monitor ')

function M.setup(opts)
  M.config = vim.tbl_deep_extend('force', M.config, opts or {})
end

return M
