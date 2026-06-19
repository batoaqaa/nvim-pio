--- stylua: ignore start

local M = {}

-- 1. Defend Against Global Environments Missing at Load Time
local safe_shell = (OS and OS.shell) and OS.shell or vim.o.shell
local safe_eol = (OS and OS.eol) and OS.eol or '\n'

-- 2. Enterprise User Configuration Specification Matrix
M.config = {
  panel_height = 0.2,
  winbar_bg = '#80a3d4',
  winbar_fg = '#000000',
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

-- The Core Tiled Window Layout Node Matrix
M.layout = {
  container_win = nil, -- THE SINGLE IMMUTABLE TILED GRID WINDOW HANDLE
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

  if M.layout.container_win and vim.api.nvim_win_is_valid(M.layout.container_win) then
    local title = (M.layout.active_type == 'monitor') and M.mon.title or M.cli.title
    vim.api.nvim_set_option_value('winbar', '%#PioWinBar#' .. title .. hint .. '%*', { scope = 'local', win = M.layout.container_win })
  end
end

--- Dynamic Workspace Tree Focus Router
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
  self:_register_lifecycle_events(math.ceil(vim.o.lines * (M.config.panel_height or 0.2)))
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

  self:_register_viewport_mappings()
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

-- nvimpio/device/terminal.lua - Part 3

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

  -- THE INDESTRUCTIBLE TABPAGE SENTINEL GUARD (With Look-Ahead Validation Shield)
  vim.api.nvim_create_autocmd({ 'WinNew', 'BufWinEnter', 'WinClosed' }, {
    group = platformio,
    callback = function()
      if M.layout.container_win and vim.api.nvim_win_is_valid(M.layout.container_win) then
        vim.schedule(function()
          if M.layout.container_win and vim.api.nvim_win_is_valid(M.layout.container_win) then
            -- LOOK-AHEAD PROTECTION: Scan loaded buffer list for active text documents
            local real_files_open = false
            for _, b in ipairs(vim.api.nvim_list_bufs()) do
              if vim.api.nvim_buf_is_valid(b) and vim.api.nvim_buf_is_loaded(b) then
                local bt = vim.api.nvim_get_option_value('buftype', { buf = b })
                local ft = vim.api.nvim_get_option_value('filetype', { buf = b })
                if bt == '' and ft ~= 'neo-tree' and ft ~= 'oil' and ft ~= 'aerial' and ft ~= 'pio_terminal' and ft ~= 'pio_workspace' then
                  real_files_open = true
                  break
                end
              end
            end

            -- Abort splitting adjustments completely if your code file is wide open behind the sidebar
            if real_files_open then
              pcall(vim.api.nvim_win_set_height, M.layout.container_win, target_height)
              M.UpdateWinbarTitles()
              return
            end

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

            if valid_wins <= 1 and vim.api.nvim_get_current_win() == M.layout.container_win then
              local scratch_buf = nil
              for _, b in ipairs(vim.api.nvim_list_bufs()) do
                if vim.api.nvim_buf_is_valid(b) and vim.api.nvim_buf_get_name(b):match('%[Workspace%]') then
                  scratch_buf = b
                  break
                end
              end

              if not scratch_buf then
                scratch_buf = vim.api.nvim_create_buf(false, true)
                vim.api.nvim_buf_set_name(scratch_buf, '[Workspace]')
                vim.api.nvim_set_option_value('buftype', 'nofile', { buf = scratch_buf })
                vim.api.nvim_set_option_value('filetype', 'pio_workspace', { buf = scratch_buf })
                vim.api.nvim_set_option_value('bufhidden', 'wipe', { buf = scratch_buf })
              end

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

function M.ShowTerminal(term_type)
  term_type = term_type or 'cli'
  local target_instance = (term_type == 'monitor') and M.mon or M.cli

  if not target_instance.buf or not vim.api.nvim_buf_is_valid(target_instance.buf) then
    target_instance:on_create()
  end

  if M.layout.container_win and vim.api.nvim_win_is_valid(M.layout.container_win) then
    vim.api.nvim_win_set_buf(M.layout.container_win, target_instance.buf)
    M.layout.active_type = term_type
    target_instance:on_spawn()

    target_instance:_register_viewport_mappings()
    M.UpdateWinbarTitles()
    target_instance:enter_insert_mode()
    return
  end

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
    M.ShowTerminal('cli')
  end
end

function M.SwitchTerminalPane()
  local next_type = (M.layout.active_type == 'cli') and 'monitor' or 'cli'
  M.ShowTerminal(next_type)
end

function M.IsTerminalOpen()
  return M.layout.container_win ~= nil and vim.api.nvim_win_is_valid(M.layout.container_win)
end

-- Singleton Instantiations
M.cli = Terminal.new('cli', ' Pio CLI> ')
M.mon = Terminal.new('monitor', ' Pio Monitor ')

-- UNIVERSAL INTERACTIVE DIRECTIONAL DOWN NAVIGATOR
vim.keymap.set({ 'n', 'i', 'v' }, '<C-j>', function()
  if M.layout.container_win and vim.api.nvim_win_is_valid(M.layout.container_win) then
    vim.api.nvim_set_current_win(M.layout.container_win)
    local active_instance = (M.layout.active_type == 'monitor') and M.mon or M.cli
    active_instance:enter_insert_mode()
  else
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<C-w>j', true, true, true), 'n', false)
  end
end, { silent = true, desc = 'Universal Tiled Panel Down Navigation Router' })

function M.setup(opts)
  M.config = vim.tbl_deep_extend('force', M.config, opts or {})
end

return M
-- stylua: ignore end
