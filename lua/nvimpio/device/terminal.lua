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

-- The Layout Node Matrix: Encapsulates all layout states natively into a clean tracker block
M.layout = {
  container_win = nil, -- The single, immutable window split anchor at the bottom
  active_type = nil, -- Tracks which terminal instance is physically visible ('cli'|'monitor')
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

----------------------------------------------------------------------------------------
-- 🌟 THE RIGID OOP TERMINAL CLASS ARCHITECTURE
----------------------------------------------------------------------------------------
---@class Terminal
---@field term_type string Unique lane tag ('cli' or 'monitor')
---@field title string Custom layout title text
---@field buf number|nil Native Neovim buffer ID handle
---@field job number|nil Background process socket channel loop stream ID
---@field newline string Carriage return line delimiter sequence
---@field filetype string Isolated text-domain namespace tag
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
  vim.cmd('startinsert')
end

function Terminal:send(command)
  local cmd_str = tostring(command or '')
  if not M.layout.container_win or not vim.api.nvim_win_is_valid(M.layout.container_win) then
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

function Terminal:_register_lifecycle_events()
  local platformio = vim.api.nvim_create_augroup('PioEvents_' .. self.buf, { clear = true })

  -- Scroll Tracker: Automatically scrolls terminal view to the absolute bottom row context safely
  vim.api.nvim_create_autocmd({ 'TextChanged', 'TextChangedI' }, {
    group = platformio,
    buffer = self.buf,
    callback = function()
      if M.layout.container_win and vim.api.nvim_win_is_valid(M.layout.container_win) then
        local win_buf = vim.api.nvim_win_get_buf(M.layout.container_win)
        if win_buf == self.buf then
          local lines = vim.api.nvim_buf_line_count(self.buf)
          pcall(vim.api.nvim_win_set_cursor, M.layout.container_win, { lines, 0 })
        end
      end
    end,
  })
end


-- stylua: ignore start

--- 🌟 REFACTOR BACKWARD-COMPATIBILITY BRIDGE:
--- Maps the legacy 'show' method directly to the enterprise singleton window manager.
--- This completely eliminates the nil method crash inside your cli.lua file on line 89.
---@method
---@return boolean
function Terminal:show()
  M.ShowTerminal(self.term_type)
  return true
end

function Terminal:_register_viewport_mappings()
  local maps = M.config.keymaps

  vim.keymap.set("t", maps.escape_term, [[<C-\><C-n>]], { buffer = self.buf })
  vim.keymap.set("n", maps.hide_pane, function() M.ToggleTerminal() end, { buffer = self.buf })

  -- Native, rock-solid layout tree jumps that can never break or trap your focus
  vim.keymap.set("t", maps.move_up, [[<C-\><C-n><C-w>k]], { buffer = self.buf, silent = true })
  vim.keymap.set("n", maps.move_up, "<C-w>k", { buffer = self.buf, silent = true })

  vim.keymap.set("t", maps.switch_pane, function() M.SwitchTerminalPane() end, { buffer = self.buf, silent = true })
  vim.keymap.set("n", maps.switch_pane, function() M.SwitchTerminalPane() end, { buffer = self.buf, silent = true })

  vim.keymap.set("n", maps.move_left, "<C-w>h", { buffer = self.buf })
  vim.keymap.set("n", maps.move_right, "<C-w>l", { buffer = self.buf })
end

----------------------------------------------------------------------------------------
-- 🌟 THE GLOBAL SINGLETON WORKSPACE MANAGER (PROFESSIONAL STANDARD)
----------------------------------------------------------------------------------------

function M.ShowTerminal(term_type)
  term_type = term_type or "cli"
  local target_instance = (term_type == "monitor") and M.mon or M.cli

  if not target_instance.buf or not vim.api.nvim_buf_is_valid(target_instance.buf) then
    target_instance:on_create()
  end

  -- 1. If the single horizontal container window is open, simply switch buffers cleanly inside it!
  if M.layout.container_win and vim.api.nvim_win_is_valid(M.layout.container_win) then
    vim.api.nvim_win_set_buf(M.layout.container_win, target_instance.buf)
    M.layout.active_type = term_type
    target_instance:on_spawn()
    target_instance:_register_viewport_mappings()
    M.UpdateWinbarTitles()
    target_instance:enter_insert_mode()
    return
  end

  -- 2. Otherwise, draw ONE clean horizontal layout split at the very bottom row boundary.
  local target_height = math.ceil(vim.o.lines * (M.config.panel_height or 0.2))
  vim.cmd("silent! botright " .. target_height .. "split")
  
  M.layout.container_win = vim.api.nvim_get_current_win()
  M.layout.active_type = term_type

  -- Enforce styling directly to the single container window split node context
  vim.api.nvim_win_set_buf(M.layout.container_win, target_instance.buf)
  vim.api.nvim_set_option_value("number", false, { scope = "local", win = M.layout.container_win })
  vim.api.nvim_set_option_value("relativenumber", false, { scope = "local", win = M.layout.container_win })
  vim.api.nvim_set_option_value("signcolumn", "no", { scope = "local", win = M.layout.container_win })
  vim.api.nvim_set_option_value("winfixheight", true, { scope = "local", win = M.layout.container_win })

  target_instance:on_spawn()
  target_instance:_register_viewport_mappings()
  M.UpdateWinbarTitles()
  target_instance:enter_insert_mode()
end

function M.HideTerminal()
  if M.layout.container_win and vim.api.nvim_win_is_valid(M.layout.container_win) then
    vim.api.nvim_win_close(M.layout.container_win, true)
  end
  M.layout.container_win = nil
  M.layout.active_type = nil
end

function M.ToggleTerminal()
  if M.layout.container_win and vim.api.nvim_win_is_valid(M.layout.container_win) then
    M.HideTerminal()
  else
    M.ShowTerminal("cli")
  end
end

function M.SwitchTerminalPane()
  local next_type = (M.layout.active_type == "cli") and "monitor" or "cli"
  M.ShowTerminal(next_type)
end

function M.IsTerminalOpen()
  return M.layout.container_win ~= nil and vim.api.nvim_win_is_valid(M.layout.container_win)
end

--- Singletons Instantiations
M.cli = Terminal.new("cli", " Pio CLI> ")
M.mon = Terminal.new("monitor", " Pio Monitor ")

function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", M.config, opts or {})
end

return M
