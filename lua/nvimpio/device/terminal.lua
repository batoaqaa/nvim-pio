-- stylua: ignore start
---@brief [[
--- nvimpio/device/terminal.lua - Production-Grade Asynchronous Terminal Manager

--[[
  require('nvimpio.device.terminal').setup({
    panel_height = 0.25,                  -- Set terminal split to 25% of screen height
    layout_style = 'below_code',         -- Options: 'below_code' (respects sidebar) or 'full_bottom'
    sidebar_default_width = 35,          -- Default sidebar width fallback
    winbar_hl_group = 'MyCustomTermBar', -- Custom highlight group name
  
    -- Optional custom sidebar predicate matcher (Zero hardcoding)
    is_sidebar = function(win, buf)
      local ft = vim.api.nvim_get_option_value('filetype', { buf = buf })
      return ft == 'custom_explorer_ft'
    end,
  
    keymaps = {
      hide_pane = 'q',
      switch_pane = '<Tab>',
      escape_term = '<Esc>',
      move_up = '<C-k>',
      move_down = '<C-j>',
      move_left = '<C-h>',
      move_right = '<C-l>',
    },
  })
]]
---@brief ]]

local M = {}

----------------------------------------------------------------------------------------
-- 1. CONFIGURATION & ENVIRONMENT SETUP
----------------------------------------------------------------------------------------
local OS = _G.OS or (pcall(require, 'nvimpio.osInfo') and _G.OS or {})
local native_shell = OS.shell or (vim.fn.has('win32') == 1 and 'pwsh' or 'sh')
local native_eol = OS.eol or '\n'

---@class TerminalKeymaps
---@field hide_pane string Action shortcut to hide the window panel split layout frame
---@field switch_pane string Action shortcut to rotate horizontally between active terminal tabs
---@field escape_term string Action shortcut to escape interactive terminal input mode
---@field move_up string Boundary navigation focus shortcut moving to window above
---@field move_down string Boundary navigation focus shortcut moving to window below
---@field move_left string Boundary navigation focus shortcut moving to window left
---@field move_right string Boundary navigation focus shortcut moving to window right

---@class TerminalConfig
---@field panel_height number Height ratio of terminal pane relative to editor lines (0.0 to 1.0)
---@field sidebar_default_width number Fallback width column size applied to sidebars/file trees
---@field layout_style string Width alignment: 'below_code' (respects sidebar) or 'full_bottom' (edge-to-edge)
---@field winbar_bg string|nil Hex background color string or nil for theme default (TabLineSel)
---@field winbar_fg string|nil Hex text foreground color string or nil
---@field winbar_hl_group string Highlight group namespace identifier registered in Neovim
---@field shell table|string Active system shell program override (e.g., 'pwsh', 'zsh', 'bash')
---@field is_sidebar? fun(win: integer, buf: integer): boolean Custom IoC predicate for sidebars/panels
---@field ignored_filetypes string[] List of Neovim filetypes ignored when resolving code windows
---@field ignored_patterns string[] Lua pattern filters used to filter out internal system buffers
---@field keymaps TerminalKeymaps Keymap registration mappings dictionary

---@type TerminalConfig
M.config = {
  panel_height = 0.2,
  sidebar_default_width = 30,
  layout_style = 'below_code', -- Options: 'below_code' (respects sidebar) or 'full_bottom' (edge-to-edge)
  winbar_bg = '#80a3d4',
  winbar_fg = '#000000',
  -- winbar_bg = nil,
  -- winbar_fg = nil,
  winbar_hl_group = 'PioWinBar',
  shell = native_shell,
  is_sidebar = nil, -- Optional custom predicate: function(win, buf) -> boolean
  ignored_filetypes = {
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
-- 2. DYNAMIC LAYOUT & WINDOW RESOLUTION ENGINE (Zero Hardcoding)
----------------------------------------------------------------------------------------

--- Dynamically evaluates whether a window is a sidebar or filetree using native Neovim heuristics
---@param win integer Window handle ID
---@return boolean
local function is_sidebar_window(win)
  if not vim.api.nvim_win_is_valid(win) then return true end

  local win_type = vim.fn.win_gettype(win)
  if win_type ~= '' then return true end

  local buf = vim.api.nvim_win_get_buf(win)

  if type(M.config.is_sidebar) == 'function' then
    if M.config.is_sidebar(win, buf) then
      return true
    end
  end

  local buftype = vim.api.nvim_get_option_value('buftype', { buf = buf })
  if buftype == 'nofile' or buftype == 'quickfix' or buftype == 'help' then
    return true
  end

  return false
end

--- Dynamically searches for an active sidebar/tree window in the current tabpage
---@return integer|nil
local function find_sidebar_window()
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if is_sidebar_window(win) then
      return win
    end
  end
  return nil
end

--- Dynamically resolves the best active code editing window
---@return integer|nil
local function find_best_code_window()
  local ignored_fts = M.config.ignored_filetypes or {}
  local ignored_patterns = M.config.ignored_patterns or {}

  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.api.nvim_win_is_valid(win) and win ~= M.layout.container_win then
      if not is_sidebar_window(win) then
        local buf = vim.api.nvim_win_get_buf(win)
        local ft = vim.api.nvim_get_option_value('filetype', { buf = buf })
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

--- Professional Winbar Renderer (Distinctly highlighted via TabLineSel)
---@return nil
function M.UpdateWinbarTitles()
  local maps = M.config.keymaps
  local hl = M.config.winbar_hl_group

  if M.config.winbar_bg then
    vim.api.nvim_set_hl(0, hl, { bg = M.config.winbar_bg, fg = M.config.winbar_fg or '#abb2bf', bold = true })
    vim.api.nvim_set_hl(0, hl .. 'Dim', { bg = M.config.winbar_bg, fg = '#5c6370', italic = true })
  else
    vim.api.nvim_set_hl(0, hl, { link = 'TabLineSel', bold = true })
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

--- Clean Configuration-Driven Layout Handler (Supports Layout Styles)
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
    if not is_sidebar_window(M.layout.code_win) then
      code_win = M.layout.code_win
    end
  end

  if not code_win then
    code_win = find_best_code_window()
  end

  local old_ea = vim.o.equalalways
  vim.o.equalalways = false

  if not code_win or not vim.api.nvim_win_is_valid(code_win) then
    local sidebar_win = find_sidebar_window()
    local scratch_buf = vim.api.nvim_create_buf(true, false)
    vim.bo[scratch_buf].buflisted = true
    vim.bo[scratch_buf].buftype = ''
    vim.bo[scratch_buf].bufhidden = 'hide'
    vim.bo[scratch_buf].swapfile = false

    if sidebar_win and vim.api.nvim_win_is_valid(sidebar_win) then
      local current_width = vim.api.nvim_win_get_width(sidebar_win)
      if current_width > (vim.o.columns * 0.4) then
        current_width = M.config.sidebar_default_width or 30
      end

      code_win = vim.api.nvim_open_win(scratch_buf, true, {
        split = 'right',
        win = sidebar_win,
      })
      pcall(vim.api.nvim_win_set_width, sidebar_win, current_width)
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

  local split_cmd = 'belowright '
  if M.config.layout_style == 'full_bottom' then
    split_cmd = 'botright '
  end

  vim.cmd(split_cmd .. target_height .. 'split')
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
-- 4. PUBLIC ORCHESTRATION LAYER (Zero Global Autocmd Bloat)
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
