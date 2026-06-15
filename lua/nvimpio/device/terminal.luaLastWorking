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

-- Caches to protect the user's private environment options and memory footings
M.user_splitkeep_cache = nil
M.cached_spacer_buf = nil

function M.UpdateWinbarTitles()
  local cli_alive = M.cli and M.cli.buf and vim.api.nvim_buf_is_valid(M.cli.buf)
  local mon_alive = M.mon and M.mon.buf and vim.api.nvim_buf_is_valid(M.mon.buf)
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

function M.RestoreWorkspaceFocus()
  local target_win = nil
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.api.nvim_win_is_valid(win) then
      local buf = vim.api.nvim_win_get_buf(win)
      local ft = vim.api.nvim_get_option_value('filetype', { buf = buf })
      local win_type = vim.fn.win_gettype(win)

      if ft ~= 'pio_terminal' and win_type == '' and ft ~= 'neo-tree' and ft ~= 'oil' and ft ~= 'aerial' and ft ~= 'pio_workspace' then
        target_win = win
        break
      end
    end
  end

  if target_win then
    vim.api.nvim_set_current_win(target_win)
  end
end

----------------------------------------------------------------------------------------
-- THE INDESTRUCTIBLE OOP TERMINAL CLASS TEMPLATE
----------------------------------------------------------------------------------------
---@class Terminal
---@field term_type string Unique structural channel lane tag ('cli' or 'monitor')
---@field title string Explicit winbar tracking text template
---@field buf number|nil Native Neovim buffer ID handle
---@field win number|nil Native Neovim window ID viewport handle
---@field last_win number|nil Code file window context index node tracking pointer
---@field job number|nil Background terminal channel process loop stream ID
---@field newline string Carriage return line delimiter sequence
---@field filetype string Fixed text-domain category namespace tag
local Terminal = {
  term_type = '',
  title = '',
  buf = nil,
  win = nil,
  last_win = nil,
  job = nil,
  newline = '\r\n',
  filetype = 'pio_terminal',
}
Terminal.__index = Terminal

function Terminal.new(term_type, panel_title)
  local self = setmetatable({}, Terminal)
  self.term_type = term_type
  self.title = panel_title
  return self
end

function Terminal:on_create()
  self.buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_option_value('filetype', self.filetype, { buf = self.buf })

  local target_height = math.ceil(vim.o.lines * (M.config.panel_height or 0.2))
  self:_register_lifecycle_events(target_height)
end

function Terminal:on_stdout(j, d, e)
  if self.term_type == 'cli' and type(M.stdout_callback) == 'function' then
    M.stdout_callback(j, d, e)
  end
end

function Terminal:on_stderr(j, d, e)
  if self.term_type == 'cli' and type(M.stdout_callback) == 'function' then
    M.stdout_callback(j, d, e)
  end
end

function Terminal:on_exit()
  if type(M.exit_callback) == 'function' then
    M.exit_callback()
  end
  M.UpdateWinbarTitles()
end

function Terminal:on_close()
  if self.job and self.job > 0 then
    pcall(vim.fn.jobstop, self.job)
  end
  self.job = nil
  self.buf = nil
end

--- 🌟 RIGID ARCHITECTURE ENGINE PASS FIX:
--- Replaced crude "i" text feeds with atomic Terminal-Mode instruction flags ("nt").
--- This completely isolates your input insertion from terminal prints, stopping prompt leaks.
function Terminal:enter_insert_mode()
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes([[<Cmd>startinsert<CR>]], true, true, true), 'nt', false)
end

function Terminal:send(command)
  local cmd_str = tostring(command or '')
  if not self.win or not vim.api.nvim_win_is_valid(self.win) then
    self:show()
  end
  if not self.job or self.job <= 0 then
    return
  end

  vim.api.nvim_set_current_win(self.win)
  self:enter_insert_mode()
  vim.fn.chansend(self.job, cmd_str .. self.newline)
end

function Terminal:_apply_window_styling()
  if not self.win or not vim.api.nvim_win_is_valid(self.win) then
    return
  end
  vim.api.nvim_set_option_value('number', false, { scope = 'local', win = self.win })
  vim.api.nvim_set_option_value('relativenumber', false, { scope = 'local', win = self.win })
  vim.api.nvim_set_option_value('signcolumn', 'no', { scope = 'local', win = self.win })
  vim.api.nvim_set_option_value('winfixheight', true, { scope = 'local', win = self.win })
end

function Terminal:on_open()
  local target_height = math.ceil(vim.o.lines * (M.config.panel_height or 0.2))
  local opposite_instance = (self.term_type == 'monitor') and M.cli or M.mon

  M.user_splitkeep_cache = vim.go.splitkeep
  vim.go.splitkeep = 'screen'

  self.win = vim.api.nvim_open_win(self.buf, true, {
    split = 'below',
    win = -1,
    height = target_height,
  })

  self:_apply_window_styling()
  self:_register_viewport_mappings(opposite_instance)
end

function Terminal:on_spawn()
  if self.job and self.job > 0 then
    return
  end
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

function Terminal:on_quit()
  if self.win and vim.api.nvim_win_is_valid(self.win) then
    vim.api.nvim_win_close(self.win, true)
  end
  self.win = nil

  if M.user_splitkeep_cache then
    vim.go.splitkeep = M.user_splitkeep_cache
    M.user_splitkeep_cache = nil
  end

  M.RestoreWorkspaceFocus()

  vim.schedule(function()
    local cli = M.cli
    local mon = M.mon
    local target_height = math.ceil(vim.o.lines * (M.config.panel_height or 0.2))
    if cli and cli.win and vim.api.nvim_win_is_valid(cli.win) then
      pcall(vim.api.nvim_win_set_height, cli.win, target_height)
    end
    if mon and mon.win and vim.api.nvim_win_is_valid(mon.win) then
      pcall(vim.api.nvim_win_set_height, mon.win, target_height)
    end
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

function Terminal:show()
  local active_win = vim.api.nvim_get_current_win()
  if vim.api.nvim_win_is_valid(active_win) then
    local active_buf = vim.api.nvim_win_get_buf(active_win)
    local active_ft = vim.api.nvim_get_option_value('filetype', { buf = active_buf })
    local win_type = vim.fn.win_gettype(active_win)

    if
      active_ft ~= self.filetype
      and win_type == ''
      and active_ft ~= 'neo-tree'
      and active_ft ~= 'oil'
      and active_ft ~= 'aerial'
      and active_ft ~= 'pio_workspace'
    then
      self.last_win = active_win
    end
  end

  if not self.buf or not vim.api.nvim_buf_is_valid(self.buf) then
    self:on_create()
  end

  local opposite_instance = (self.term_type == 'monitor') and M.cli or M.mon

  if opposite_instance.win and vim.api.nvim_win_is_valid(opposite_instance.win) then
    self.win = opposite_instance.win
    opposite_instance.win = nil

    vim.api.nvim_win_set_buf(self.win, self.buf)
    vim.api.nvim_set_current_win(self.win)

    if not self.job or self.job <= 0 then
      self:on_spawn()
    end

    self:_apply_window_styling()
    M.UpdateWinbarTitles()
    self:_register_viewport_mappings(opposite_instance)
    self:enter_insert_mode()
    return true
  end

  if self.win and vim.api.nvim_win_is_valid(self.win) then
    vim.api.nvim_set_current_win(self.win)
    self:enter_insert_mode()
    return true
  end

  self:on_open()
  self:on_spawn()

  M.UpdateWinbarTitles()
  return true
end

function Terminal:_register_lifecycle_events(target_height)
  local platformio = vim.api.nvim_create_augroup('PioEvents_' .. self.buf, { clear = true })

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

  vim.api.nvim_create_autocmd({ 'WinNew', 'BufWinEnter', 'WinClosed' }, {
    group = platformio,
    callback = function()
      if self.win and vim.api.nvim_win_is_valid(self.win) then
        vim.schedule(function()
          if self.win and vim.api.nvim_win_is_valid(self.win) then
            vim.go.cmdheight = 1

            local open_wins = vim.api.nvim_tabpage_list_wins(0)
            local valid_wins = 0
            for _, w in ipairs(open_wins) do
              if vim.api.nvim_win_is_valid(w) then
                local b = vim.api.nvim_win_get_buf(w)
                local ft = vim.api.nvim_get_option_value('filetype', { buf = b })
                if ft ~= 'neo-tree' and ft ~= 'oil' and ft ~= 'aerial' then
                  valid_wins = valid_wins + 1
                end
              end
            end

            if valid_wins <= 1 and vim.api.nvim_get_current_win() == self.win then
              if not M.cached_spacer_buf or not vim.api.nvim_buf_is_valid(M.cached_spacer_buf) then
                M.cached_spacer_buf = vim.api.nvim_create_buf(false, true)
                vim.api.nvim_set_option_value('buftype', 'nofile', { buf = M.cached_spacer_buf })
                vim.api.nvim_set_option_value('filetype', 'pio_workspace', { buf = M.cached_spacer_buf })
                vim.api.nvim_set_option_value('bufhidden', 'hide', { buf = M.cached_spacer_buf })
              end

              vim.cmd('noautocmd topleft split')
              vim.api.nvim_win_set_buf(vim.api.nvim_get_current_win(), M.cached_spacer_buf)
              vim.cmd('noautocmd lua vim.api.nvim_set_current_win(' .. self.win .. ')')
            end

            pcall(vim.api.nvim_win_set_height, self.win, target_height)
            M.UpdateWinbarTitles()
          end
        end)
      end
    end,
  })
end

function Terminal:_register_viewport_mappings(opposite_instance)
  local maps = M.config.keymaps

  vim.keymap.set('t', maps.escape_term, [[<C-\><C-n>]], { buffer = self.buf })
  vim.keymap.set('n', maps.hide_pane, function()
    self:on_quit()
  end, { buffer = self.buf })

  -- 🌟 UNIVERSAL UP-NAVIGATION ROUTER FIX:
  -- Combines cached window pointers with a pure atomic C-API fallback pass.
  -- If last_win fails or no files are open, nvim_input forcefully jumps focus straight up.
  vim.keymap.set('t', maps.move_up, function()
    local code_win = self.last_win or opposite_instance.last_win
    if code_win and vim.api.nvim_win_is_valid(code_win) then
      vim.api.nvim_set_current_win(code_win)
    else
      M.RestoreWorkspaceFocus()
      if vim.api.nvim_get_current_win() == self.win then
        vim.api.nvim_input([[<C-\><C-n><C-w>k]])
      end
    end
  end, { buffer = self.buf, silent = true })

  vim.keymap.set('n', maps.move_up, function()
    local code_win = self.last_win or opposite_instance.last_win
    if code_win and vim.api.nvim_win_is_valid(code_win) then
      vim.api.nvim_set_current_win(code_win)
    else
      M.RestoreWorkspaceFocus()
      if vim.api.nvim_get_current_win() == self.win then
        vim.api.nvim_input([[<C-w>k]])
      end
    end
  end, { buffer = self.buf, silent = true })

  vim.keymap.set('t', maps.switch_pane, function()
    local current_winbar = vim.api.nvim_get_option_value('winbar', { scope = 'local' }) or ''
    if current_winbar:find('%[; Hide%]') or current_winbar:find('%[' .. maps.hide_pane .. ' Hide%]') then
      self:on_quit()
      return
    end
    vim.schedule(function()
      opposite_instance:show()
    end)
  end, { buffer = self.buf, silent = true })

  vim.keymap.set('n', maps.switch_pane, function()
    vim.schedule(function()
      opposite_instance:show()
    end)
  end, { buffer = self.buf, silent = true })

  vim.keymap.set('n', maps.move_left, '<C-w>h', { buffer = self.buf })
  vim.keymap.set('n', maps.move_right, '<C-w>l', { buffer = self.buf })

  vim.keymap.set('n', maps.move_down, function()
    local open_check = self.win and vim.api.nvim_win_is_valid(self.win) and vim.api.nvim_win_get_buf(self.win) == self.buf
    if open_check then
      vim.api.nvim_set_current_win(self.win)
      self:enter_insert_mode()
    else
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<C-w>j', true, true, true), 'n', false)
    end
  end, { buffer = self.buf, silent = true })

  vim.keymap.set('t', maps.move_down, [[<C-\><C-n><C-w>j]], { buffer = self.buf, silent = true })
end

M.cli = Terminal.new('cli', ' Pio CLI> ')
M.mon = Terminal.new('monitor', ' Pio Monitor ')

function M.setup(opts)
  M.config = vim.tbl_deep_extend('force', M.config, opts or {})
end

return M

-- local M = {}
--
-- -- Enterprise User Configuration Specification Matrix
-- M.config = {
--   panel_height = 0.2,
--   winbar_bg = '#80a3d4',
--   winbar_fg = '#000000',
--   shell = vim.o.shell,
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
-- -- Unified Winbar Header Redraw Layout Sync Engine Matrix
-- function M.UpdateWinbarTitles()
--   local cli_alive = M.cli and M.cli.buf and vim.api.nvim_buf_is_valid(M.cli.buf)
--   local mon_alive = M.mon and M.mon.buf and vim.api.nvim_buf_is_valid(M.mon.buf)
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
-- -- Dynamic Workspace Target Focus Shifter Router
-- function M.RestoreWorkspaceFocus()
--   local target_win = nil
--   for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
--     if vim.api.nvim_win_is_valid(win) then
--       local buf = vim.api.nvim_win_get_buf(win)
--       local ft = vim.api.nvim_get_option_value('filetype', { buf = buf })
--       local win_type = vim.fn.win_gettype(win)
--
--       if ft ~= 'pio_terminal' and win_type == '' and ft ~= 'neo-tree' and ft ~= 'oil' and ft ~= 'aerial' and ft ~= 'pio_workspace' then
--         target_win = win
--         break
--       end
--     end
--   end
--
--   if target_win then
--     vim.api.nvim_set_current_win(target_win)
--   end
-- end
--
-- ----------------------------------------------------------------------------------------
-- -- THE IMMUTABLE OO TERMINAL CLASS ARCHITECTURE
-- ----------------------------------------------------------------------------------------
-- ---@class Terminal
-- ---@field term_type string Unique structural channel lane tag ('cli' or 'monitor')
-- ---@field title string Explicit text layout template drawn onto the local winbar row
-- ---@field buf number|nil Immutable Neovim native buffer context memory address handle
-- ---@field win number|nil Active viewport layout window node context index pointer
-- ---@field last_win number|nil Explicitly maps the code file window context tracking node
-- ---@field job number|nil Asynchronous background socket process loop channel ID stream
-- ---@field newline string Normalized carriage return terminator sequence delimiters
-- ---@field filetype string Strict isolated text-domain category namespace tag
-- local Terminal = {
--   term_type = '',
--   title = '',
--   buf = nil,
--   win = nil,
--   last_win = nil,
--   job = nil,
--   newline = '\r\n',
--   filetype = 'pio_terminal',
-- }
-- Terminal.__index = Terminal
--
-- function Terminal.new(term_type, panel_title)
--   local self = setmetatable({}, Terminal)
--   self.term_type = term_type
--   self.title = panel_title
--   return self
-- end
--
-- function Terminal:on_create()
--   self.buf = vim.api.nvim_create_buf(false, true)
--   vim.api.nvim_set_option_value('filetype', self.filetype, { buf = self.buf })
--
--   local target_height = math.ceil(vim.o.lines * (M.config.panel_height or 0.2))
--   self:_register_lifecycle_events(target_height)
-- end
--
-- function Terminal:on_stdout(j, d, e)
--   if self.term_type == 'cli' and type(M.stdout_callback) == 'function' then
--     M.stdout_callback(j, d, e)
--   end
-- end
--
-- function Terminal:on_stderr(j, d, e)
--   if self.term_type == 'cli' and type(M.stdout_callback) == 'function' then
--     M.stdout_callback(j, d, e)
--   end
-- end
--
-- function Terminal:on_exit()
--   if type(M.exit_callback) == 'function' then
--     M.exit_callback()
--   end
--   M.UpdateWinbarTitles()
-- end
--
-- function Terminal:on_close()
--   if self.job and self.job > 0 then
--     pcall(vim.fn.jobstop, self.job)
--   end
--   self.job = nil
--   self.buf = nil
-- end
--
-- function Terminal:enter_insert_mode()
--   vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('i', true, true, true), 'n', false)
-- end
--
-- function Terminal:send(command)
--   local cmd_str = tostring(command or '')
--   if not self.win or not vim.api.nvim_win_is_valid(self.win) then
--     self:show()
--   end
--   if not self.job or self.job <= 0 then
--     return
--   end
--
--   vim.api.nvim_set_current_win(self.win)
--   self:enter_insert_mode()
--   vim.fn.chansend(self.job, cmd_str .. self.newline)
-- end
--
-- function Terminal:on_open()
--   local target_height = math.ceil(vim.o.lines * (M.config.panel_height or 0.2))
--   local opposite_instance = (self.term_type == 'monitor') and M.cli or M.mon
--
--   -- Enforce modern scroll preservation mechanics globally before drawing splits
--   vim.go.splitkeep = 'screen'
--
--   -- Anchor the window split container frame directly at the global base floor
--   self.win = vim.api.nvim_open_win(self.buf, true, {
--     split = 'below',
--     win = -1, -- Explicit global tabpage layout tree context node anchor
--     height = target_height,
--   })
--
--   -- Enforce clean, minimalist terminal window styling configurations
--   vim.api.nvim_set_option_value('number', false, { scope = 'local', win = self.win })
--   vim.api.nvim_set_option_value('relativenumber', false, { scope = 'local', win = self.win })
--   vim.api.nvim_set_option_value('signcolumn', 'no', { scope = 'local', win = self.win })
--   vim.api.nvim_set_option_value('winfixheight', true, { scope = 'local', win = self.win })
--
--   self:_register_viewport_mappings(opposite_instance)
-- end
--
-- function Terminal:on_spawn()
--   if self.job and self.job > 0 then
--     return
--   end
--
--   local channel_id = vim.fn.termopen(M.config.shell, {
--     on_stdout = function(j, d, e)
--       self:on_stdout(j, d, e)
--     end,
--     on_stderr = function(j, d, e)
--       self:on_stderr(j, d, e)
--     end,
--     on_exit = function()
--       self:on_exit()
--     end,
--   })
--   self.job = (channel_id and channel_id > 0) and channel_id or nil
-- end
--
-- function Terminal:on_quit()
--   if self.win and vim.api.nvim_win_is_valid(self.win) then
--     vim.api.nvim_win_close(self.win, true)
--   end
--   self.win = nil
--
--   M.RestoreWorkspaceFocus()
--
--   vim.schedule(function()
--     local cli = M.cli
--     local mon = M.mon
--     local target_height = math.ceil(vim.o.lines * (M.config.panel_height or 0.2))
--     if cli and cli.win and vim.api.nvim_win_is_valid(cli.win) then
--       pcall(vim.api.nvim_win_set_height, cli.win, target_height)
--     end
--     if mon and mon.win and vim.api.nvim_win_is_valid(mon.win) then
--       pcall(vim.api.nvim_win_set_height, mon.win, target_height)
--     end
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
-- function Terminal:show()
--   local active_win = vim.api.nvim_get_current_win()
--   if vim.api.nvim_win_is_valid(active_win) then
--     local active_buf = vim.api.nvim_win_get_buf(active_win)
--     local active_ft = vim.api.nvim_get_option_value('filetype', { buf = active_buf })
--     local win_type = vim.fn.win_gettype(active_win)
--
--     if
--       active_ft ~= self.filetype
--       and win_type == ''
--       and active_ft ~= 'neo-tree'
--       and active_ft ~= 'oil'
--       and active_ft ~= 'aerial'
--       and active_ft ~= 'pio_workspace'
--     then
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
--   -- SILKY-SMOOTH WINDOW REUSE: Swaps terminal buffers natively without flashing splits
--   if opposite_instance.win and vim.api.nvim_win_is_valid(opposite_instance.win) then
--     self.win = opposite_instance.win
--     opposite_instance.win = nil
--
--     vim.api.nvim_win_set_buf(self.win, self.buf)
--     vim.api.nvim_set_current_win(self.win)
--
--     if not self.job or self.job <= 0 then
--       self:on_spawn()
--     end
--
--     vim.api.nvim_set_option_value('number', false, { scope = 'local', win = self.win })
--     vim.api.nvim_set_option_value('relativenumber', false, { scope = 'local', win = self.win })
--     vim.api.nvim_set_option_value('signcolumn', 'no', { scope = 'local', win = self.win })
--     vim.api.nvim_set_option_value('winfixheight', true, { scope = 'local', win = self.win })
--
--     M.UpdateWinbarTitles()
--     self:_register_viewport_mappings(opposite_instance)
--     self:enter_insert_mode()
--     return true
--   end
--
--   if self.win and vim.api.nvim_win_is_valid(self.win) then
--     vim.api.nvim_set_current_win(self.win)
--     self:enter_insert_mode()
--     return true
--   end
--
--   self:on_open()
--   self:on_spawn()
--
--   M.UpdateWinbarTitles()
--   return true
-- end
--
-- function Terminal:_register_lifecycle_events(target_height)
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
--   -- INFO: BufUnload
--   vim.api.nvim_create_autocmd('BufUnload', {
--     group = platformio,
--     buffer = self.buf,
--     callback = function(args)
--       vim.keymap.del('t', '<Esc>', { buffer = args.buf })
--       vim.keymap.del('n', '<Esc>', { buffer = args.buf })
--
--       -- clear autommmand when quit
--       vim.api.nvim_clear_autocmds({ group = platformio })
--
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
--   -- Core Programmatic Scroll Tracker: Follows terminal prints down safely
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
--   -- Height Boundary Enforcement Lock
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
--
--   -- FLICKER-FREE STRUCTURAL HEALING SENTINEL ENGINE
--   vim.api.nvim_create_autocmd({ 'WinNew', 'BufWinEnter', 'WinClosed' }, {
--     group = platformio,
--     callback = function()
--       if self.win and vim.api.nvim_win_is_valid(self.win) then
--         vim.schedule(function()
--           if self.win and vim.api.nvim_win_is_valid(self.win) then
--             vim.go.cmdheight = 1
--
--             local open_wins = vim.api.nvim_tabpage_list_wins(0)
--             local valid_wins = 0
--             for _, w in ipairs(open_wins) do
--               if vim.api.nvim_win_is_valid(w) then
--                 local b = vim.api.nvim_win_get_buf(w)
--                 local ft = vim.api.nvim_get_option_value('filetype', { buf = b })
--                 if ft ~= 'neo-tree' and ft ~= 'oil' and ft ~= 'aerial' then
--                   valid_wins = valid_wins + 1
--                 end
--               end
--             end
--
--             if valid_wins <= 1 and vim.api.nvim_get_current_win() == self.win then
--               local scratch_buf = vim.api.nvim_create_buf(false, true)
--
--               -- 🌟 THE INDESTRUCTIBLE FIX: Cleaned out static string name assignments entirely.
--               -- Uses an anonymous layout address tag config parameter to bypass the E95 name crash.
--               vim.api.nvim_set_option_value('buftype', 'nofile', { buf = scratch_buf })
--               vim.api.nvim_set_option_value('filetype', 'pio_workspace', { buf = scratch_buf })
--               vim.api.nvim_set_option_value('bufhidden', 'wipe', { buf = scratch_buf })
--
--               vim.cmd('noautocmd topleft split')
--               vim.api.nvim_win_set_buf(vim.api.nvim_get_current_win(), scratch_buf)
--
--               vim.cmd('noautocmd lua vim.api.nvim_set_current_win(' .. self.win .. ')')
--             end
--
--             pcall(vim.api.nvim_win_set_height, self.win, target_height)
--             M.UpdateWinbarTitles()
--           end
--         end)
--       end
--     end,
--   })
-- end
--
-- function Terminal:_register_viewport_mappings(opposite_instance)
--   local maps = M.config.keymaps
--
--   -- Native Terminal Shortcuts Mapping Configurations
--   vim.keymap.set('t', maps.escape_term, [[<C-\><C-n>]], { buffer = self.buf })
--   vim.keymap.set('n', maps.hide_pane, function()
--     self:on_quit()
--   end, { buffer = self.buf })
--
--   vim.keymap.set('t', maps.move_up, function()
--     local code_win = self.last_win or opposite_instance.last_win
--     if code_win and vim.api.nvim_win_is_valid(code_win) then
--       vim.api.nvim_set_current_win(code_win)
--     else
--       M.RestoreWorkspaceFocus()
--     end
--   end, { buffer = self.buf, silent = true })
--
--   vim.keymap.set('n', maps.move_up, function()
--     local code_win = self.last_win or opposite_instance.last_win
--     if code_win and vim.api.nvim_win_is_valid(code_win) then
--       vim.api.nvim_set_current_win(code_win)
--     else
--       M.RestoreWorkspaceFocus()
--     end
--   end, { buffer = self.buf, silent = true })
--
--   vim.keymap.set('t', maps.switch_pane, function()
--     local current_winbar = vim.api.nvim_get_option_value('winbar', { scope = 'local' }) or ''
--     if current_winbar:find('%[; Hide%]') or current_winbar:find('%[' .. maps.hide_pane .. ' Hide%]') then
--       self:on_quit()
--       return
--     end
--     vim.schedule(function()
--       opposite_instance:show()
--     end)
--   end, { buffer = self.buf, silent = true })
--
--   vim.keymap.set('n', maps.switch_pane, function()
--     vim.schedule(function()
--       opposite_instance:show()
--     end)
--   end, { buffer = self.buf, silent = true })
--
--   -- Cross-Window Standard Tiled Split Navigation Mappings
--   vim.keymap.set('n', maps.move_left, '<C-w>h', { buffer = self.buf })
--   vim.keymap.set('n', maps.move_right, '<C-w>l', { buffer = self.buf })
--
--   vim.keymap.set('n', maps.move_down, function()
--     local open_check = self.win and vim.api.nvim_win_is_valid(self.win) and vim.api.nvim_win_get_buf(self.win) == self.buf
--     if open_check then
--       vim.api.nvim_set_current_win(self.win)
--       self:enter_insert_mode()
--     else
--       vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<C-w>j', true, true, true), 'n', false)
--     end
--   end, { buffer = self.buf, silent = true })
--
--   vim.keymap.set('t', maps.move_down, [[<C-\><C-n><C-w>j]], { buffer = self.buf, silent = true })
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
