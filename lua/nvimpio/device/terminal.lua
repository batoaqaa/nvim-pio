local M = {}

-- Enterprise User Configuration Specification Matrix
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
-- 🌟 ENTERPRISE-GRADE DECOUPLED TERMINAL CORE ENGINE
----------------------------------------------------------------------------------------
---@class Terminal
---@field term_type string Unique structural channel lane tag ('cli' or 'monitor')
---@field title string Explicit text layout template drawn onto the local winbar row
---@field buf number|nil Immutable Neovim native buffer context memory address handle
---@field win number|nil Active viewport layout window node context index pointer
---@field job number|nil Asynchronous background socket process loop channel ID stream
---@field newline string Normalized carriage return terminator sequence delimiters
---@field filetype string Strict isolated text-domain category namespace tag
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

--- Immutable Factory Class Constructor
function Terminal.new(term_type, panel_title)
  local self = setmetatable({}, Terminal)
  self.term_type = term_type
  self.title = panel_title
  return self
end

--- Lifecycle Hook: Allocates a clean, pristine memory block completely invisible to LSPs
---@method
function Terminal:on_create()
  self.buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_option_value('filetype', self.filetype, { buf = self.buf })

  local target_height = math.ceil(vim.o.lines * (M.config.panel_height or 0.25))
  self:_register_lifecycle_events(target_height)
end

--- Lifecycle Hook: High-Utility Stdout Processor Interceptor
---@method
function Terminal:on_stdout(job_id, data, event)
  if self.term_type == 'cli' and type(M.stdout_callback) == 'function' then
    M.stdout_callback(job_id, data, event)
  end
end

--- Lifecycle Hook: High-Utility Stderr Processor Interceptor
---@method
function Terminal:on_stderr(job_id, data, event)
  if self.term_type == 'cli' and type(M.stdout_callback) == 'function' then
    M.stdout_callback(job_id, data, event)
  end
end

--- Lifecycle Hook: Triggered natively the millisecond a channel task processes out
---@method
function Terminal:on_exit()
  if type(M.exit_callback) == 'function' then
    M.exit_callback()
  end
  M.UpdateWinbarTitles()
end

--- Lifecycle Hook: Tears down process stream sockets cleanly
---@method
function Terminal:on_close()
  if self.job and self.job > 0 then
    pcall(vim.fn.jobstop, self.job)
  end
  self.job = nil
  self.buf = nil
end

--- Native Process Channel Data Submission Stream Pipeline
---@method
---@param command string|number Explicit string input array payload targeted down the pipe.
function Terminal:send(command)
  local cmd_str = tostring(command or '')
  if not self.win or not vim.api.nvim_win_is_valid(self.win) then
    self:show()
  end
  if not self.job or self.job <= 0 then
    return
  end

  -- Direct asynchronous payload delivery down the core socket stream channel
  vim.fn.chansend(self.job, cmd_str .. self.newline)

  -- Programmatic scrolling alignment completely bypassing global normal mode execution keys
  local target_win = self.win
  local target_buf = self.buf
  if target_win and vim.api.nvim_win_is_valid(target_win) and target_buf then
    vim.schedule(function()
      if vim.api.nvim_buf_is_valid(target_buf) and vim.api.nvim_win_is_valid(target_win) then
        local lines = vim.api.nvim_buf_line_count(target_buf)
        pcall(vim.api.nvim_win_set_cursor, target_win, { lines, 0 })
      end
    end)
  end
end

--- Lifecycle Hook: Draws the native split viewport safely beneath code workspaces
---@method
function Terminal:on_open()
  local target_height = math.ceil(vim.o.lines * (M.config.panel_height or 0.25))
  local opposite_instance = (self.term_type == 'monitor') and M.cli or M.mon

  -- Structural Viewport Creation Pass
  self.win = vim.api.nvim_open_win(self.buf, true, { split = 'below', win = -1, height = target_height })

  vim.cmd('setlocal nonumber norelativenumber signcolumn=no')
  pcall(vim.api.nvim_set_option_value, 'winfixheight', true, { scope = 'local', win = self.win })
  M.UpdateWinbarTitles()

  -- Initialize standard background process streams if currently resting or unallocated
  if not self.job or self.job <= 0 then
    local channel_id = vim.fn.termopen(M.config.shell, {
      on_stdout = function(j, d, e)
        self:on_stdout(j, d, e)
      end,
      on_stderr = function(j, d, e)
        self:on_stderr(j, d, e)
      end,
      on_exit = function()
        self:on_exit()
      end,
    })
    self.job = (channel_id and channel_id > 0) and channel_id or nil
  end

  self:_register_viewport_mappings(opposite_instance)
end

--- Lifecycle Hook: Tears down split window frames and calculates target focus redirection
---@method
function Terminal:on_quit()
  if self.win and vim.api.nvim_win_is_valid(self.win) then
    vim.api.nvim_win_close(self.win, true)
  end
  self.win = nil

  -- 🌟 TREE TRAVERSAL RESOLUTION: Dynamically inspect window hierarchy
  -- Safely relocates cursor context to valid code splits, ignoring Neo-tree
  local target_win = nil
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.api.nvim_win_is_valid(win) then
      local buf = vim.api.nvim_win_get_buf(win)
      local ft = vim.api.nvim_get_option_value('filetype', { buf = buf })
      local win_type = vim.fn.win_gettype(win)

      if ft ~= self.filetype and win_type == '' and ft ~= 'neo-tree' then
        target_win = win
        break
      end
    end
  end

  if target_win then
    vim.api.nvim_set_current_win(target_win)
  else
    vim.cmd('wincmd k')
  end

  vim.schedule(function()
    vim.cmd('wincmd =')
    M.UpdateWinbarTitles()
  end)
end

function Terminal:close()
  self:on_close()
  self:on_quit()
end

function Terminal:hide()
  self:on_quit()
end

--- Main Entry Gateway Coordinator Pass
---@return boolean
function Terminal:show()
  if not self.buf or not vim.api.nvim_buf_is_valid(self.buf) then
    self:on_create()
  end

  local opposite_instance = (self.term_type == 'monitor') and M.cli or M.mon

  -- Flicker-Free Viewport Reuse Gateway Split Swap
  if opposite_instance.win and vim.api.nvim_win_is_valid(opposite_instance.win) then
    self.win = opposite_instance.win
    opposite_instance.win = nil

    vim.api.nvim_win_set_buf(self.win, self.buf)
    M.UpdateWinbarTitles()
    return true
  end

  if self.win and vim.api.nvim_win_is_valid(self.win) then
    vim.api.nvim_set_current_win(self.win)
    return true
  end

  self:on_open()
  return true
end

function Terminal:_register_lifecycle_events(target_height)
  local platformio = vim.api.nvim_create_augroup('PioEvents_' .. self.buf, { clear = true })

  -- Intercept manual exits typed via command bar (:q and :q!)
  vim.api.nvim_create_autocmd('CmdlineLeave', {
    group = platformio,
    buffer = self.buf,
    callback = function()
      if vim.v.event and not vim.v.event.abort and vim.v.event.cmdtype == ':' then
        local cmd = vim.fn.getcmdline()
        if cmd == 'q' or cmd == 'q!' then
          if cmd == 'q!' then
            self:on_close()
          end
          vim.schedule(function()
            self:on_quit()
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

  -- Core Programmatic Scroll Tracker
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

  -- Height Boundary Enforcement Lock
  vim.api.nvim_create_autocmd('WinEnter', {
    group = platformio,
    buffer = self.buf,
    callback = function()
      vim.schedule(function()
        local current_win = vim.api.nvim_get_current_win()
        if current_win == self.win and self.win and vim.api.nvim_win_is_valid(self.win) then
          pcall(vim.api.nvim_win_set_height, self.win, target_height)
          local lines = vim.api.nvim_buf_line_count(self.buf)
          pcall(vim.api.nvim_win_set_cursor, self.win, { lines, 0 })
        end
      end)
    end,
  })
end

function Terminal:_register_viewport_mappings(opposite_instance)
  local maps = M.config.keymaps

  -- Core Navigation Mapping Implementations
  vim.keymap.set('t', maps.escape_term, [[<C-\><C-n>]], { buffer = self.buf })
  vim.keymap.set('n', maps.hide_pane, function()
    self:on_quit()
  end, { buffer = self.buf })

  vim.keymap.set('t', maps.move_up, [[<C-\><C-n><C-w>k]], { buffer = self.buf, silent = true })
  vim.keymap.set('n', maps.move_up, '<C-w>k', { buffer = self.buf, silent = true })

  vim.keymap.set('t', maps.switch_pane, function()
    local current_winbar = vim.api.nvim_get_option_value('winbar', { scope = 'local' }) or ''
    if current_winbar:find('%[; Hide%]') or current_winbar:find('%[' .. maps.hide_pane .. ' Hide%]') then
      self:on_quit()
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

  vim.keymap.set('n', maps.switch_pane, function()
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
  vim.keymap.set('n', maps.move_down, '<C-w>j', { buffer = self.buf })
end

--- Winbar Redraw Layout Sync Engine Matrix
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

local function IsTerminalOpen(instance)
  if not instance then
    return false
  end
  return instance.win and vim.api.nvim_win_is_valid(instance.win) and vim.api.nvim_win_get_buf(instance.win) == instance.buf
end

function M.IsTerminalOpen(term_type)
  local instance = (term_type == 'monitor') and M.mon or M.cli
  return IsTerminalOpen(instance)
end

--- Object Singleton Instantiations
M.cli = Terminal.new('cli', ' Pio CLI> ')
M.mon = Terminal.new('monitor', ' Pio Monitor ')

function M.setup(opts)
  M.config = vim.tbl_deep_extend('force', M.config, opts or {})
end

return M

-- -- stylua: ignore start
--
-- local M = {}
--
-- -- Default Public User Configuration Matrix
-- M.config = {
--   panel_height = 0.2,
--   winbar_bg = '#80a3d4',
--   winbar_fg = '#000000',
--   shell = OS.shell,
--   keymaps = {
--     hide_pane = 'q',
--     switch_pane = '<Tab>',
--     escape_term = '<Esc>',
--     move_up = '<C-k>',
--     move_down = '<C-j>',
--     move_left = '<C-h>',
--     move_right = '<C-l>',
--   },
-- }
--
-- M.stdout_callback = nil
-- M.exit_callback = nil
--
-- ----------------------------------------------------------------------------------------
-- -- OBJECT ORIENTED TERMINAL CLASS ARCHITECTURE
-- ----------------------------------------------------------------------------------------
-- ---@class Terminal
-- ---@field term_type string Unique lane tag ('cli' or 'monitor')
-- ---@field title string The text drawn onto the window winbar header
-- ---@field buf number|nil The native Neovim buffer ID handle
-- ---@field win number|nil The native Neovim window ID viewport handle
-- ---@field last_win number|nil Originating file split window ID context handle
-- ---@field job number|nil Asynchronous process stream channel ID handle
-- ---@field newline string Pre-cached newline carriage return delimiter
-- ---@field filetype string Fixed text-domain category tag
-- local Terminal = {
--   term_type = '',
--   title = '',
--   buf = nil,
--   win = nil,
--   last_win = nil,
--   job = nil,
--   newline = OS.eol,
--   filetype = 'pio_terminal',
-- }
-- Terminal.__index = Terminal
--
-- --- Factory Constructor
-- function Terminal.new(term_type, panel_title)
--   local self = setmetatable({}, Terminal)
--   self.term_type = term_type
--   self.title = panel_title
--   return self
-- end
--
-- --- Hook: Fires ONCE when the buffer context is allocated
-- ---@method
-- function Terminal:on_create()
--   self.buf = vim.api.nvim_create_buf(false, true)
--
--   -- Set the filetype tag cleanly, but DO NOT manually force "buftype"
--   -- Neovim will set buftype = "terminal" natively when termopen() executes.
--   vim.api.nvim_set_option_value('filetype', self.filetype, { buf = self.buf })
--
--   local target_height = math.ceil(vim.o.lines * (M.config.panel_height or 0.25))
--   self:_attach_events(target_height)
-- end
--
-- --- Hook: Process backend stdout streams natively
-- ---@method
-- function Terminal:on_stdout(j, d, e)
--   if self.term_type == 'cli' and type(M.stdout_callback) == 'function' then
--     M.stdout_callback(j, d, e)
--   end
-- end
--
-- --- Hook: Process backend stderr streams natively
-- ---@method
-- function Terminal:on_stderr(j, d, e)
--   if self.term_type == 'cli' and type(M.stdout_callback) == 'function' then
--     M.stdout_callback(j, d, e)
--   end
-- end
--
-- --- Hook: Fires cleanly when a background task completes execution
-- ---@method
-- function Terminal:on_exit()
--   if type(M.exit_callback) == 'function' then
--     M.exit_callback()
--   end
--   M.UpdateWinbarTitles()
-- end
--
-- --- Hook: Core platform socket channel teardown
-- ---@method
-- function Terminal:on_close()
--   if self.job and self.job > 0 then
--     pcall(vim.fn.jobstop, self.job)
--   end
--   self.job = nil
--   self.buf = nil
-- end
--
-- --- Pure String Channel Data Injection
-- ---@method
-- function Terminal:send(command)
--   local cmd_str = tostring(command or '')
--   if not self.win or not vim.api.nvim_win_is_valid(self.win) then
--     self:show()
--   end
--   if not self.job or self.job <= 0 then
--     return
--   end
--
--   vim.fn.chansend(self.job, cmd_str .. self.newline)
--
--   vim.schedule(function()
--     if self.win and vim.api.nvim_win_is_valid(self.win) then
--       local lines = vim.api.nvim_buf_line_count(self.buf)
--       pcall(vim.api.nvim_win_set_cursor, self.win, { lines, 0 })
--     end
--   end)
-- end
-- --- Hook: Handles physical window allocation drawing passes cleanly
-- ---@method
-- function Terminal:on_open()
--   local target_height = math.ceil(vim.o.lines * (M.config.panel_height or 0.25))
--   local opposite_instance = (self.term_type == 'monitor') and M.cli or M.mon
--
--   -- Allocate layout viewport directly beneath code files
--   self.win = vim.api.nvim_open_win(self.buf, true, { split = 'below', win = -1, height = target_height })
--
--   vim.cmd('setlocal nonumber norelativenumber signcolumn=no')
--   pcall(vim.api.nvim_set_option_value, 'winfixheight', true, { scope = 'local', win = self.win })
--   M.UpdateWinbarTitles()
--
--   -- Initialize background process cleanly inside our dedicated context
--   if not self.job or self.job <= 0 then
--     local channel_id = vim.fn.termopen(M.config.shell, {
--       on_stdout = function(j, d, e)
--         self:on_stdout(j, d, e)
--       end,
--       on_stderr = function(j, d, e)
--         self:on_stderr(j, d, e)
--       end,
--       on_exit = function()
--         self:on_exit()
--       end,
--     })
--     self.job = (channel_id and channel_id > 0) and channel_id or nil
--   end
--
--   self:_attach_keymaps(opposite_instance)
-- end
--
-- --- Hook: Collapses split viewports and redirects layout focus securely
-- ---@method
-- function Terminal:on_quit()
--   if self.win and vim.api.nvim_win_is_valid(self.win) then
--     vim.api.nvim_win_close(self.win, true)
--   end
--   self.win = nil
--
--   if self.last_win and vim.api.nvim_win_is_valid(self.last_win) then
--     vim.api.nvim_set_current_win(self.last_win)
--   else
--     vim.cmd('wincmd k')
--   end
--   self.last_win = nil
--
--   vim.schedule(function()
--     vim.cmd('wincmd =')
--     M.UpdateWinbarTitles()
--   end)
-- end
--
-- function Terminal:close()
--   self:on_close()
--   self:on_quit()
-- end
--
-- function Terminal:hide()
--   self:on_quit()
-- end
--
-- --- Unified Pure Layout Open/Reuse Pass
-- ---@return boolean
-- function Terminal:show()
--   local active_win = vim.api.nvim_get_current_win()
--   if vim.api.nvim_win_is_valid(active_win) then
--     local active_buf = vim.api.nvim_win_get_buf(active_win)
--     local active_ft = vim.api.nvim_get_option_value('filetype', { buf = active_buf })
--     local win_type = vim.fn.win_gettype(active_win)
--     if active_ft ~= self.filetype and win_type == '' and active_ft ~= 'neo-tree' then
--       self.last_win = active_win
--     end
--   end
--
--   if not self.buf or not vim.api.nvim_buf_is_valid(self.buf) then
--     self:on_create()
--   end
--
--   local opposite_instance = (self.term_type == 'monitor') and M.cli or M.mon
--
--   -- Flicker-Free Sibling Viewport Swap
--   if opposite_instance.win and vim.api.nvim_win_is_valid(opposite_instance.win) then
--     self.win = opposite_instance.win
--     self.last_win = opposite_instance.last_win or self.last_win
--     opposite_instance.win = nil
--
--     vim.api.nvim_win_set_buf(self.win, self.buf)
--     M.UpdateWinbarTitles()
--     return true
--   end
--
--   if self.win and vim.api.nvim_win_is_valid(self.win) then
--     vim.api.nvim_set_current_win(self.win)
--     return true
--   end
--
--   self:on_open()
--   return true
-- end
--
-- function Terminal:_attach_events(target_height)
--   local platformio = vim.api.nvim_create_augroup('PioEvents_' .. self.buf, { clear = true })
--
--   -- Intercept manual exits typed via command bar (:q and :q!)
--   vim.api.nvim_create_autocmd('CmdlineLeave', {
--     group = platformio,
--     buffer = self.buf,
--     callback = function()
--       if vim.v.event and not vim.v.event.abort and vim.v.event.cmdtype == ':' then
--         local cmd = vim.fn.getcmdline()
--         if cmd == 'q' or cmd == 'q!' then
--           if cmd == 'q!' then
--             self:on_close()
--           end
--           vim.schedule(function()
--             self:on_quit()
--           end)
--         end
--       end
--     end,
--   })
--
--   vim.api.nvim_create_autocmd('BufLeave', {
--     group = platformio,
--     buffer = self.buf,
--     callback = function()
--       vim.schedule(function()
--         M.UpdateWinbarTitles()
--       end)
--     end,
--   })
--
--   -- Core Programmatic Scroll Tracker
--   vim.api.nvim_create_autocmd({ 'TextChanged', 'TextChangedI' }, {
--     group = platformio,
--     buffer = self.buf,
--     callback = function()
--       local win_handle = vim.fn.bufwinid(self.buf)
--       if win_handle and win_handle ~= -1 and vim.api.nvim_win_is_valid(win_handle) then
--         vim.schedule(function()
--           if vim.api.nvim_win_is_valid(win_handle) then
--             local lines = vim.api.nvim_buf_line_count(self.buf)
--             pcall(vim.api.nvim_win_set_cursor, win_handle, { lines, 0 })
--           end
--         end)
--       end
--     end,
--   })
--
--   -- Geometry Height Locks
--   vim.api.nvim_create_autocmd('WinEnter', {
--     group = platformio,
--     buffer = self.buf,
--     callback = function()
--       vim.schedule(function()
--         local current_win = vim.api.nvim_get_current_win()
--         if current_win == self.win and self.win and vim.api.nvim_win_is_valid(self.win) then
--           pcall(vim.api.nvim_win_set_height, self.win, target_height)
--           local lines = vim.api.nvim_buf_line_count(self.buf)
--           pcall(vim.api.nvim_win_set_cursor, self.win, { lines, 0 })
--         end
--       end)
--     end,
--   })
-- end
--
-- function Terminal:_attach_keymaps(opposite_instance)
--   local maps = M.config.keymaps
--
--   -- Native Terminal Shortcuts Mapping
--   vim.keymap.set('t', maps.escape_term, [[<C-\><C-n>]], { buffer = self.buf })
--   vim.keymap.set('n', maps.hide_pane, function()
--     self:on_quit()
--   end, { buffer = self.buf })
--
--   vim.keymap.set('t', maps.move_up, [[<C-\><C-n><C-w>k]], { buffer = self.buf, silent = true })
--   vim.keymap.set('n', maps.move_up, '<C-w>k', { buffer = self.buf, silent = true })
--
--   vim.keymap.set('t', maps.switch_pane, function()
--     local current_winbar = vim.api.nvim_get_option_value('winbar', { scope = 'local' }) or ''
--     if current_winbar:find('%[; Hide%]') or current_winbar:find('%[' .. maps.hide_pane .. ' Hide%]') then
--       self:on_quit()
--       return
--     end
--     opposite_instance.last_win = self.last_win
--     if self.win and vim.api.nvim_win_is_valid(self.win) then
--       vim.api.nvim_win_close(self.win, true)
--     end
--     self.win = nil
--     vim.schedule(function()
--       opposite_instance:show()
--     end)
--   end, { buffer = self.buf, silent = true })
--
--   vim.keymap.set('n', maps.switch_pane, function()
--     opposite_instance.last_win = self.last_win
--     if self.win and vim.api.nvim_win_is_valid(self.win) then
--       vim.api.nvim_win_close(self.win, true)
--     end
--     self.win = nil
--     vim.schedule(function()
--       opposite_instance:show()
--     end)
--   end, { buffer = self.buf, silent = true })
--
--   vim.keymap.set('n', maps.move_left, '<C-w>h', { buffer = self.buf })
--   vim.keymap.set('n', maps.move_right, '<C-w>l', { buffer = self.buf })
--   vim.keymap.set('n', maps.move_down, '<C-w>j', { buffer = self.buf })
-- end
--
-- --- Visual redrawing loop engine applying winbar header tags
-- function M.UpdateWinbarTitles()
--   local cli_alive = M.cli.buf and vim.api.nvim_buf_is_valid(M.cli.buf)
--   local mon_alive = M.mon.buf and vim.api.nvim_buf_is_valid(M.mon.buf)
--   local maps = M.config.keymaps
--
--   local hint = (cli_alive and mon_alive) and string.format('[ %s  Switch;  %s  Hide; :q! Quit ] ', maps.switch_pane, maps.hide_pane)
--     or string.format('[ %s  Hide; :q! Quit ] ', maps.hide_pane)
--
--   vim.api.nvim_set_hl(0, 'PioWinBar', { bg = M.config.winbar_bg, fg = M.config.winbar_fg })
--
--   for _, instance in pairs({ M.cli, M.mon }) do
--     if instance and instance.win and vim.api.nvim_win_is_valid(instance.win) then
--       vim.api.nvim_set_option_value('winbar', '%#PioWinBar#' .. instance.title .. hint .. '%*', { scope = 'local', win = instance.win })
--     end
--   end
-- end
--
-- local function IsTerminalOpen(instance)
--   if not instance then
--     return false
--   end
--   return instance.win and vim.api.nvim_win_is_valid(instance.win) and vim.api.nvim_win_get_buf(instance.win) == instance.buf
-- end
--
-- function M.IsTerminalOpen(term_type)
--   local instance = (term_type == 'monitor') and M.mon or M.cli
--   return IsTerminalOpen(instance)
-- end
--
-- --- Singletons Instantiations
-- M.cli = Terminal.new('cli', ' Pio CLI> ')
-- M.mon = Terminal.new('monitor', ' Pio Monitor ')
--
-- function M.setup(opts)
--   M.config = vim.tbl_deep_extend('force', M.config, opts or {})
-- end
--
-- return M
