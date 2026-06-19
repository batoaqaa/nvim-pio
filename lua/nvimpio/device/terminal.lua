-- nvimpio/device/terminal.lua - Part 1
local M = {}

-- 1. Defend Against Global Environments Missing at Load Time
local safe_shell = (OS and OS.shell) and OS.shell or vim.o.shell
local safe_eol = (OS and OS.eol) and OS.eol or '\n'

-- 2. Enterprise User Configuration Specification Matrix
M.config = {
  panel_height = 0.2,
  winbar_bg = '#80a3d4',
  winbar_fg = '#000000',
  winbar_hl_group = 'PioWinBar',
  shell = safe_shell,
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

-- Dictionary keeping track of ALL dynamically registered terminals
M.terminals = {}

-- The Core Tiled Window Layout Node Matrix
M.layout = {
  container_win = nil, -- THE SINGLE IMMUTABLE TILED GRID WINDOW HANDLE
  active_type = nil, -- Tracks the name key of the visible node
}

--- Pure C-API Highlight winbar renderer (Dynamic Multi-Tab Layout Engine)
function M.UpdateWinbarTitles()
  local maps = M.config.keymaps

  vim.api.nvim_set_hl(0, M.config.winbar_hl_group, { bg = M.config.winbar_bg, fg = M.config.winbar_fg, bold = true })
  vim.api.nvim_set_hl(0, M.config.winbar_hl_group .. 'Dim', { bg = M.config.winbar_bg, fg = '#4e5a6b', italic = true })

  if not M.layout.container_win or not vim.api.nvim_win_is_valid(M.layout.container_win) then
    return
  end

  local ordered_terminals = {}
  for _, term in pairs(M.terminals) do
    if term.buf and vim.api.nvim_buf_is_valid(term.buf) then
      table.insert(ordered_terminals, term)
    end
  end

  table.sort(ordered_terminals, function(a, b)
    return (a._creation_index or 0) < (b._creation_index or 0)
  end)

  local tab_string = ' '
  local total_terminals = 0

  for _, term in ipairs(ordered_terminals) do
    total_terminals = total_terminals + 1
    local name = term.term_type
    if M.layout.active_type == name then
      tab_string = tab_string .. string.format('%%#%s# [%s] %%*', M.config.winbar_hl_group, term.title:gsub('%s+', ''))
    else
      tab_string = tab_string .. string.format('%%#%sDim#  %s  %%*', M.config.winbar_hl_group, term.title:gsub('%s+', ''))
    end
  end

  local hint = (total_terminals > 1) and string.format(' [ %s  Switch;  %s  Hide; :q! Quit ] ', maps.switch_pane, maps.hide_pane)
    or string.format(' [ %s  Hide; :q! Quit ] ', maps.hide_pane)

  vim.api.nvim_set_option_value('winbar', tab_string .. '%=' .. hint, { scope = 'local', win = M.layout.container_win })
end

--- Dynamic Workspace Tree Focus Router
function M.RestoreWorkspaceFocus()
  local target_win = nil
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.api.nvim_win_is_valid(win) then
      local buf = vim.api.nvim_win_get_buf(win)
      local ft = vim.api.nvim_get_option_value('filetype', { buf = buf })
      local win_type = vim.fn.win_gettype(win)

      if
        ft ~= 'pio_terminal'
        and win_type == ''
        and ft ~= 'neo-tree'
        and ft ~= 'oil'
        and ft ~= 'aerial'
        and ft ~= 'pio_workspace'
        and not ft:match('^terminal_')
      then
        target_win = win
        break
      end
    end
  end

  if target_win then
    vim.api.nvim_set_current_win(target_win)
  end
end

-- nvimpio/device/terminal.lua - Part 2

----------------------------------------------------------------------------------------
-- OBJECT ORIENTED TERMINAL CLASS BLUEPRINT
----------------------------------------------------------------------------------------
---@class Terminal
local Terminal = {
  term_type = '',
  title = '',
  buf = nil,
  job = nil,
  newline = safe_eol,
  filetype = 'pio_terminal',
  _custom_stdout = nil,
}
Terminal.__index = Terminal

function Terminal.new(term_type, panel_title, filetype, custom_stdout)
  local self = setmetatable({}, Terminal)
  self.term_type = term_type
  self.title = panel_title

  -- Enforce explicit evaluation boundaries to eliminate expression ambiguity
  self.filetype = filetype or ('terminal_' .. term_type)

  self._custom_stdout = custom_stdout
  return self
end

function Terminal:on_create()
  self.buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_option_value('filetype', self.filetype, { buf = self.buf })
  self:_register_viewport_bindings()
end

-- FIXED FOCUS-LOCKED SEND METHOD
-- Sends commands entirely in the background. It updates the terminal screen layout
-- in real-time below, but completely leaves your active file buffer focus untouched.
function Terminal:send(command)
  local cmd_str = tostring(command or '')

  -- Save your active work window handle before any properties shift
  local original_work_win = vim.api.nvim_get_current_win()

  -- If the lower split is closed or showing a different tab, pull open the split layout safely
  if not M.layout.container_win or not vim.api.nvim_win_is_valid(M.layout.container_win) or M.layout.active_type ~= self.term_type then
    M.show(self.term_type)
  end

  if not self.job or self.job <= 0 then
    return
  end

  -- 1. CRITICAL: Dispatch text command payload downstream directly into process pipe channel.
  -- Bypassing window focus alterations keeps your typing context safe.
  vim.fn.chansend(self.job, cmd_str .. self.newline)

  -- 2. Force normal mode layout enforcement inside the lower split window container context
  vim.cmd('noautocmd stopinsert')

  -- 3. Hard-restore cursor focus back into the user's active file buffer instantly
  if original_work_win and vim.api.nvim_win_is_valid(original_work_win) then
    pcall(vim.api.nvim_set_current_win, original_work_win)
  end
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

function Terminal:on_stdout(j, d, e)
  if self._custom_stdout then
    self._custom_stdout(j, d, e)
  elseif self.term_type == 'cli' and type(M.stdout_callback) == 'function' then
    M.stdout_callback(j, d, e)
  end
end

function Terminal:on_stderr(j, d, e)
  self:on_stdout(j, d, e)
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

function Terminal:on_quit()
  M.hide()
end
function Terminal:hide()
  M.hide()
end

function Terminal:close()
  self:on_close()
  M.hide()
end

function Terminal:on_open()
  local target_height = math.ceil(vim.o.lines * (M.config.panel_height or 0.2))

  vim.go.splitkeep = 'screen'
  M.layout.container_win = vim.api.nvim_open_win(self.buf, true, {
    split = 'below',
    win = -1,
    height = target_height,
  })
  M.layout.active_type = self.term_type

  vim.api.nvim_set_option_value('number', false, { scope = 'local', win = M.layout.container_win })
  vim.api.nvim_set_option_value('relativenumber', false, { scope = 'local', win = M.layout.container_win })
  vim.api.nvim_set_option_value('signcolumn', 'no', { scope = 'local', win = M.layout.container_win })
  vim.api.nvim_set_option_value('winfixheight', true, { scope = 'local', win = M.layout.container_win })

  self:_register_viewport_mappings()
end

function Terminal:enter_insert_mode()
  if M.layout.container_win and vim.api.nvim_win_is_valid(M.layout.container_win) then
    vim.api.nvim_set_current_win(M.layout.container_win)
    vim.cmd('startinsert')
  end
end

function Terminal:_register_viewport_mappings()
  local maps = M.config.keymaps

  -- TERMINAL ESCAPE ACTION
  vim.keymap.set('t', maps.escape_term, [[<C-\><C-n>]], { buffer = self.buf, silent = true })

  -- DYNAMIC TERMINAL SWITCHING
  vim.keymap.set('t', maps.switch_pane, function()
    vim.cmd([[noautocmd stopinsert]])
    M.SwitchTerminalPane()
  end, { buffer = self.buf, silent = true })
  vim.keymap.set('n', maps.switch_pane, function()
    M.SwitchTerminalPane()
  end, { buffer = self.buf, silent = true })

  -- INTERACTIVE PANE HIDING
  vim.keymap.set('t', maps.hide_pane, function()
    vim.cmd([[noautocmd stopinsert]])
    M.toggle()
  end, { buffer = self.buf, silent = true })
  vim.keymap.set('n', maps.hide_pane, function()
    M.toggle()
  end, { buffer = self.buf })

  -- INTERACTIVE DIRECTIONAL UP SHIFT
  vim.keymap.set('t', maps.move_up, [[<C-\><C-n><C-w>k]], { buffer = self.buf, silent = true })
  vim.keymap.set('n', maps.move_up, '<C-w>k', { buffer = self.buf, silent = true })

  -- HORIZONTAL NAVIGATORS
  vim.keymap.set('n', maps.move_left, '<C-w>h', { buffer = self.buf })
  vim.keymap.set('n', maps.move_right, '<C-w>l', { buffer = self.buf })
end
-- stylua: ignore end

-- nvimpio/device/terminal.lua - Part 3

function Terminal:_register_viewport_bindings()
  local group_id = vim.api.nvim_create_augroup('PioLocalEvents_' .. self.buf, { clear = true })

  -- Intercept manual command exits (:q and :q!)
  vim.api.nvim_create_autocmd('CmdlineLeave', {
    group = group_id,
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

  vim.api.nvim_create_autocmd('WinLeave', {
    group = group_id,
    buffer = self.buf,
    callback = function()
      vim.schedule(function()
        M.UpdateWinbarTitles()
      end)
    end,
  })

  -- FIXED WORKSPACE GUARD: Safely releases window parameters upon manual pane closure
  vim.api.nvim_create_autocmd('WinClosed', {
    group = group_id,
    callback = function()
      if not M.layout.container_win or not vim.api.nvim_win_is_valid(M.layout.container_win) then
        return
      end

      local closed_win = tonumber(vim.fn.expand('<amatch>'))
      if closed_win == M.layout.container_win then
        M.layout.container_win = nil
        M.layout.active_type = nil
      end
    end,
  })
end

----------------------------------------------------------------------------------------
-- GLOBAL SINGLETON WORKSPACE MANAGER INTERFACE
----------------------------------------------------------------------------------------

function M.create_terminal(name, title, filetype_or_cb, custom_stdout)
  local final_filetype = nil
  local final_cb = nil

  if type(filetype_or_cb) == 'function' then
    final_cb = filetype_or_cb
    final_filetype = 'terminal_' .. name
  else
    final_filetype = filetype_or_cb or ('terminal_' .. name)
    final_cb = custom_stdout
  end

  local current_count = 0
  for _ in pairs(M.terminals) do
    current_count = current_count + 1
  end

  M.terminals[name] = Terminal.new(name, title, final_filetype, final_cb)
  M.terminals[name]._creation_index = current_count + 1

  M[name] = M.terminals[name]

  M.terminals[name]:on_create()
  return M.terminals[name]
end

function M.show(term_type)
  if not term_type then
    term_type = next(M.terminals)
  end
  local target_instance = M.terminals[term_type]
  if not target_instance then
    return
  end

  if not target_instance.buf or not vim.api.nvim_buf_is_valid(target_instance.buf) then
    target_instance:on_create()
  end

  -- Standard manual interaction router: Intentionally moves focus into the terminal zone
  if M.layout.container_win and vim.api.nvim_win_is_valid(M.layout.container_win) then
    local old_win = vim.api.nvim_get_current_win()
    pcall(vim.api.nvim_set_current_win, M.layout.container_win)

    target_instance:_register_viewport_mappings()
    vim.api.nvim_win_set_buf(M.layout.container_win, target_instance.buf)
    M.layout.active_type = term_type

    target_instance:on_spawn()
    M.UpdateWinbarTitles()
    vim.cmd('stopinsert')

    if old_win ~= M.layout.container_win then
      pcall(vim.api.nvim_set_current_win, old_win)
    end
    return
  end

  target_instance:on_open()
  target_instance:on_spawn()
  M.UpdateWinbarTitles()
  vim.cmd('stopinsert')
end

function M.hide()
  if M.layout.container_win and vim.api.nvim_win_is_valid(M.layout.container_win) then
    pcall(vim.api.nvim_win_close, M.layout.container_win, true)
  end
  M.layout.container_win = nil
  M.layout.active_type = nil
  M.RestoreWorkspaceFocus()
end

function M.toggle()
  if M.layout.container_win and vim.api.nvim_win_is_valid(M.layout.container_win) then
    M.hide()
  else
    M.show(M.layout.active_type or 'cli')
  end
end

function Terminal:show()
  M.show(self.term_type)
end

function M.SwitchTerminalPane()
  local ordered_keys = {}
  for k, _ in pairs(M.terminals) do
    table.insert(ordered_keys, k)
  end

  table.sort(ordered_keys, function(a, b)
    local term_a = M.terminals[a]
    local term_b = M.terminals[b]
    return (term_a._creation_index or 0) < (term_b._creation_index or 0)
  end)

  if #ordered_keys <= 1 then
    return
  end

  local current_index = 1
  for i, k in ipairs(ordered_keys) do
    if k == M.layout.active_type then
      current_index = i
      break
    end
  end

  local next_index = (current_index % #ordered_keys) + 1
  M.show(ordered_keys[next_index])
end

function M.IsTerminalOpen()
  return M.layout.container_win ~= nil and vim.api.nvim_win_is_valid(M.layout.container_win)
end

--- CRITICAL CRASH-PROOF FOCUS-LOCKED COMMAND PAYLOAD DISPATCHER
--- Updates layout split states and shifts tab text strings in real-time, but programmatically
--- bars your typing cursor context from ever shifting down into Terminal Insert mode.
---@param cmd string The shell payload command text string to execute
function M.send_and_restore(cmd)
  local original_work_win = vim.api.nvim_get_current_win()
  local was_visible = M.layout.container_win ~= nil and vim.api.nvim_win_is_valid(M.layout.container_win)

  local target_instance = M.terminals.cli
  if not target_instance then
    return
  end

  -- Guarantee target allocation buffers and underlying process pipes are initialized cleanly
  if not target_instance.buf or not vim.api.nvim_buf_is_valid(target_instance.buf) then
    target_instance:on_create()
  end
  target_instance:on_spawn()

  -- CASE 1: Lower terminal layout split is ALREADY open on 'mon' or 'logs'
  if was_visible then
    -- Swap layout views cleanly via pure low-level C-API (Bypasses cursor focus changes completely)
    pcall(vim.api.nvim_win_set_buf, M.layout.container_win, target_instance.buf)
    M.layout.active_type = 'cli'
    M.UpdateWinbarTitles()

    -- Dispatch compilation data straight down your background process pipe channel channel instantly
    if target_instance.job and target_instance.job > 0 then
      vim.fn.chansend(target_instance.job, cmd .. target_instance.newline)
    end

    -- Force normal mode state limits to prevent Neovim from launching insert mode triggers
    vim.api.nvim_buf_call(target_instance.buf, function()
      vim.cmd('noautocmd stopinsert')
    end)

    -- Double-insulate focus bounds back up inside your active text buffer window handle
    if original_work_win and vim.api.nvim_win_is_valid(original_work_win) then
      pcall(vim.api.nvim_set_current_win, original_work_win)
    end
    return
  end

  -- CASE 2: Lower terminal layout split was hidden when command was issued
  local original_exit_callback = M.exit_callback
  M.exit_callback = function()
    M.exit_callback = original_exit_callback
    if type(M.exit_callback) == 'function' then
      M.exit_callback()
    end

    -- Dismiss panel layout once the compiling action drops off the channel
    vim.schedule(function()
      M.hide()
      if original_work_win and vim.api.nvim_win_is_valid(original_work_win) then
        pcall(vim.api.nvim_set_current_win, original_work_win)
      else
        M.RestoreWorkspaceFocus()
      end
    end)
  end

  -- Open the layout below using standalone builders to completely shield against recursive require leaks
  local target_height = math.ceil(vim.o.lines * (M.config.panel_height or 0.2))
  vim.go.splitkeep = 'screen'

  M.layout.container_win = vim.api.nvim_open_win(target_instance.buf, true, {
    split = 'below',
    win = -1,
    height = target_height,
  })
  M.layout.active_type = 'cli'

  vim.api.nvim_set_option_value('number', false, { scope = 'local', win = M.layout.container_win })
  vim.api.nvim_set_option_value('relativenumber', false, { scope = 'local', win = M.layout.container_win })
  vim.api.nvim_set_option_value('signcolumn', 'no', { scope = 'local', win = M.layout.container_win })
  vim.api.nvim_set_option_value('winfixheight', true, { scope = 'local', win = M.layout.container_win })

  target_instance:_register_viewport_mappings()
  M.UpdateWinbarTitles()

  -- Dispatch compilation instructions down the running job pipe
  if target_instance.job and target_instance.job > 0 then
    vim.fn.chansend(target_instance.job, cmd .. target_instance.newline)
  end

  -- Force stop insert tracking mode and jump your cursor back up instantly
  vim.cmd('noautocmd stopinsert')
  if original_work_win and vim.api.nvim_win_is_valid(original_work_win) then
    pcall(vim.api.nvim_set_current_win, original_work_win)
  end
end

-- UNIVERSAL INTERACTIVE DIRECTIONAL DOWN NAVIGATOR
vim.keymap.set({ 'n', 'i', 'v' }, '<C-j>', function()
  if M.layout.container_win and vim.api.nvim_win_is_valid(M.layout.container_win) then
    vim.api.nvim_set_current_win(M.layout.container_win)
    vim.cmd('stopinsert')
  else
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<C-w>j', true, true, true), 'n', false)
  end
end, { silent = true })

function M.setup(opts)
  M.config = vim.tbl_deep_extend('force', M.config, opts or {})
end

----------------------------------------------------------------------------------------
-- SYSTEM FACTORY CHANNELS INITIALIZATION
----------------------------------------------------------------------------------------
M.create_terminal('cli', ' Pio CLI ', function(j, d, e)
  if type(M.stdout_callback) == 'function' then
    M.stdout_callback(j, d, e)
  end
end)

M.create_terminal('mon', ' Pio monitor ', nil)
M.create_terminal('logs', ' Target Logs ', nil)

setmetatable(M, {
  __index = function(table, key)
    return rawget(table, 'terminals')[key]
  end,
})

return M
-- stylua: ignore end
