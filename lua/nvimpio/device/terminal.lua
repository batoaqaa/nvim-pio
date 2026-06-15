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

----------------------------------------------------------------------------------------
-- OBJECT ORIENTED TERMINAL CLASS BLUEPRINT
----------------------------------------------------------------------------------------
---@class Terminal
---@field term_type string Unique lane tag ('cli' or 'monitor')
---@field title string The text drawn onto the window winbar header
---@field buf number|nil Native Neovim buffer ID handle
---@field win number|nil Native Neovim window ID viewport handle
---@field job number|nil Asynchronous terminal channel ID backend process loop handle
---@field newline string Pre-cached cross-platform newline sequence delimiter
---@field filetype string Fixed text-domain category tracking tag
local Terminal = {
  term_type = '',
  title = '',
  buf = nil,
  win = nil,
  job = nil,
  newline = '\r\n',
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

--- Dynamic Workspace Focus Shifter
--- Automatically scans active layout nodes and relocates cursor focus away from sidebars
function M.RestoreWorkspaceFocus()
  local target_win = nil
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.api.nvim_win_is_valid(win) then
      local buf = vim.api.nvim_win_get_buf(win)
      local ft = vim.api.nvim_get_option_value('filetype', { buf = buf })
      local win_type = vim.fn.win_gettype(win)

      -- If the window split holds an active code file and isn't a sidebar/floating popup, lock onto it
      if ft ~= 'pio_terminal' and win_type == '' and ft ~= 'neo-tree' and ft ~= 'oil' then
        target_win = win
        break
      end
    end
  end

  if target_win then
    vim.api.nvim_set_current_win(target_win)
  else
    vim.cmd('wincmd k') -- Fallback up if no listed file splits are found
  end
end

--- Core Close Controller
function Terminal:close()
  if self.job and self.job > 0 then
    pcall(vim.fn.jobstop, self.job)
  end
  if self.win and vim.api.nvim_win_is_valid(self.win) then
    vim.api.nvim_win_close(self.win, true)
  end
  self.win = nil
  self.buf = nil
  self.job = nil

  M.RestoreWorkspaceFocus()
  vim.schedule(function()
    vim.cmd('wincmd =')
    M.UpdateWinbarTitles()
  end)
end

--- Core Hide Controller
function Terminal:hide()
  if self.win and vim.api.nvim_win_is_valid(self.win) then
    vim.api.nvim_win_close(self.win, true)
  end
  self.win = nil

  M.RestoreWorkspaceFocus()
  vim.schedule(function()
    vim.cmd('wincmd =')
    M.UpdateWinbarTitles()
  end)
end

--- Stable Programmatic Send Action
function Terminal:send(command)
  local cmd_str = tostring(command or '')
  if not self.win or not vim.api.nvim_win_is_valid(self.win) then
    self:show()
  end
  if not self.job or self.job <= 0 then
    return
  end

  -- Direct programmatic stream injection via our newline terminator
  vim.fn.chansend(self.job, cmd_str .. self.newline)
end

--- Pure Show Pass - Handles clean split window toggling natively
---@return boolean
function Terminal:show()
  local opposite_instance = (self.term_type == 'monitor') and M.cli or M.mon

  -- Clean Sibling Teardown: If the alternative terminal is open, shut its window split first
  if opposite_instance.win and vim.api.nvim_win_is_valid(opposite_instance.win) then
    vim.api.nvim_win_close(opposite_instance.win, true)
    opposite_instance.win = nil
  end

  -- Fast path return: If our pane window is already alive, jump focus directly
  if self.win and vim.api.nvim_win_is_valid(self.win) then
    vim.api.nvim_set_current_win(self.win)
    return true
  end

  -- Initialize a clean scratch buffer if opening for the very first time
  local is_new_buffer = false
  if not self.buf or not vim.api.nvim_buf_is_valid(self.buf) then
    self.buf = vim.api.nvim_create_buf(false, true)
    is_new_buffer = true
  end

  if self.buf and vim.api.nvim_buf_is_valid(self.buf) then
    vim.api.nvim_set_option_value('filetype', self.filetype, { buf = self.buf })
  end

  -- Native Split: Render the split layout frame directly below your code file workspace
  local target_height = math.ceil(vim.o.lines * (M.config.panel_height or 0.25))
  self.win = vim.api.nvim_open_win(self.buf, true, { split = 'below', win = -1, height = target_height })

  -- Initialize standard termopen shell loop inside our bottom split viewport context
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
        M.UpdateWinbarTitles()
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

  -- Initial Entry State: Always map focus into standard normal mode boundaries
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes([[<C-\><C-n>]], true, true, true), 'n', false)
  return true
end

function Terminal:_attach_events(target_height, opposite_instance)
  local platformio = vim.api.nvim_create_augroup('PioEvents_' .. self.buf, { clear = true })

  -- Intercept typed command bar exits (:q and :q!) and handle workspace focus shifting safely
  vim.api.nvim_create_autocmd('CmdlineLeave', {
    group = platformio,
    buffer = self.buf,
    callback = function()
      if vim.v.event and not vim.v.event.abort and vim.v.event.cmdtype == ':' then
        local cmd = vim.fn.getcmdline()
        if cmd == 'q' or cmd == 'q!' then
          if cmd == 'q!' and self.job and self.job > 0 then
            pcall(vim.fn.jobstop, self.job)
          end
          self.win = nil
          vim.schedule(function()
            M.RestoreWorkspaceFocus()
          end)
        end
      end
    end,
  })

  vim.api.nvim_create_autocmd('BufLeave', {
    group = platformio,
    buffer = self.buf,
    callback = function()
      vim.schedule(function()
        M.UpdateWinbarTitles()
      end)
    end,
  })

  -- Robust Programmatic Scroll Tracker: Follows terminal text stream outputs down cleanly
  vim.api.nvim_create_autocmd({ 'TextChanged', 'TextChangedI' }, {
    group = platformio,
    buffer = self.buf,
    callback = function()
      local win_handle = vim.fn.bufwinid(self.buf)
      if win_handle and win_handle ~= -1 and vim.api.nvim_win_is_valid(win_handle) then
        vim.schedule(function()
          if vim.api.nvim_win_is_valid(win_handle) then
            local lines = vim.api.nvim_buf_line_count(self.buf)
            pcall(vim.api.nvim_win_set_cursor, win_handle, { lines, 0 })
          end
        end)
      end
    end,
  })

  -- Focus Lock: Forces Normal mode navigation whenever a terminal split window gains focus
  vim.api.nvim_create_autocmd('WinEnter', {
    group = platformio,
    buffer = self.buf,
    callback = function()
      vim.schedule(function()
        local current_win = vim.api.nvim_get_current_win()
        if current_win == self.win and self.win and vim.api.nvim_win_is_valid(self.win) then
          pcall(vim.api.nvim_win_set_height, self.win, target_height)
          vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes([[<C-\><C-n>]], true, true, true), 'n', false)
          local lines = vim.api.nvim_buf_line_count(self.buf)
          pcall(vim.api.nvim_win_set_cursor, self.win, { lines, 0 })
        end
      end)
    end,
  })

  self:_attach_keymaps(target_height, opposite_instance)
end

function Terminal:_attach_keymaps(target_height, opposite_instance)
  local maps = M.config.keymaps

  -- Native Terminal Navigation Keymaps Setup
  vim.keymap.set('t', maps.escape_term, [[<C-\><C-n>]], { buffer = self.buf })
  vim.keymap.set('n', maps.hide_pane, function()
    self:hide()
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
    local current_winbar = vim.api.nvim_get_option_value('winbar', { scope = 'local' }) or ''
    if current_winbar:find('%[; Hide%]') or current_winbar:find('%[' .. maps.hide_pane .. ' Hide%]') then
      self:hide()
      return
    end

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
        local lines = vim.api.nvim_buf_line_count(self.buf)
        pcall(vim.api.nvim_win_set_cursor, self.win, { lines, 0 })
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
