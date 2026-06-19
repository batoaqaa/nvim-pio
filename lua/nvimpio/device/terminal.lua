--- stylua: ignore start
local M = {}

-- 1. Defend Against Global Environments Missing at Load Time
local safe_shell = (OS and OS.shell) and OS.shell or vim.o.shell
local safe_eol = (OS and OS.eol) and OS.eol or '\n'

-- 2. Configuration & Focus Exclusions Setup Matrix
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

M.terminals = {}

-- Core Layout Workspace Handle Matrix
M.layout = {
  container_win = nil,
  active_type = nil,
}

--- Pure C-API Highlight winbar renderer (Dynamic Multi-Tab Layout Engine)
function M.UpdateWinbarTitles()
  local maps = M.config.keymaps

  vim.api.nvim_set_hl(0, M.config.winbar_hl_group, { bg = M.config.winbar_bg, fg = M.config.winbar_fg, bold = true })
  vim.api.nvim_set_hl(0, M.config.winbar_hl_group .. 'Dim', { bg = M.config.winbar_bg, fg = '#4e5a6b', italic = true })

  if not M.layout.container_win or not vim.api.nvim_win_is_valid(M.layout.container_win) then
    return
  end

  local tab_string = ' '
  local total_terminals = 0
  local ordered_keys = {}
  for k, _ in pairs(M.terminals) do
    table.insert(ordered_keys, k)
  end
  table.sort(ordered_keys)

  for _, name in ipairs(ordered_keys) do
    local term = M.terminals[name]
    if term.buf and vim.api.nvim_buf_is_valid(term.buf) then
      total_terminals = total_terminals + 1
      if M.layout.active_type == name then
        tab_string = tab_string .. string.format('%%#%s# [%s] %%*', M.config.winbar_hl_group, term.title:gsub('%s+', ''))
      else
        tab_string = tab_string .. string.format('%%#%sDim#  %s  %%*', M.config.winbar_hl_group, term.title:gsub('%s+', ''))
      end
    end
  end

  local hint = (total_terminals > 1) and string.format(' [ %s Switch; %s Hide; :q! Quit ] ', maps.switch_pane, maps.hide_pane)
    or string.format(' [ %s Hide; :q! Quit ] ', maps.hide_pane)

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

      if not M.config.ignored_focus_filetypes[ft] and win_type == '' then
        target_win = win
        break
      end
    end
  end

  if target_win then
    pcall(vim.api.nvim_set_current_win, target_win)
  end
end

-- nvimpio/device/terminal.lua - Part 2
local Terminal = {}
Terminal.__index = Terminal

function Terminal.new(term_type, panel_title, default_filetype, custom_stdout)
  local self = setmetatable({}, Terminal)
  self.term_type = term_type
  self.title = panel_title
  self.buf = nil
  self.job = nil
  self.newline = safe_eol
  self.filetype = default_filetype or ('terminal_' .. term_type)
  self._custom_stdout = custom_stdout
  return self
end

function Terminal:on_create()
  if self.buf and vim.api.nvim_buf_is_valid(self.buf) then
    pcall(vim.api.nvim_buf_delete, self.buf, { force = true })
  end

  self.buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_option_value('filetype', self.filetype, { buf = self.buf })
  self:_register_viewport_bindings()
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

  pcall(vim.api.nvim_set_current_win, M.layout.container_win)
  self:enter_insert_mode()
  vim.fn.chansend(self.job, cmd_str .. self.newline)
end

function Terminal:on_stdout(j, d, e)
  if self._custom_stdout then
    self._custom_stdout(j, d, e)
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
  if self._custom_stdout then
    self._custom_stdout(j, d, e)
  end
end

function Terminal:on_exit()
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
    pcall(vim.api.nvim_set_current_win, M.layout.container_win)
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

-- nvimpio/device/terminal.lua - Part 3
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
end

--- Initializes the single, global, structural workspace layout tracker
function M._initialize_global_sentinel()
  -- Centralized group stops event multiplier accumulation completely
  local global_group = vim.api.nvim_create_augroup('PioGlobalWorkspaceSentinel', { clear = true })

  -- Monitor ONLY WinClosed to avoid recursive focus shifts
  vim.api.nvim_create_autocmd('WinClosed', {
    group = global_group,
    callback = function()
      -- Anti-freezing circuit: break execution if hidden, invalid, or already processing a recovery split
      if not M.layout.container_win or not vim.api.nvim_win_is_valid(M.layout.container_win) or M.layout.is_recovering then
        return
      end

      -- Identify the concrete window ID that Neovim is destroying right now
      local closed_win = tonumber(vim.fn.expand('<amatch>'))
      if closed_win == M.layout.container_win then
        -- If our layout container window itself was explicitly closed by the user, clear trackers and exit
        M.layout.container_win = nil
        M.layout.active_type = nil
        return
      end

      vim.schedule(function()
        -- Ensure layout integrity inside the asynchronous scheduler pipeline boundary
        if M.layout.container_win and vim.api.nvim_win_is_valid(M.layout.container_win) then
          local open_wins = vim.api.nvim_tabpage_list_wins(0)
          local valid_wins = 0

          for _, w in ipairs(open_wins) do
            -- Double check we are not using stale layout window handles that are currently closing
            if vim.api.nvim_win_is_valid(w) and w ~= M.layout.container_win and w ~= closed_win then
              local b = vim.api.nvim_win_get_buf(w)
              local ft = vim.api.nvim_get_option_value('filetype', { buf = b })
              if not M.config.ignored_focus_filetypes[ft] then
                valid_wins = valid_wins + 1
              end
            end
          end

          -- True Layout Collapse Discovered: 0 normal file editing slots are left
          if valid_wins == 0 then
            -- ENGAGE THREAD RECURSION LOCK: Blocks incoming window updates from loop freezing
            M.layout.is_recovering = true

            local fallback = M.config.sentinel_fallback
            local scratch_buf = nil

            for _, b in ipairs(vim.api.nvim_list_bufs()) do
              if vim.api.nvim_buf_is_valid(b) and vim.api.nvim_buf_get_name(b):match(fallback.buffer_name:gsub('%[', '%%['):gsub('%]', '%%]')) then
                scratch_buf = b
                break
              end
            end

            if not scratch_buf then
              scratch_buf = vim.api.nvim_create_buf(false, true)
              vim.api.nvim_buf_set_name(scratch_buf, fallback.buffer_name)
              vim.api.nvim_set_option_value('buftype', fallback.buftype, { buf = scratch_buf })
              vim.api.nvim_set_option_value('filetype', fallback.filetype, { buf = scratch_buf })
              vim.api.nvim_set_option_value('bufhidden', fallback.bufhidden, { buf = scratch_buf })
            end

            -- Shift pointer target down to terminal split line to execute clean horizontal cut away splits
            local old_current = vim.api.nvim_get_current_win()
            pcall(vim.api.nvim_set_current_win, M.layout.container_win)

            -- FIX: Changed 'topleft split' to 'aboveleft split' to prevent the terminal moving up the screen
            local split_success = pcall(function()
              vim.cmd('noautocmd aboveleft split')
            end)

            if split_success then
              local top_work_win = vim.api.nvim_get_current_win()
              vim.api.nvim_win_set_buf(top_work_win, scratch_buf)

              -- Clean out any winbar rules inherited on the fallback window split
              vim.api.nvim_set_option_value('winbar', '', { scope = 'local', win = top_work_win })

              vim.cmd('noautocmd wincmd J') -- Rigid enforcement layout lock: holds terminal baseline horizontally at bottom
              local target_height = math.ceil(vim.o.lines * (M.config.panel_height or 0.2))
              pcall(vim.api.nvim_win_set_height, M.layout.container_win, target_height)
              pcall(vim.api.nvim_set_current_win, top_work_win)
            else
              pcall(vim.api.nvim_set_current_win, old_current)
            end

            -- RELEASE THREAD RECURSION LOCK: Safe to evaluate structural context updates again
            M.layout.is_recovering = false
          end
          M.UpdateWinbarTitles()
        end
      end)
    end,
  })
end

-- --- Initializes the single, global, structural workspace layout tracker
-- function M._initialize_global_sentinel()
--   -- Using a fixed module-level group completely stops autocmd multipliers
--   local global_group = vim.api.nvim_create_augroup('PioGlobalWorkspaceSentinel', { clear = true })
--
--   vim.api.nvim_create_autocmd({ 'WinClosed', 'WinLeave' }, {
--     group = global_group,
--     callback = function()
--       if not M.layout.container_win or not vim.api.nvim_win_is_valid(M.layout.container_win) then
--         return
--       end
--
--       vim.schedule(function()
--         if M.layout.container_win and vim.api.nvim_win_is_valid(M.layout.container_win) then
--           local open_wins = vim.api.nvim_tabpage_list_wins(0)
--           local valid_wins = 0
--
--           for _, w in ipairs(open_wins) do
--             if vim.api.nvim_win_is_valid(w) then
--               local b = vim.api.nvim_win_get_buf(w)
--               local ft = vim.api.nvim_get_option_value('filetype', { buf = b })
--               if not M.config.ignored_focus_filetypes[ft] then
--                 valid_wins = valid_wins + 1
--               end
--             end
--           end
--
--           -- If closing a split leaves ONLY our layout panels, reconstruct work space safely
--           if valid_wins == 0 then
--             local fallback = M.config.sentinel_fallback
--             local scratch_buf = nil
--
--             for _, b in ipairs(vim.api.nvim_list_bufs()) do
--               if vim.api.nvim_buf_is_valid(b) and vim.api.nvim_buf_get_name(b):match(fallback.buffer_name:gsub('%[', '%%['):gsub('%]', '%%]')) then
--                 scratch_buf = b
--                 break
--               end
--             end
--
--             if not scratch_buf then
--               scratch_buf = vim.api.nvim_create_buf(false, true)
--               vim.api.nvim_buf_set_name(scratch_buf, fallback.buffer_name)
--               vim.api.nvim_set_option_value('buftype', fallback.buftype, { buf = scratch_buf })
--               vim.api.nvim_set_option_value('filetype', fallback.filetype, { buf = scratch_buf })
--               vim.api.nvim_set_option_value('bufhidden', fallback.bufhidden, { buf = scratch_buf })
--             end
--
--             local old_current = vim.api.nvim_get_current_win()
--             pcall(vim.api.nvim_set_current_win, M.layout.container_win)
--
--             local split_success = pcall(function()
--               vim.cmd('noautocmd topleft split')
--             end)
--
--             if split_success then
--               local top_work_win = vim.api.nvim_get_current_win()
--               vim.api.nvim_win_set_buf(top_work_win, scratch_buf)
--
--               vim.cmd('noautocmd wincmd J') -- Firmly anchor terminal window frame at absolute bottom baseline
--               local target_height = math.ceil(vim.o.lines * (M.config.panel_height or 0.2))
--               pcall(vim.api.nvim_win_set_height, M.layout.container_win, target_height)
--               pcall(vim.api.nvim_set_current_win, top_work_win)
--             else
--               pcall(vim.api.nvim_set_current_win, old_current)
--             end
--           end
--           M.UpdateWinbarTitles()
--         end
--       end)
--     end,
--   })
-- end

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

  M.terminals[name] = Terminal.new(name, title, final_filetype, final_cb)
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

  if M.layout.container_win and vim.api.nvim_win_is_valid(M.layout.container_win) then
    local old_win = vim.api.nvim_get_current_win()
    pcall(vim.api.nvim_set_current_win, M.layout.container_win)
    vim.api.nvim_win_set_buf(M.layout.container_win, target_instance.buf)
    M.layout.active_type = term_type

    target_instance:on_spawn()
    M.UpdateWinbarTitles()

    if old_win == M.layout.container_win then
      target_instance:enter_insert_mode()
    else
      pcall(vim.api.nvim_set_current_win, old_win)
    end
    return
  end

  target_instance:on_open()
  M.UpdateWinbarTitles()
  target_instance:enter_insert_mode()
end

function M.HideTerminal()
  if M.layout.container_win and vim.api.nvim_win_is_valid(M.layout.container_win) then
    pcall(vim.api.nvim_win_close, M.layout.container_win, true)
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
  table.sort(keys)

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
    pcall(vim.api.nvim_set_current_win, M.layout.container_win)
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
-- HARD MODULE INVOCATION CODES
----------------------------------------------------------------------------------------
M.create_terminal('cli', ' Run Build Command Panel ', nil)
M.create_terminal('server', ' Development Server Output ', nil)
M.create_terminal('logs', ' System Logs Tail ', nil)

-- Establish single workspace layout monitor listener loop exactly once on loading stage
M._initialize_global_sentinel()

setmetatable(M, {
  __index = function(table, key)
    return rawget(table, 'terminals')[key]
  end,
})

return M
-- stylua: ignore end
