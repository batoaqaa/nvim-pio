-- stylua: ignore start
---@brief [[
--- nvimpio/device/terminal.lua - Production-Grade Asynchronous Terminal Manager
---@brief ]]

local M = {}

----------------------------------------------------------------------------------------
-- 1. CONFIGURATION & ENVIRONMENT SETUP
----------------------------------------------------------------------------------------
local OS = _G.OS or (pcall(require, 'nvimpio.osInfo') and _G.OS or {})
local native_shell = OS.shell or (vim.fn.has('win32') == 1 and 'pwsh' or 'sh')
local native_eol = OS.eol or '\n'

---@class TerminalKeymaps
---@field hide_pane string
---@field switch_pane string
---@field escape_term string
---@field move_up string
---@field move_down string
---@field move_left string
---@field move_right string

---@class TerminalConfig
---@field panel_height number
---@field winbar_bg string|nil
---@field winbar_fg string|nil
---@field winbar_hl_group string
---@field shell table|string
---@field ignored_filetypes string[]
---@field ignored_patterns string[]
---@field keymaps TerminalKeymaps

---@type TerminalConfig
M.config = {
  panel_height = 0.2,
  winbar_bg = nil, -- Inherit or default dynamically
  winbar_fg = nil,
  winbar_hl_group = 'PioWinBar',
  shell = native_shell,
  ignored_filetypes = {
    'nvim-tree',
    'neo-tree',
    'oil',
    'aerial',
    'pio_terminal',
  },
  ignored_patterns = {
    '^terminal_',
    '^pio_pane_',
  },
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
M.terminals = {}

---@class TerminalLayout
---@field container_win integer|nil
---@field active_type string|nil
---@field code_win integer|nil
M.layout = {
  container_win = nil,
  active_type = nil,
  code_win = nil,
}

----------------------------------------------------------------------------------------
-- 2. DYNAMIC LAYOUT & WINDOW RESOLUTION ENGINE
----------------------------------------------------------------------------------------

--- Dynamically inspects the workspace to find an active file tree window
---@return integer|nil
local function find_tree_window()
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.api.nvim_win_is_valid(win) then
      local buf = vim.api.nvim_win_get_buf(win)
      local ft = vim.api.nvim_get_option_value('filetype', { buf = buf })
      local bufname = vim.api.nvim_buf_get_name(buf)
      if ft == 'nvim-tree' or ft == 'neo-tree' or bufname:match('NvimTree') or bufname:match('neo%-tree') then
        return win
      end
    end
  end
  return nil
end

--- Dynamically evaluates the best code window based on configuration filters
---@return integer|nil
local function find_best_code_window()
  local ignored_fts = M.config.ignored_filetypes or {}
  local ignored_patterns = M.config.ignored_patterns or {}

  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.api.nvim_win_is_valid(win) and win ~= M.layout.container_win then
      local buf = vim.api.nvim_win_get_buf(win)
      local ft = vim.api.nvim_get_option_value('filetype', { buf = buf })
      local bufname = vim.api.nvim_buf_get_name(buf)
      local win_type = vim.fn.win_gettype(win)

      if win_type == '' and not find_tree_window() == win then
        local is_ignored = false
        for _, ignored in ipairs(ignored_fts) do
          if ft == ignored then is_ignored = true; break end
        end
        if not is_ignored then
          for _, pat in ipairs(ignored_patterns) do
            if ft:match(pat) then is_ignored = true; break end
          end
        end

        if not is_ignored then return win end
      end
    end
  end
  return nil
end

--- Professional Winbar Renderer with automatic fallback highlighting
---@return nil
function M.UpdateWinbarTitles()
  local maps = M.config.keymaps
  local hl = M.config.winbar_hl_group

  -- Fallback or custom highlight generation
  if M.config.winbar_bg then
    vim.api.nvim_set_hl(0, hl, { bg = M.config.winbar_bg, fg = M.config.winbar_fg or '#000000', bold = true })
    vim.api.nvim_set_hl(0, hl .. 'Dim', { bg = M.config.winbar_bg, fg = '#4e5a6b', italic = true })
  else
    vim.api.nvim_set_hl(0, hl, { link = 'StatusLine', bold = true })
    vim.api.nvim_set_hl(0, hl .. 'Dim', { link = 'Comment', italic = true })
  end

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

  local tab_string = string.format('%%#%sDim# ', hl)
  local total_terminals = 0

  for _, term in ipairs(ordered_terminals) do
    total_terminals = total_terminals + 1
    local name = term.term_type
    local clean_title = term.title:gsub('%s+', '')
    if M.layout.active_type == name then
      tab_string = tab_string .. string.format('%%#%s# [%s] %%*', hl, clean_title)
    else
      tab_string = tab_string .. string.format('%%#%sDim#  %s  %%*', hl, clean_title)
    end
  end

  local hint = (total_terminals > 1) and string.format(' [ %s  Switch;  %s  Hide; :q! Quit ] ', maps.switch_pane, maps.hide_pane)
    or string.format(' [ %s  Hide; :q! Quit ] ', maps.hide_pane)

  vim.api.nvim_set_option_value(
    'winbar',
    string.format('%s%%#%sDim#%%=%s', tab_string, hl, hint),
    { scope = 'local', win = M.layout.container_win }
  )
end

function M.RestoreWorkspaceFocus()
  local target_win = find_best_code_window()
  if target_win and vim.api.nvim_win_is_valid(target_win) then
    vim.api.nvim_set_current_win(target_win)
  end
end

----------------------------------------------------------------------------------------
-- 3. OBJECT-ORIENTED TERMINAL SPECIFICATION
----------------------------------------------------------------------------------------
---@class Terminal
---@field term_type string
---@field title string
---@field buf integer|nil
---@field job integer|nil
---@field newline string
---@field filetype string
---@field _custom_stdout fun(job_id: integer, data: string[], event: string)|nil
---@field _on_next_exit fun()|nil
---@field _is_scrolling boolean
---@field _creation_index integer|nil
local Terminal = {
  term_type = '',
  title = '',
  buf = nil,
  job = nil,
  newline = native_eol,
  filetype = 'pio_terminal',
  _custom_stdout = nil,
  _on_next_exit = nil,
  _is_scrolling = false,
  _creation_index = nil,
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

  local target_shell = M.config.shell or native_shell
  if type(target_shell) == 'table' and target_shell.program then
    target_shell = target_shell.program
  end

  vim.api.nvim_buf_call(self.buf, function()
    local channel_id = vim.fn.termopen(target_shell, {
      on_stdout = function(j, d, e) self:on_stdout(j, d, e) end,
      on_stderr = function(j, d, e) self:on_stderr(j, d, e) end,
      on_exit = function() self:on_exit() end,
    })
    self.job = (channel_id and channel_id > 0) and channel_id or nil
  end)

  vim.api.nvim_set_option_value('filetype', self.filetype, { buf = self.buf })
  vim.api.nvim_set_option_value('bufhidden', 'hide', { buf = self.buf })

  pcall(function() vim.b[self.buf].bufferline_deny = true end)
  vim.b[self.buf].pio_term_type = self.term_type

  self:_register_viewport_mappings()
  self:_register_viewport_bindings()
end

function Terminal:send(command)
  local cmd_str = tostring(command or '')
  local original_work_win = vim.api.nvim_get_current_win()

  if not self.buf or not vim.api.nvim_buf_is_valid(self.buf) then self:on_create() end

  if not M.layout.container_win or not vim.api.nvim_win_is_valid(M.layout.container_win) or M.layout.active_type ~= self.term_type then
    M.show(self.term_type)
  end

  if not self.job or self.job <= 0 then return end
  if cmd_str ~= '' and not cmd_str:match('^%s') then cmd_str = ' ' .. cmd_str end

  vim.fn.chansend(self.job, cmd_str .. self.newline)

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

  if original_work_win and vim.api.nvim_win_is_valid(original_work_win) then
    pcall(vim.api.nvim_set_current_win, original_work_win)
  end
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
  local cb = self._on_next_exit
  self._on_next_exit = nil
  if cb and type(cb) == 'function' then cb() end
  M.UpdateWinbarTitles()
end

--- Professional Layout Opening Handler (Dynamic Inspector Pattern)
---@return nil
function Terminal:on_open()
  local target_height = math.ceil(vim.o.lines * (M.config.panel_height or 0.2))
  vim.go.splitkeep = 'screen'

  if M.layout.container_win and vim.api.nvim_win_is_valid(M.layout.container_win) then
    vim.api.nvim_win_set_buf(M.layout.container_win, self.buf)
    M.layout.active_type = self.term_type
    self:_register_viewport_mappings()
    M.UpdateWinbarTitles()
    return
  end

  local code_win = nil
  if M.layout.code_win and vim.api.nvim_win_is_valid(M.layout.code_win) then
    local buf = vim.api.nvim_win_get_buf(M.layout.code_win)
    local ft = vim.api.nvim_get_option_value('filetype', { buf = buf })
    if ft ~= 'nvim-tree' and ft ~= 'neo-tree' then
      code_win = M.layout.code_win
    end
  end

  if not code_win then
    code_win = find_best_code_window()
  end

  -- Preserve layout proportions cleanly
  local old_ea = vim.o.equalalways
  vim.o.equalalways = false

  if not code_win or not vim.api.nvim_win_is_valid(code_win) then
    local tree_win = find_tree_window()
    local scratch_buf = vim.api.nvim_create_buf(true, false)
    vim.bo[scratch_buf].buflisted = true
    vim.bo[scratch_buf].buftype = ''
    vim.bo[scratch_buf].bufhidden = 'hide'
    vim.bo[scratch_buf].swapfile = false

    if tree_win and vim.api.nvim_win_is_valid(tree_win) then
      -- Dynamically query actual current width of tree instead of hardcoded numbers
      local current_tree_width = vim.api.nvim_win_get_width(tree_win)
      code_win = vim.api.nvim_open_win(scratch_buf, true, {
        split = 'right',
        win = tree_win,
      })
      pcall(vim.api.nvim_win_set_width, tree_win, current_tree_width)
    else
      code_win = vim.api.nvim_open_win(scratch_buf, true, {
        split = 'right',
      })
    end
  end

  M.layout.code_win = code_win

  local code_buf = vim.api.nvim_win_get_buf(code_win)
  if vim.api.nvim_buf_is_valid(code_buf) then
    vim.bo[code_buf].buflisted = true
    if vim.bo[code_buf].buftype ~= 'nofile' then
      vim.bo[code_buf].buftype = ''
    end
  end

  if vim.api.nvim_buf_get_name(code_buf) == '' and vim.api.nvim_buf_line_count(code_buf) <= 1 then
    vim.api.nvim_set_option_value('number', false, { scope = 'local', win = code_win })
    vim.api.nvim_set_option_value('relativenumber', false, { scope = 'local', win = code_win })
    vim.api.nvim_set_option_value('signcolumn', 'no', { scope = 'local', win = code_win })
  end

  vim.api.nvim_set_current_win(code_win)
  vim.cmd('belowright ' .. target_height .. 'split')
  M.layout.container_win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(M.layout.container_win, self.buf)
  M.layout.active_type = self.term_type

  vim.api.nvim_set_option_value('winfixheight', true, { scope = 'local', win = M.layout.container_win })
  vim.w[M.layout.container_win].pio_managed = true
  vim.w[M.layout.container_win].nvim_tree_no_window_picker = true
  vim.api.nvim_set_option_value('number', false, { scope = 'local', win = M.layout.container_win })
  vim.api.nvim_set_option_value('relativenumber', false, { scope = 'local', win = M.layout.container_win })
  vim.api.nvim_set_option_value('signcolumn', 'no', { scope = 'local', win = M.layout.container_win })

  vim.o.equalalways = old_ea
  self:_register_viewport_mappings()

  if code_win and vim.api.nvim_win_is_valid(code_win) then
    vim.api.nvim_set_current_win(code_win)
  end
end

function Terminal:_register_viewport_mappings()
  local maps = M.config.keymaps
  vim.keymap.set('t', maps.escape_term, [[<C-\><C-n>]], { buffer = self.buf, silent = true })
  vim.keymap.set('t', maps.switch_pane, function() M.SwitchTerminalPane() end, { buffer = self.buf, silent = true })
  vim.keymap.set('n', maps.switch_pane, function() M.SwitchTerminalPane() end, { buffer = self.buf, silent = true })
  vim.keymap.set('n', maps.hide_pane, function() M.toggle() end, { buffer = self.buf })
  vim.keymap.set('t', maps.move_up, [[<C-\><C-n><C-w>k]], { buffer = self.buf, silent = true })
  vim.keymap.set('n', maps.move_up, '<C-w>k', { buffer = self.buf, silent = true })
  vim.keymap.set('n', maps.move_left, '<C-w>h', { buffer = self.buf })
  vim.keymap.set('n', maps.move_right, '<C-w>l', { buffer = self.buf })
end

function Terminal:_register_viewport_bindings()
  local group_id = vim.api.nvim_create_augroup('PioLocalEvents_' .. self.buf, { clear = true })

  vim.api.nvim_create_autocmd({ 'BufWinEnter', 'BufEnter' }, {
    group = group_id,
    buffer = self.buf,
    callback = function()
      if M.layout.container_win and vim.api.nvim_win_is_valid(M.layout.container_win) then
        vim.api.nvim_set_option_value('number', false, { scope = 'local', win = M.layout.container_win })
        vim.api.nvim_set_option_value('relativenumber', false, { scope = 'local', win = M.layout.container_win })
        vim.api.nvim_set_option_value('signcolumn', 'no', { scope = 'local', win = M.layout.container_win })
      end
    end,
  })

  vim.api.nvim_create_autocmd('BufWipeout', {
    group = group_id,
    buffer = self.buf,
    callback = function()
      if self.job and self.job > 0 then pcall(vim.fn.jobstop, self.job) end
      self.job = nil
      self.buf = nil
      self._on_next_exit = nil
      if M.layout.active_type == self.term_type then
        M.layout.active_type = nil
        M.hide()
      end
    end,
  })

  vim.api.nvim_create_autocmd('WinLeave', {
    group = group_id,
    buffer = self.buf,
    callback = function()
      vim.schedule(function() M.UpdateWinbarTitles() end)
    end,
  })

  vim.api.nvim_create_autocmd('WinClosed', {
    group = group_id,
    callback = function(args)
      local closed_win = tonumber(args.match)
      if closed_win == M.layout.container_win then
        M.layout.container_win = nil
        M.layout.active_type = nil
      end
    end,
  })
end

function Terminal:on_close()
  local tracking_buf = self.buf
  self.job = nil
  self.buf = nil
  self._on_next_exit = nil
  M.layout.code_win = nil
  if tracking_buf and vim.api.nvim_buf_is_valid(tracking_buf) then
    pcall(vim.api.nvim_buf_delete, tracking_buf, { force = true })
  end
end

function Terminal:close()
  self:on_close()
  M.hide()
end

function Terminal:show()
  M.show(self.term_type)
end

function Terminal:hide()
  M.hide()
end

----------------------------------------------------------------------------------------
-- 4. ORCHESTRATION & FOCUS ROUTING SUBSYSTEM
----------------------------------------------------------------------------------------

local _is_routing_focus = false
vim.api.nvim_create_autocmd('WinEnter', {
  group = vim.api.nvim_create_augroup('PioTerminalFocusRouter', { clear = true }),
  callback = function()
    if _is_routing_focus then return end
    local win = vim.api.nvim_get_current_win()
    if not vim.api.nvim_win_is_valid(win) then return end

    local buf = vim.api.nvim_win_get_buf(win)
    local ft = vim.api.nvim_get_option_value('filetype', { buf = buf })
    local bufname = vim.api.nvim_buf_get_name(buf)

    if ft == 'nvim-tree' or ft == 'neo-tree' or bufname:match('NvimTree') or bufname:match('neo%-tree') then
      if M.layout.container_win and vim.api.nvim_win_is_valid(M.layout.container_win) then
        local code_win = M.layout.code_win
        if not code_win or not vim.api.nvim_win_is_valid(code_win) then
          code_win = find_best_code_window()
        end

        if code_win and vim.api.nvim_win_is_valid(code_win) and code_win ~= win then
          _is_routing_focus = true
          local tree_win = win
          pcall(function()
            vim.fn.win_gotoid(code_win)
            vim.fn.win_gotoid(tree_win)
          end)
          _is_routing_focus = false
        end
      end
    end
  end,
})

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

  if M.terminals[name] then
    M.terminals[name].title = title
    M.terminals[name].filetype = final_filetype
    M.terminals[name]._custom_stdout = final_cb
    if not M.terminals[name].buf or not vim.api.nvim_buf_is_valid(M.terminals[name].buf) then
      M.terminals[name]:on_create()
    end
    return M.terminals[name]
  end

  local current_count = 0
  for _ in pairs(M.terminals) do current_count = current_count + 1 end

  M.terminals[name] = Terminal.new(name, title, final_filetype, final_cb)
  M.terminals[name]._creation_index = current_count + 1
  M[name] = M.terminals[name]

  M.terminals[name]:on_create()
  return M.terminals[name]
end

function M.show(term_type)
  if not term_type then term_type = next(M.terminals) end
  local target_instance = M.terminals[term_type]
  if not target_instance then return end

  if not target_instance.buf or not vim.api.nvim_buf_is_valid(target_instance.buf) then
    target_instance:on_create()
  end

  if M.layout.container_win and vim.api.nvim_win_is_valid(M.layout.container_win) then
    vim.api.nvim_win_set_buf(M.layout.container_win, target_instance.buf)
    M.layout.active_type = term_type
    target_instance:_register_viewport_mappings()
    M.UpdateWinbarTitles()
    return
  end

  target_instance:on_open()
  M.UpdateWinbarTitles()
end

function M.hide()
  if M.layout.container_win and vim.api.nvim_win_is_valid(M.layout.container_win) then
    if vim.w[M.layout.container_win].pio_managed then
      pcall(vim.api.nvim_win_close, M.layout.container_win, true)
    end
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

function M.SwitchTerminalPane()
  local ordered_keys = {}
  for k, _ in pairs(M.terminals) do table.insert(ordered_keys, k) end

  table.sort(ordered_keys, function(a, b)
    return (M.terminals[a]._creation_index or 0) < (M.terminals[b]._creation_index or 0)
  end)

  if #ordered_keys <= 1 then return end

  local current_index = 1
  for i, k in ipairs(ordered_keys) do
    if k == M.layout.active_type then current_index = i; break end
  end

  local next_index = (current_index % #ordered_keys) + 1
  M.show(ordered_keys[next_index])
end

function M.IsTerminalOpen()
  return M.layout.container_win ~= nil and vim.api.nvim_win_is_valid(M.layout.container_win)
end

function M.send_and_restore(cmd)
  local target_instance = M.terminals.cli
  if not target_instance then return end

  local original_work_win = vim.api.nvim_get_current_win()
  target_instance._on_next_exit = function()
    vim.schedule(function()
      M.hide()
      if original_work_win and vim.api.nvim_win_is_valid(original_work_win) then
        pcall(vim.api.nvim_set_current_win, original_work_win)
      else
        M.RestoreWorkspaceFocus()
      end
    end)
  end

  if not target_instance.buf or not vim.api.nvim_buf_is_valid(target_instance.buf) then
    target_instance:on_create()
  end
  target_instance:send(cmd)
end

vim.keymap.set({ 'n', 'i', 'v' }, '<C-j>', function()
  if M.layout.container_win and vim.api.nvim_win_is_valid(M.layout.container_win) then
    vim.api.nvim_set_current_win(M.layout.container_win)
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
function M.reopen()
  if M.terminals['logs'] then M.terminals['logs']:close() end
  if M.terminals['mon'] then M.terminals['mon']:close() end
  if M.terminals['cli'] then M.terminals['cli']:close() end

  M.create_terminal('cli', ' CLI ', function(j, d, e)
    if type(M.stdout_callback) == 'function' then M.stdout_callback(j, d, e) end
  end)
  M.create_terminal('mon', ' Monitor ', nil)
  M.create_terminal('logs', ' OS ', nil)
end
M.reopen()

setmetatable(M, {
  __index = function(table, key)
    return rawget(table, 'terminals')[key]
  end,
})

return M
-- stylua: ignore end
