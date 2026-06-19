--- stylua: ignore start
local M = {}

-- 1. Anti-Crash Global Fallbacks
local safe_shell = (OS and OS.shell) and OS.shell or vim.o.shell
local safe_eol = (OS and OS.eol) and OS.eol or '\n'

-- 2. Purely Extensible Abstract Configuration Specification Matrix
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
    global_fallback_action = '<C-w>j',
  },
  ignored_focus_filetypes = {
    ['pio_terminal'] = true,
    ['pio_workspace'] = true,
    ['neo-tree'] = true,
    ['oil'] = true,
    ['aerial'] = true,
  },
  sentinel_fallback = {
    buffer_name = '[Workspace]',
    filetype = 'pio_workspace',
    buftype = 'nofile',
    bufhidden = 'wipe',
  },
}

M.stdout_callback = nil
M.exit_callback = nil
M.terminals = {}

-- Core Tiled Window Layout Node Matrix
M.layout = {
  container_win = nil,
  active_type = nil,
}

--- Pure C-API Highlight winbar renderer

--- Pure C-API Highlight winbar renderer (Dynamic Multi-Tab Layout Engine)
function M.UpdateWinbarTitles()
  local maps = M.config.keymaps

  -- Create a muted background highlight group for inactive tabs
  vim.api.nvim_set_hl(0, M.config.winbar_hl_group, { bg = M.config.winbar_bg, fg = M.config.winbar_fg, bold = true })
  vim.api.nvim_set_hl(0, M.config.winbar_hl_group .. 'Dim', { bg = M.config.winbar_bg, fg = '#4e5a6b', italic = true })

  if not M.layout.container_win or not vim.api.nvim_win_is_valid(M.layout.container_win) then
    return
  end

  -- 1. Dynamically build the tabbed terminal list string
  local tab_string = ' '
  local total_terminals = 0

  -- We want to iterate in a predictable order, so we gather sorted keys
  local ordered_keys = {}
  for k, _ in pairs(M.terminals) do
    table.insert(ordered_keys, k)
  end
  table.sort(ordered_keys)

  for _, name in ipairs(ordered_keys) do
    local term = M.terminals[name]
    if term.buf and vim.api.nvim_buf_is_valid(term.buf) then
      total_terminals = total_terminals + 1

      -- Check if this specific terminal is the one currently displayed
      if M.layout.active_type == name then
        -- Bright/Highlighted styling for the active terminal tab
        tab_string = tab_string .. string.format('%%#%s# [%s] %%*', M.config.winbar_hl_group, term.title:gsub('%s+', ''))
      else
        -- Muted/Dimmed styling for the background inactive terminal tabs
        tab_string = tab_string .. string.format('%%#%sDim#  %s  %%*', M.config.winbar_hl_group, term.title:gsub('%s+', ''))
      end
    end
  end

  -- 2. Construct navigation hint instructions depending on how many tabs exist
  local hint = (total_terminals > 1) and string.format(' [ %s Switch; %s Hide; :q! Quit ] ', maps.switch_pane, maps.hide_pane)
    or string.format(' [ %s Hide; :q! Quit ] ', maps.hide_pane)

  -- 3. Right-align the hint shortcuts using Vim's statusline column-break syntax (%=)
  local final_winbar = tab_string .. '%=' .. hint

  vim.api.nvim_set_option_value('winbar', final_winbar, { scope = 'local', win = M.layout.container_win })
end
-- function M.UpdateWinbarTitles()
--   local maps = M.config.keymaps
--   local alive_count = 0
--
--   for _, term in pairs(M.terminals) do
--     if term.buf and vim.api.nvim_buf_is_valid(term.buf) then
--       alive_count = alive_count + 1
--     end
--   end
--
--   local hint = (alive_count > 1) and string.format('[ %s Switch; %s Hide; :q! Quit ] ', maps.switch_pane, maps.hide_pane)
--     or string.format('[ %s Hide; :q! Quit ] ', maps.hide_pane)
--
--   vim.api.nvim_set_hl(0, M.config.winbar_hl_group, { bg = M.config.winbar_bg, fg = M.config.winbar_fg })
--
--   if M.layout.container_win and vim.api.nvim_win_is_valid(M.layout.container_win) then
--     local current_term = M.terminals[M.layout.active_type]
--     local title = current_term and current_term.title or ''
--     vim.api.nvim_set_option_value('winbar', '%#' .. M.config.winbar_hl_group .. '#' .. title .. hint .. '%*', { scope = 'local', win = M.layout.container_win })
--   end
-- end

--- Dynamic Workspace Tree Focus Router
function M.RestoreWorkspaceFocus()
  local target_win = nil
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.api.nvim_win_is_valid(win) then
      local buf = vim.api.nvim_win_get_buf(win)
      local ft = vim.api.nvim_get_option_value('filetype', { buf = buf })
      local win_type = vim.fn.win_gettype(win)

      if not M.config.ignored_focus_filetypes[ft] and win_type == '' then
        target_win = win
        break
      end
    end
  end

  if target_win then
    vim.api.nvim_set_current_win(target_win)
  end
end

local Terminal = {}
Terminal.__index = Terminal

function Terminal.new(term_type, panel_title, default_filetype)
  local self = setmetatable({}, Terminal)
  self.term_type = term_type
  self.title = panel_title
  self.buf = nil
  self.job = nil
  self.newline = safe_eol
  self.filetype = default_filetype or 'pio_terminal'
  return self
end

function Terminal:on_create()
  if self.buf and vim.api.nvim_buf_is_valid(self.buf) then
    pcall(vim.api.nvim_buf_delete, self.buf, { force = true })
  end

  self.buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_option_value('filetype', self.filetype, { buf = self.buf })

  local fallback_lines = math.ceil(vim.o.lines * (M.config.panel_height or 0.2))
  self:_register_lifecycle_events(fallback_lines)
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

function Terminal:send(command)
  local cmd_str = tostring(command or '')

  if not M.layout.container_win or not vim.api.nvim_win_is_valid(M.layout.container_win) or M.layout.active_type ~= self.term_type then
    M.ShowTerminal(self.term_type)
  end
  if not self.job or self.job <= 0 then
    return
  end

  vim.api.nvim_set_current_win(M.layout.container_win)
  self:enter_insert_mode()
  vim.fn.chansend(self.job, cmd_str .. self.newline)
end

function Terminal:on_stdout(j, d, e)
  if M.stdout_callback then
    M.stdout_callback(self.term_type, j, d, e)
  end
  vim.schedule(function()
    if M.layout.container_win and vim.api.nvim_win_is_valid(M.layout.container_win) then
      if vim.api.nvim_win_get_buf(M.layout.container_win) == self.buf then
        local lines = vim.api.nvim_buf_line_count(self.buf)
        pcall(vim.api.nvim_win_set_cursor, M.layout.container_win, { lines, 0 })
      end
    end
  end)
end

function Terminal:on_stderr(j, d, e)
  if M.stdout_callback then
    M.stdout_callback(self.term_type, j, d, e)
  end
end

function Terminal:on_exit()
  if M.exit_callback then
    M.exit_callback(self.term_type)
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
  M.HideTerminal()
end
function Terminal:hide()
  M.HideTerminal()
end

function Terminal:close()
  self:on_close()
  M.HideTerminal()
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

  if not self.job then
    self:on_spawn()
  end
  self:_register_viewport_mappings()
  M.UpdateWinbarTitles()
end

function Terminal:show()
  M.ShowTerminal(self.term_type)
  return true
end

function Terminal:enter_insert_mode()
  if M.layout.container_win and vim.api.nvim_win_is_valid(M.layout.container_win) then
    vim.api.nvim_set_current_win(M.layout.container_win)
    vim.cmd('startinsert')
  end
end

function Terminal:_register_viewport_mappings()
  local maps = M.config.keymaps
  vim.keymap.set('t', maps.escape_term, [[<C-\><C-n>]], { buffer = self.buf, silent = true })
  vim.keymap.set('n', maps.hide_pane, function()
    M.ToggleTerminal()
  end, { buffer = self.buf })
  vim.keymap.set('t', maps.move_up, [[<C-\><C-n><C-w>k]], { buffer = self.buf, silent = true })
  vim.keymap.set('n', maps.move_up, '<C-w>k', { buffer = self.buf, silent = true })
  vim.keymap.set('t', maps.switch_pane, function()
    M.SwitchTerminalPane()
  end, { buffer = self.buf, silent = true })
  vim.keymap.set('n', maps.switch_pane, function()
    M.SwitchTerminalPane()
  end, { buffer = self.buf, silent = true })
  vim.keymap.set('n', maps.move_left, '<C-w>h', { buffer = self.buf })
  vim.keymap.set('n', maps.move_right, '<C-w>l', { buffer = self.buf })
end

function Terminal:_register_lifecycle_events(target_height)
  local group_name = 'GenericTermEvents_' .. self.buf
  local group_id = vim.api.nvim_create_augroup(group_name, { clear = true })

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

  vim.api.nvim_create_autocmd({ 'WinNew', 'BufWinEnter', 'WinClosed' }, {
    group = group_id,
    callback = function()
      if M.layout.container_win and vim.api.nvim_win_is_valid(M.layout.container_win) then
        vim.schedule(function()
          if M.layout.container_win and vim.api.nvim_win_is_valid(M.layout.container_win) then
            local open_wins = vim.api.nvim_tabpage_list_wins(0)
            local valid_wins = 0

            for _, w in ipairs(open_wins) do
              if vim.api.nvim_win_is_valid(w) then
                local b = vim.api.nvim_win_get_buf(w)
                local ft = vim.api.nvim_get_option_value('filetype', { buf = b })
                if not M.config.ignored_focus_filetypes[ft] then
                  valid_wins = valid_wins + 1
                end
              end
            end

            if valid_wins <= 1 and vim.api.nvim_get_current_win() == M.layout.container_win then
              local fallback = M.config.sentinel_fallback
              local scratch_buf = vim.api.nvim_create_buf(false, true)

              vim.api.nvim_buf_set_name(scratch_buf, fallback.buffer_name)
              vim.api.nvim_set_option_value('buftype', fallback.buftype, { buf = scratch_buf })
              vim.api.nvim_set_option_value('filetype', fallback.filetype, { buf = scratch_buf })
              vim.api.nvim_set_option_value('bufhidden', fallback.bufhidden, { buf = scratch_buf })

              vim.cmd('noautocmd topleft split')
              vim.api.nvim_win_set_buf(vim.api.nvim_get_current_win(), scratch_buf)
              vim.cmd('noautocmd lua vim.api.nvim_set_current_win(' .. M.layout.container_win .. ')')
            end

            pcall(vim.api.nvim_win_set_height, M.layout.container_win, target_height)
            M.UpdateWinbarTitles()
          end
        end)
      end
    end,
  })
end

----------------------------------------------------------------------------------------
-- GLOBAL SINGLETON WORKSPACE MANAGER INTERFACE
----------------------------------------------------------------------------------------

function M.create_terminal(name, title, filetype)
  local final_filetype = filetype or ('terminal_' .. name)
  M.terminals[name] = Terminal.new(name, title, final_filetype)
  M.config.ignored_focus_filetypes[final_filetype] = true
  M.terminals[name]:on_create()
  return M.terminals[name]
end

function M.ShowTerminal(term_type)
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

  -- Inside your Part 3 M.ShowTerminal function:
  if M.layout.container_win and vim.api.nvim_win_is_valid(M.layout.container_win) then
    vim.api.nvim_win_set_buf(M.layout.container_win, target_instance.buf)
    M.layout.active_type = term_type
    target_instance:on_spawn()
    target_instance:_register_viewport_mappings()

    -- ALWAYS FORCE THE REDRAW RIGHT HERE!
    M.UpdateWinbarTitles()

    target_instance:enter_insert_mode()
    return
  end
  -- if M.layout.container_win and vim.api.nvim_win_is_valid(M.layout.container_win) then
  --   vim.api.nvim_win_set_buf(M.layout.container_win, target_instance.buf)
  --   M.layout.active_type = term_type
  --   target_instance:on_spawn()
  --   target_instance:_register_viewport_mappings()
  --   M.UpdateWinbarTitles()
  --   target_instance:enter_insert_mode()
  --   return
  -- end

  target_instance:on_open()
  target_instance:on_spawn()
  M.UpdateWinbarTitles()
  target_instance:enter_insert_mode()
end

function M.HideTerminal()
  if M.layout.container_win and vim.api.nvim_win_is_valid(M.layout.container_win) then
    vim.api.nvim_win_close(M.layout.container_win, true)
  end
  M.layout.container_win = nil
  M.layout.active_type = nil
  M.RestoreWorkspaceFocus()
end

function M.ToggleTerminal()
  if M.layout.container_win and vim.api.nvim_win_is_valid(M.layout.container_win) then
    M.HideTerminal()
  else
    M.ShowTerminal(M.layout.active_type)
  end
end

function M.SwitchTerminalPane()
  local keys = {}
  for k, _ in pairs(M.terminals) do
    table.insert(keys, k)
  end
  if #keys <= 1 then
    return
  end

  local current_index = 1
  for i, k in ipairs(keys) do
    if k == M.layout.active_type then
      current_index = i
      break
    end
  end

  local next_index = (current_index % #keys) + 1
  M.ShowTerminal(keys[next_index])
end

function M.IsTerminalOpen()
  return M.layout.container_win ~= nil and vim.api.nvim_win_is_valid(M.layout.container_win)
end

-- UNIVERSAL INTERACTIVE DIRECTIONAL DOWN NAVIGATOR MAP
vim.keymap.set({ 'n', 'i', 'v' }, M.config.keymaps.move_down, function()
  if M.layout.container_win and vim.api.nvim_win_is_valid(M.layout.container_win) then
    vim.api.nvim_set_current_win(M.layout.container_win)
    local active_instance = M.terminals[M.layout.active_type]
    if active_instance then
      active_instance:enter_insert_mode()
    end
  else
    local fallback = vim.api.nvim_replace_termcodes(M.config.keymaps.global_fallback_action, true, true, true)
    vim.api.nvim_feedkeys(fallback, 'n', false)
  end
end, { silent = true, desc = 'Universal Tiled Panel Down Navigation Router' })

function M.setup(opts)
  M.config = vim.tbl_deep_extend('force', M.config, opts or {})
end

----------------------------------------------------------------------------------------
-- AUTOMATED MODULE INSTANTIATION SEQUENCING
----------------------------------------------------------------------------------------

-- Pre-initialize the panels on module load so they exist instantly
M.create_terminal('cli', ' Run Build Command Panel ')
M.create_terminal('mon', ' Serial interface ')
M.create_terminal('logs', ' System Logs Tail ')

-- Enable shorthand lookups like: require('nvimpio.device.terminal').cli:send("pio run")
setmetatable(M, {
  __index = function(table, key)
    return rawget(table, 'terminals')[key]
  end,
})
return M
-- stylua: ignore end
