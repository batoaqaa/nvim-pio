
-- stylua: ignore start

local M = {}

-- Enterprise User Configuration Specification Matrix
M.config = {
  panel_height = 0.2, -- Height percentage factor relative to global screen rows
  winbar_bg = '#80a3d4',
  winbar_fg = '#000000',
  shell = vim.o.shell,
  keymaps = {
    hide_pane     = "q",
    switch_pane   = "<Tab>",
    escape_term   = "<Esc>",
    move_up       = "<C-k>",
    move_down     = "<C-j>",
    move_left     = "<C-h>",
    move_right    = "<C-l>",
  }
}

M.stdout_callback = nil
M.exit_callback = nil

--- Winbar Redraw Layout Sync Engine Matrix
function M.UpdateWinbarTitles()
  local cli_alive = M.cli and M.cli.buf and vim.api.nvim_buf_is_valid(M.cli.buf)
  local mon_alive = M.mon and M.mon.buf and vim.api.nvim_buf_is_valid(M.mon.buf)
  local maps = M.config.keymaps

  local hint = (cli_alive and mon_alive)
    and string.format("[ %s  Switch;  %s  Hide; :q! Quit ] ", maps.switch_pane, maps.hide_pane)
    or string.format("[ %s  Hide; :q! Quit ] ", maps.hide_pane)

  vim.api.nvim_set_hl(0, 'PioWinBar', { bg = M.config.winbar_bg, fg = M.config.winbar_fg })

  for _, instance in pairs({ M.cli, M.mon }) do
    if instance and instance.win and vim.api.nvim_win_is_valid(instance.win) then
      vim.api.nvim_set_option_value('winbar', '%#PioWinBar#' .. instance.title .. hint .. '%*', { scope = 'local', win = instance.win })
    end
  end
end

--- Dynamic Workspace Tree Router
function M.RestoreWorkspaceFocus()
  local target_win = nil
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.api.nvim_win_is_valid(win) then
      local buf = vim.api.nvim_win_get_buf(win)
      local ft = vim.api.nvim_get_option_value("filetype", { buf = buf })
      local win_type = vim.fn.win_gettype(win)
      
      if ft ~= "pio_terminal" and win_type == "" and ft ~= "neo-tree" and ft ~= "oil" and ft ~= "aerial" then
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
---@field title string Explicit text layout template drawn onto the winbar row
---@field buf number|nil Immutable Neovim native buffer context memory address handle
---@field win number|nil Active viewport layout window node context index pointer
---@field job number|nil Asynchronous background socket process loop channel ID stream
---@field newline string Normalized carriage return terminator sequence delimiters
---@field filetype string Strict isolated text-domain category namespace tag
local Terminal = {
  term_type = "",
  title     = "",
  buf       = nil,
  win       = nil,
  job       = nil,
  newline   = "\r\n",
  filetype  = "pio_terminal",
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
  vim.api.nvim_set_option_value("filetype", self.filetype, { buf = self.buf })
  self:_register_lifecycle_events()
end

function Terminal:on_stdout(j, d, e)
  if self.term_type == "cli" and type(M.stdout_callback) == "function" then M.stdout_callback(j, d, e) end
end

function Terminal:on_stderr(j, d, e)
  if self.term_type == "cli" and type(M.stdout_callback) == "function" then M.stdout_callback(j, d, e) end
end

function Terminal:on_exit()
  M.UpdateWinbarTitles()
end

function Terminal:on_close()
  if self.job and self.job > 0 then pcall(vim.fn.jobstop, self.job) end
  self.job = nil
  self.buf = nil
end

function Terminal:enter_insert_mode()
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("i", true, true, true), "n", false)
end

function Terminal:send(command)
  local cmd_str = tostring(command or "")
  if not self.win or not vim.api.nvim_win_is_valid(self.win) then self:show() end
  if not self.job or self.job <= 0 then return end
  vim.api.nvim_set_current_win(self.win)
  self:enter_insert_mode()
  vim.fn.chansend(self.job, cmd_str .. self.newline)
end

--- 🌟 THE DEFENSIVE FLOATING PANEL ENGINE
--- Draws an uncollapsible, sidebar-immune global panel layout canvas context.
---@method
function Terminal:on_open()
  local opposite_instance = (self.term_type == "monitor") and M.cli or M.mon

  -- 1. Compute explicit geometric bounds matching the total screen resolution matrix
  local total_cols = vim.o.columns
  local total_lines = vim.o.lines
  local target_height = math.ceil(total_lines * (M.config.panel_height or 0.2))
  
  -- Account for statusline and command line spacing height dynamically
  local row_placement = total_lines - target_height - (vim.o.laststatus > 0 and 2 or 1) - vim.o.cmdheight

  -- 2. Allocate an explicit floating window context container at the absolute base boundary.
  -- Setting relative = "editor" decouples the terminal completely from your file column splits.
  self.win = vim.api.nvim_open_win(self.buf, true, {
    relative = "editor",
    row = row_placement,
    col = 0,
    width = total_cols,
    height = target_height,
    style = "minimal",
    border = "none"
  })

  -- Enforce styling overrides directly to the floating node context
  vim.api.nvim_set_option_value("number", false, { scope = "local", win = self.win })
  vim.api.nvim_set_option_value("relativenumber", false, { scope = "local", win = self.win })
  vim.api.nvim_set_option_value("signcolumn", "no", { scope = "local", win = self.win })

  self:_register_viewport_mappings(opposite_instance)
end

function Terminal:on_spawn()
  if self.job and self.job > 0 then return end
  local channel_id = vim.fn.termopen(M.config.shell, {
    on_stdout = function(j, d, e) self:on_stdout(j, d, e) end,
    on_stderr = function(j, d, e) self:on_stderr(j, d, e) end,
    on_exit   = function() self:on_exit() end
  })
  self.job = (channel_id and channel_id > 0) and channel_id or nil
end

function Terminal:on_quit()
  if self.win and vim.api.nvim_win_is_valid(self.win) then vim.api.nvim_win_close(self.win, true) end
  self.win = nil
  M.RestoreWorkspaceFocus()
  M.UpdateWinbarTitles()
end

function Terminal:close()
  self:on_close()
  self:on_quit()
end

function Terminal:hide()
  self:on_quit()
end

function Terminal:show()
  if not self.buf or not vim.api.nvim_buf_is_valid(self.buf) then self:on_create() end

  local opposite_instance = (self.term_type == "monitor") and M.cli or M.mon

  -- WINDOW REUSE TRANSITION LAYER
  if opposite_instance.win and vim.api.nvim_win_is_valid(opposite_instance.win) then
    self.win = opposite_instance.win
    opposite_instance.win = nil 
    
    vim.api.nvim_win_set_buf(self.win, self.buf)
    vim.api.nvim_set_current_win(self.win)

    if not self.job or self.job <= 0 then self:on_spawn() end

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

function Terminal:_register_lifecycle_events()
  local platformio = vim.api.nvim_create_augroup("PioEvents_" .. self.buf, { clear = true })

  vim.api.nvim_create_autocmd('BufLeave', {
    group = platformio, buffer = self.buf,
    callback = function() vim.schedule(function() M.UpdateWinbarTitles() end) end,
  })

  -- Robust Programmatic Scroll Tracker: Follows terminal prints down safely
  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
    group = platformio, buffer = self.buf,
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

  -- DYNAMIC RESOLUTION ADAPTER
  vim.api.nvim_create_autocmd({ "VimResized" }, {
    group = platformio,
    callback = function()
      if self.win and vim.api.nvim_win_is_valid(self.win) then
        vim.schedule(function()
          if self.win and vim.api.nvim_win_is_valid(self.win) then
            local total_cols = vim.o.columns
            local total_lines = vim.o.lines
            local target_height = math.ceil(total_lines * (M.config.panel_height or 0.2))
            local row_placement = total_lines - target_height - (vim.o.laststatus > 0 and 2 or 1) - vim.o.cmdheight
            
            pcall(vim.api.nvim_win_set_config, self.win, {
              relative = "editor",
              row = row_placement,
              col = 0,
              width = total_cols,
              height = target_height
            })
          end
        end)
      end
    end,
  })
end

function Terminal:_register_viewport_mappings(opposite_instance)
  local maps = M.config.keymaps

  vim.keymap.set("t", maps.escape_term, [[<C-\><C-n>]], { buffer = self.buf })
  vim.keymap.set("n", maps.hide_pane, function() self:on_quit() end, { buffer = self.buf })

  vim.keymap.set("t", maps.move_up, function() M.RestoreWorkspaceFocus() end, { buffer = self.buf, silent = true })
  vim.keymap.set("n", maps.move_up, function() M.RestoreWorkspaceFocus() end, { buffer = self.buf, silent = true })

  vim.keymap.set("t", maps.switch_pane, function() vim.schedule(function() opposite_instance:show() end) end, { buffer = self.buf, silent = true })
  vim.keymap.set("n", maps.switch_pane, function() vim.schedule(function() opposite_instance:show() end) end, { buffer = self.buf, silent = true })

  vim.api.nvim_buf_set_keymap(self.buf, "n", maps.move_left, "<C-w>h", { silent = true })
  vim.api.nvim_buf_set_keymap(self.buf, "n", maps.move_right, "<C-w>l", { silent = true })
end

local function IsTerminalOpen(instance)
  if not instance then return false end
  return instance.win and vim.api.nvim_win_is_valid(instance.win) and vim.api.nvim_win_get_buf(instance.win) == instance.buf
end

function M.IsTerminalOpen(term_type)
  local instance = (term_type == "monitor") and M.mon or M.cli
  return IsTerminalOpen(instance)
end

--- Singletons Instantiations
M.cli = Terminal.new("cli", " Pio CLI> ")
M.mon = Terminal.new("monitor", " Pio Monitor ")

-- 🌟 FIXED CORE ROUTING INFRASTRUCTURE:
-- Placed cleanly at raw execution level. It activates immediately on editor startup.
-- Using a scheduled setter wrapper completely clears layout focus lag.
vim.keymap.set({"n", "i", "v"}, M.config.keymaps.move_down, function()
  local cli = M.cli
  local mon = M.mon
  
  if cli and cli.win and vim.api.nvim_win_is_valid(cli.win) then
    vim.schedule(function()
      if cli.win and vim.api.nvim_win_is_valid(cli.win) then
        vim.api.nvim_set_current_win(cli.win)
        cli:enter_insert_mode()
      end
    end)
  elseif mon and mon.win and vim.api.nvim_win_is_valid(mon.win) then
    vim.schedule(function()
      if mon.win and vim.api.nvim_win_is_valid(mon.win) then
        vim.api.nvim_set_current_win(mon.win)
        mon:enter_insert_mode()
      end
    end)
  else
    -- Standard Tiling Split Viewport Navigation Fallback pass
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<C-w>j", true, true, true), "n", false)
  end
end, { silent = true, desc = "Universal Floating Terminal Down Navigation Router" })

function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", M.config, opts or {})
end

return M
