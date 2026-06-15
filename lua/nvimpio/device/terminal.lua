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

-- The Core Sovereign Layout Management State
M.layout = {
  panel_win = nil, -- The absolute foreground floating terminal view window
  dummy_win = nil, -- The native tiled background spacer window that shrinks code splits upward
  active_type = nil, -- Tracks visible node ('cli' or 'monitor')
}

--- Pure C-API Highlight winbar renderer
function M.UpdateWinbarTitles()
  local cli_alive = M.cli and M.cli.buf and vim.api.nvim_buf_is_valid(M.cli.buf)
  local mon_alive = M.mon and M.mon.buf and vim.api.nvim_buf_is_valid(M.mon.buf)
  local maps = M.config.keymaps

  local hint = (cli_alive and mon_alive) and string.format('[ %s  Switch;  %s  Hide; :q! Quit ] ', maps.switch_pane, maps.hide_pane)
    or string.format('[ %s  Hide; :q! Quit ] ', maps.hide_pane)

  vim.api.nvim_set_hl(0, 'PioWinBar', { bg = M.config.winbar_bg, fg = M.config.winbar_fg })

  if M.layout.panel_win and vim.api.nvim_win_is_valid(M.layout.panel_win) then
    local title = (M.layout.active_type == 'monitor') and M.mon.title or M.cli.title
    vim.api.nvim_set_option_value('winbar', '%#PioWinBar#' .. title .. hint .. '%*', { scope = 'local', win = M.layout.panel_win })
  end
end

--- Dynamic Workspace Tree Router
function M.RestoreWorkspaceFocus()
  local target_win = nil
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.api.nvim_win_is_valid(win) then
      local buf = vim.api.nvim_win_get_buf(win)
      local ft = vim.api.nvim_get_option_value('filetype', { buf = buf })
      local win_type = vim.fn.win_gettype(win)

      if ft ~= 'pio_terminal' and win_type == '' and ft ~= 'neo-tree' and ft ~= 'oil' and ft ~= 'aerial' and ft ~= 'pio_spacer' then
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
-- OBJECT ORIENTED TERMINAL CLASS BLUEPRINT
----------------------------------------------------------------------------------------
---@class Terminal
---@field term_type string Unique structural channel lane tag ('cli' or 'monitor')
---@field title string Explicit winbar tracking text template
---@field buf number|nil Native Neovim buffer ID handle
---@field job number|nil Background terminal channel process loop stream ID
---@field newline string Carriage return line delimiter sequence
---@field filetype string Strict isolated text-domain category namespace tag
local Terminal = {
  term_type = '',
  title = '',
  buf = nil,
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
  self:_register_lifecycle_events()
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

function Terminal:enter_insert_mode()
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes([[<Cmd>startinsert<CR>]], true, true, true), 'nt', false)
end

function Terminal:send(command)
  local cmd_str = tostring(command or '')
  if not M.layout.panel_win or not vim.api.nvim_win_is_valid(M.layout.panel_win) then
    M.ShowTerminal(self.term_type)
  end
  if not self.job or self.job <= 0 then
    return
  end

  vim.api.nvim_set_current_win(M.layout.panel_win)
  self:enter_insert_mode()
  vim.fn.chansend(self.job, cmd_str .. self.newline)
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

function Terminal:_register_lifecycle_events()
  local platformio = vim.api.nvim_create_augroup('PioEvents_' .. self.buf, { clear = true })

  -- Scroll Tracker: Automatically scrolls terminal view to the absolute bottom row context safely
  vim.api.nvim_create_autocmd({ 'TextChanged', 'TextChangedI' }, {
    group = platformio,
    buffer = self.buf,
    callback = function()
      if M.layout.panel_win and vim.api.nvim_win_is_valid(M.layout.panel_win) then
        local win_buf = vim.api.nvim_win_get_buf(M.layout.panel_win)
        if win_buf == self.buf then
          local lines = vim.api.nvim_buf_line_count(self.buf)
          pcall(vim.api.nvim_win_set_cursor, M.layout.panel_win, { lines, 0 })
        end
      end
    end,
  })
end

function Terminal:show()
  M.ShowTerminal(self.term_type)
  return true
end

function Terminal:_register_viewport_mappings()
  local maps = M.config.keymaps

  vim.keymap.set('t', maps.escape_term, [[<C-\><C-n>]], { buffer = self.buf })
  vim.keymap.set('n', maps.hide_pane, function()
    M.ToggleTerminal()
  end, { buffer = self.buf })

  -- Absolute navigation commands that bypass layout variables entirely
  vim.keymap.set('t', maps.move_up, function()
    M.RestoreWorkspaceFocus()
  end, { buffer = self.buf, silent = true })
  vim.keymap.set('n', maps.move_up, function()
    M.RestoreWorkspaceFocus()
  end, { buffer = self.buf, silent = true })

  vim.keymap.set('t', maps.switch_pane, function()
    M.SwitchTerminalPane()
  end, { buffer = self.buf, silent = true })
  vim.keymap.set('n', maps.switch_pane, function()
    M.SwitchTerminalPane()
  end, { buffer = self.buf, silent = true })

  vim.keymap.set('n', maps.move_left, '<C-w>h', { buffer = self.buf })
  vim.keymap.set('n', maps.move_right, '<C-w>l', { buffer = self.buf })
end

----------------------------------------------------------------------------------------
-- THE GLOBAL LAYER OVERRIDE MANAGER (THE ROBUST SOLUTION)
----------------------------------------------------------------------------------------

function M.ShowTerminal(term_type)
  term_type = term_type or 'cli'
  local target_instance = (term_type == 'monitor') and M.mon or M.cli

  if not target_instance.buf or not vim.api.nvim_buf_is_valid(target_instance.buf) then
    target_instance:on_create()
  end

  local total_cols = vim.o.columns
  local total_lines = vim.o.lines
  local target_height = math.ceil(total_lines * (M.config.panel_height or 0.2))
  local row_placement = total_lines - target_height - (vim.o.laststatus > 0 and 2 or 1) - vim.o.cmdheight

  -- 1. If the horizontal container window is open, switch buffers cleanly inside it!
  if M.layout.panel_win and vim.api.nvim_win_is_valid(M.layout.panel_win) then
    vim.api.nvim_win_set_buf(M.layout.panel_win, target_instance.buf)
    M.layout.active_type = term_type
    target_instance:on_spawn()
    target_instance:_register_viewport_mappings()
    M.UpdateWinbarTitles()
    target_instance:enter_insert_mode()
    return
  end

  -- 2. Open an unlisted, un-swappable TILED split container to reserve space.
  local spacer_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_option_value('buftype', 'nofile', { buf = spacer_buf })
  vim.api.nvim_set_option_value('filetype', 'pio_spacer', { buf = spacer_buf })
  vim.api.nvim_set_option_value('bufhidden', 'wipe', { buf = spacer_buf })

  vim.go.splitkeep = 'screen'
  M.layout.dummy_win = vim.api.nvim_open_win(spacer_buf, false, {
    split = 'below',
    win = -1,
    height = target_height,
  })
  vim.api.nvim_set_option_value('winfixheight', true, { scope = 'local', win = M.layout.dummy_win })

  -- 3. Draw the actual absolute terminal layer directly over our reserved tiled split window gap.
  M.layout.panel_win = vim.api.nvim_open_win(target_instance.buf, true, {
    relative = 'editor',
    row = row_placement,
    col = 0,
    width = total_cols,
    height = target_height,
    style = 'minimal',
    border = 'none',
  })
  M.layout.active_type = term_type

  -- 🌟 FIXED PROPERTY NODE SPECIFICATION:
  -- All options now uniformly target M.layout.panel_win. 'self.win' is completely removed.
  vim.api.nvim_set_option_value('number', false, { scope = 'local', win = M.layout.panel_win })
  vim.api.nvim_set_option_value('relativenumber', false, { scope = 'local', win = M.layout.panel_win })
  vim.api.nvim_set_option_value('signcolumn', 'no', { scope = 'local', win = M.layout.panel_win })

  target_instance:on_spawn()
  target_instance:_register_viewport_mappings()
  M.UpdateWinbarTitles()
  target_instance:enter_insert_mode()
end

function M.HideTerminal()
  if M.layout.panel_win and vim.api.nvim_win_is_valid(M.layout.panel_win) then
    vim.api.nvim_win_close(M.layout.panel_win, true)
  end
  if M.layout.dummy_win and vim.api.nvim_win_is_valid(M.layout.dummy_win) then
    vim.api.nvim_win_close(M.layout.dummy_win, true)
  end
  M.layout.panel_win = nil
  M.layout.dummy_win = nil
  M.layout.active_type = nil
end

function M.ToggleTerminal()
  if M.layout.panel_win and vim.api.nvim_win_is_valid(M.layout.panel_win) then
    M.HideTerminal()
  else
    M.ShowTerminal('cli')
  end
end

function M.SwitchTerminalPane()
  local next_type = (M.layout.active_type == 'cli') and 'monitor' or 'cli'
  M.ShowTerminal(next_type)
end

function M.IsTerminalOpen()
  return M.layout.panel_win ~= nil and vim.api.nvim_win_is_valid(M.layout.panel_win)
end

--- Singletons Instantiations
M.cli = Terminal.new('cli', ' Pio CLI> ')
M.mon = Terminal.new('monitor', ' Pio Monitor ')

-- UNIVERSAL INTERACTIVE DIRECTIONAL DOWN NAVIGATOR
vim.keymap.set({ 'n', 'i', 'v' }, M.config.keymaps.move_down, function()
  if M.layout.panel_win and vim.api.nvim_win_is_valid(M.layout.panel_win) then
    vim.api.nvim_set_current_win(M.layout.panel_win)
    local active_instance = (M.layout.active_type == 'monitor') and M.mon or M.cli
    active_instance:enter_insert_mode()
  else
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<C-w>j', true, true, true), 'n', false)
  end
end, { silent = true, desc = 'Universal Edge-Pinned Panel Down Navigation Router' })

function M.setup(opts)
  M.config = vim.tbl_deep_extend('force', M.config, opts or {})
end

return M
