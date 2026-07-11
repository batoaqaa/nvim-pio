-- stylua: ignore start
-- nvimpio/device/terminal.lua - Part 1

local M = {}

-- 1. Insulated Cross-Platform Environment Discovery Matrix
local native_shell = OS.shell
local native_eol = OS.eol

-- 2. Enterprise Configuration Specification Matrix
M.config = {
  panel_height = 0.2,
  winbar_bg = '#80a3d4',
  winbar_fg = '#000000',
  winbar_hl_group = 'PioWinBar',
  shell = native_shell,
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
M.terminals = {}

-- Pinned Workspace Tree Sizing Metrics Matrix
M.layout = {
  container_win = nil, -- SINGLE REGULATED SPLIT WINDOW HANDLE
  active_type = nil, -- Current visible terminal key name string
}

--- Pure C-API Highlight winbar renderer (Preserves explicit layout creation order)
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

  local tab_string = string.format("%%#%sDim# ", M.config.winbar_hl_group)
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

  vim.api.nvim_set_option_value('winbar', string.format("%s%%#%sDim#%%=%s", tab_string, M.config.winbar_hl_group, hint), { scope = 'local', win = M.layout.container_win })
end

--- Dynamic Workspace Tree Focus Router Matrix
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
-- HIGH-PERFORMANCE OBJECT-ORIENTED TERMINAL SPECIFICATION
----------------------------------------------------------------------------------------
---@class Terminal
local Terminal = {
  term_type = '',
  title = '',
  buf = nil,
  job = nil,
  newline = native_eol,
  filetype = 'pio_terminal',
  _custom_stdout = nil,
  _is_scrolling = false, -- Atomic Lock: Stops high-speed process outputs from lagging viewports
}
Terminal.__index = Terminal

function Terminal.new(term_type, panel_title, filetype, custom_stdout)
  local self = setmetatable({}, Terminal)
  self.term_type = term_type
  self.title = panel_title
  self.filetype = filetype or ('terminal_' .. term_type)
  self._custom_stdout = custom_stdout
  return self
end

function Terminal:on_create()
  self.buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_option_value('filetype', self.filetype, { buf = self.buf })
  self:_register_viewport_mappings()
  self:_register_viewport_bindings()
end

--- Rigid Focus-Locked Background Process Payload Dispatcher Matrix
function Terminal:send(command)
  local cmd_str = tostring(command or '')
  local original_work_win = vim.api.nvim_get_current_win()

  -- EXTERNAL RESURRECTION DETECTOR: Auto-recreates structural handles if killed by a previous :q!
  local was_dead = not self.buf or not vim.api.nvim_buf_is_valid(self.buf)
  if was_dead then
    self:on_create()
  end

  if not M.layout.container_win or not vim.api.nvim_win_is_valid(M.layout.container_win) or M.layout.active_type ~= self.term_type then
    M.show(self.term_type)
  end

  self:on_spawn()

  if not self.job or self.job <= 0 then
    return
  end

  if cmd_str ~= '' and not cmd_str:match('^%s') then
    cmd_str = ' ' .. cmd_str
  end

  -- ASYNC CONTEXT SCHEDULER GUARD: Throttles text feed on clean channel transformations
  if was_dead then
    vim.schedule(function()
      if self.job and self.job > 0 then
        vim.fn.chansend(self.job, cmd_str .. self.newline)
      end
    end)
  else
    vim.fn.chansend(self.job, cmd_str .. self.newline)
  end

  vim.api.nvim_set_option_value('winbar', vim.api.nvim_get_option_value('winbar', { win = M.layout.container_win }), { win = M.layout.container_win })

  if M.layout.container_win and vim.api.nvim_win_is_valid(M.layout.container_win) and not self._is_scrolling then
    self._is_scrolling = true
    vim.schedule(function()
      if self.buf and vim.api.nvim_buf_is_valid(self.buf) and M.layout.container_win and vim.api.nvim_win_is_valid(M.layout.container_win) then
        local line_count = vim.api.nvim_buf_line_count(self.buf)
        if line_count > 0 then
          pcall(vim.api.nvim_win_set_cursor, M.layout.container_win, { line_count, 0 })
        end
      end
      self._is_scrolling = false
    end)
  end

  vim.api.nvim_input([[<C-\><C-n>]])

  if original_work_win and vim.api.nvim_win_is_valid(original_work_win) then
    pcall(vim.api.nvim_set_current_win, original_work_win)
  end
end

function Terminal:on_spawn()
  if self.job and self.job > 0 then
    return
  end
  local channel_id = vim.fn.termopen(M.config.shell, {
    on_stdout = function(j, d, e) self:on_stdout(j, d, e) end,
    on_stderr = function(j, d, e) self:on_stderr(j, d, e) end,
    on_exit = function() self:on_exit() end,
  })
  self.job = (channel_id and channel_id > 0) and channel_id or nil
end

function Terminal:on_stdout(j, d, e)
  if self._custom_stdout then self._custom_stdout(j, d, e)
  elseif self.term_type == 'cli' and type(M.stdout_callback) == 'function' then
    M.stdout_callback(j, d, e)
  end
end

function Terminal:on_stderr(j, d, e) self:on_stdout(j, d, e) end

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
  if self.buf and vim.api.nvim_buf_is_valid(self.buf) then
    pcall(vim.api.nvim_buf_delete, self.buf, { force = true })
  end
  if self.buf then
    pcall(vim.api.nvim_del_augroup_by_name, 'PioLocalEvents_' .. self.buf)
  end
  self.job = nil
  self.buf = nil
end

function Terminal:on_quit() M.hide() end
function Terminal:hide() M.hide() end

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
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('startinsert', true, false, true), 'n', false)
  end
end

function Terminal:_register_viewport_mappings()
  local maps = M.config.keymaps

  vim.keymap.set('t', maps.escape_term, [[<C-\><C-n>]], { buffer = self.buf, silent = true })

  vim.keymap.set('t', maps.switch_pane, function()
    vim.api.nvim_input([[<C-\><C-n>]])
    M.SwitchTerminalPane()
  end, { buffer = self.buf, silent = true })
  vim.keymap.set('n', maps.switch_pane, function()
    M.SwitchTerminalPane()
  end, { buffer = self.buf, silent = true })

  vim.keymap.set('n', maps.hide_pane, function()
    M.toggle()
  end, { buffer = self.buf })

  vim.keymap.set('t', maps.move_up, [[<C-\><C-n><C-w>k]], { buffer = self.buf, silent = true })
  vim.keymap.set('n', maps.move_up, '<C-w>k', { buffer = self.buf, silent = true })

  vim.keymap.set('n', maps.move_left, '<C-w>h', { buffer = self.buf })
  vim.keymap.set('n', maps.move_right, '<C-w>l', { buffer = self.buf })
end

function Terminal:_register_viewport_bindings()
  local group_id = vim.api.nvim_create_augroup('PioLocalEvents_' .. self.buf, { clear = true })

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



-- nvimpio/device/terminal.lua - Part 3

----------------------------------------------------------------------------------------
-- CORE API ORCHESTRATION INTERFACE LAYER
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

  -- REUSE GATEWAY: Safeguards index arrays from inflating and shifting tab sorting configurations
  if M.terminals[name] then
    M.terminals[name].title = title
    M.terminals[name].filetype = final_filetype
    M.terminals[name]._custom_stdout = final_cb
    M.terminals[name]:on_create()
    return M.terminals[name]
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

  if M.layout.container_win and vim.api.nvim_win_is_valid(M.layout.container_win) then
    local old_win = vim.api.nvim_get_current_win()
    pcall(vim.api.nvim_set_current_win, M.layout.container_win)

    target_instance:_register_viewport_mappings()
    vim.api.nvim_win_set_buf(M.layout.container_win, target_instance.buf)
    M.layout.active_type = term_type

    target_instance:on_spawn()
    M.UpdateWinbarTitles()

    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes([[<C-\><C-n>]], true, true, true), 'n', false)

    if old_win ~= M.layout.container_win then
      pcall(vim.api.nvim_set_current_win, old_win)
    end
    return
  end

  target_instance:on_open()
  target_instance:on_spawn()
  M.UpdateWinbarTitles()

  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes([[<C-\><C-n>]], true, true, true), 'n', false)
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

--- CRITICAL STATEFUL COMMAND DISPATCHER MATRIX (Safely hooks onto :q! targets)
function M.send_and_restore(cmd)
  local was_visible = M.layout.container_win ~= nil and vim.api.nvim_win_is_valid(M.layout.container_win)
  local target_instance = M.terminals.cli
  if not target_instance then
    return
  end

  local was_dead = not target_instance.buf or not vim.api.nvim_buf_is_valid(target_instance.buf)

  if was_dead then
    target_instance:on_create()
  end
  target_instance:on_spawn()

  if was_visible and not was_dead then
    pcall(vim.api.nvim_win_set_buf, M.layout.container_win, target_instance.buf)
    M.layout.active_type = 'cli'
    M.UpdateWinbarTitles()

    if target_instance.job and target_instance.job > 0 then
      vim.fn.chansend(target_instance.job, cmd .. target_instance.newline)
    end

    vim.api.nvim_input([[<C-\><C-n>]])
    return
  end

  local original_work_win = vim.api.nvim_get_current_win()
  local original_exit_callback = M.exit_callback

  M.exit_callback = function()
    M.exit_callback = original_exit_callback
    if type(M.exit_callback) == 'function' then
      M.exit_callback()
    end

    vim.schedule(function()
      M.hide()
      if original_work_win and vim.api.nvim_win_is_valid(original_work_win) then
        pcall(vim.api.nvim_set_current_win, original_work_win)
      else
        M.RestoreWorkspaceFocus()
      end
    end)
  end

  M.show('cli')

  if was_dead then
    vim.schedule(function()
      if target_instance.job and target_instance.job > 0 then
        vim.fn.chansend(target_instance.job, cmd .. target_instance.newline)
      end
    end)
  else
    if target_instance.job and target_instance.job > 0 then
      vim.fn.chansend(target_instance.job, cmd .. target_instance.newline)
    end
  end

  if original_work_win and vim.api.nvim_win_is_valid(original_work_win) then
    pcall(vim.api.nvim_set_current_win, original_work_win)
  end

  vim.api.nvim_input([[<C-\><C-n>]])
end

-- UNIVERSAL INTERACTIVE DIRECTIONAL DOWN NAVIGATOR
vim.keymap.set({ 'n', 'i', 'v' }, '<C-j>', function()
  if M.layout.container_win and vim.api.nvim_win_is_valid(M.layout.container_win) then
    vim.api.nvim_set_current_win(M.layout.container_win)
    vim.api.nvim_input([[<C-\><C-n>]])
  else
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<C-w>j', true, true, true), 'n', false)
  end
end, { silent = true })

function M.setup(opts)
  M.config = vim.tbl_deep_extend('force', M.config, opts or {})
end

----------------------------------------------------------------------------------------
-- SYSTEM FACTORY CHANNELS INITIALIZATION
function M.reopen()
  if (M.terminals['logs']) then M.terminals['logs']:close() end
  if (M.terminals['mon']) then M.terminals['mon']:close() end
  if (M.terminals['cli']) then M.terminals['cli']:close() end

  M.create_terminal('cli', ' CLI ', function(j, d, e)
    if type(M.stdout_callback) == 'function' then
      M.stdout_callback(j, d, e)
    end
  end)
  M.create_terminal('mon', ' Monitor ', nil)
  M.create_terminal('logs', ' OS ', nil)
end
M.reopen()
----------------------------------------------------------------------------------------

setmetatable(M, {
  __index = function(table, key)
    return rawget(table, 'terminals')[key]
  end,
})

return M
-- stylua: ignore end
