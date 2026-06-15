
-- stylua: ignore start

local M = {}

-- Enterprise User Configuration Specification Matrix
M.config = {
  panel_height = 0.2,
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

----------------------------------------------------------------------------------------
-- 🌟 THE RIGID NATIVE TERMINAL CLASS ARCHITECTURE
----------------------------------------------------------------------------------------
---@class Terminal
---@field term_type string Unique structural channel lane tag ('cli' or 'monitor')
---@field title string Explicit text layout template drawn onto the local winbar row
---@field buf number|nil Immutable Neovim native buffer context memory address handle
---@field win number|nil Active viewport layout window node context index pointer
---@field last_win number|nil Explicitly maps the code file window context tracking node
---@field job number|nil Asynchronous background socket process loop channel ID stream
---@field newline string Normalized carriage return terminator sequence delimiters
---@field filetype string Strict isolated text-domain category namespace tag
local Terminal = {
  term_type = "",
  title     = "",
  buf       = nil,
  win       = nil,
  last_win  = nil,
  job       = nil,
  newline   = "\r\n",
  filetype  = "pio_terminal",
}
Terminal.__index = Terminal

--- Factory Class Constructor
function Terminal.new(term_type, panel_title)
  local self = setmetatable({}, Terminal)
  self.term_type = term_type
  self.title = panel_title
  return self
end

--- Hook: Allocates a clean, pristine memory block completely invisible to LSPs
---@method
function Terminal:on_create()
  self.buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_option_value("filetype", self.filetype, { buf = self.buf })

  local target_height = math.ceil(vim.o.lines * (M.config.panel_height or 0.2))
  self:_register_lifecycle_events(target_height)
end

--- Hook: Process backend stdout streams natively
---@method
function Terminal:on_stdout(j, d, e)
  if self.term_type == "cli" and type(M.stdout_callback) == "function" then
    M.stdout_callback(j, d, e)
  end
end

--- Hook: Process backend stderr streams natively
---@method
function Terminal:on_stderr(j, d, e)
  if self.term_type == "cli" and type(M.stdout_callback) == "function" then
    M.stdout_callback(j, d, e)
  end
end

--- Hook: Fires cleanly when a background task completes execution
---@method
function Terminal:on_exit()
  if type(M.exit_callback) == "function" then
    M.exit_callback()
  end
  M.UpdateWinbarTitles()
end

--- Hook: Core platform socket channel teardown
---@method
function Terminal:on_close()
  if self.job and self.job > 0 then
    pcall(vim.fn.jobstop, self.job)
  end
  self.job = nil
  self.buf = nil
end

--- Programmatic Insert-Mode Trigger wrapper using pure API entries
---@method
function Terminal:enter_insert_mode()
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("i", true, true, true), "n", false)
end

--- Synchronous Execution Pipeline Bridge
---@method
---@param command string|number Explicit string instruction payload delivered down the process.
function Terminal:send(command)
  local cmd_str = tostring(command or "")
  if not self.win or not vim.api.nvim_win_is_valid(self.win) then
    self:show()
  end
  if not self.job or self.job <= 0 then return end

  vim.api.nvim_set_current_win(self.win)
  self:enter_insert_mode()

  vim.fn.chansend(self.job, cmd_str .. self.newline)
end


--- Hook: Handles physical window layout allocations cleanly with zero leaks
---@method
function Terminal:on_open()
  local target_height = math.ceil(vim.o.lines * (M.config.panel_height or 0.2))
  local opposite_instance = (self.term_type == "monitor") and M.cli or M.mon
  
  -- Open the window via modern C-API globally at the root base.
  -- Setting split = "below" and win = -1 locks the window across the entire bottom floor.
  -- Neo-tree can now close and open freely; this window will refuse to move or distort.
  self.win = vim.api.nvim_open_win(self.buf, true, {
    split = "below",
    win = -1, -- Global tabpage anchor context (Bypasses column dependencies)
    height = target_height
  })

  -- Enforce clean, minimalist terminal window styling configurations
  vim.api.nvim_set_option_value("number", false, { scope = "local", win = self.win })
  vim.api.nvim_set_option_value("relativenumber", false, { scope = "local", win = self.win })
  vim.api.nvim_set_option_value("signcolumn", "no", { scope = "local", win = self.win })
  
  -- Hard lock the layout height programmatically to block any vertical shrinkage
  vim.api.nvim_set_option_value("winfixheight", true, { scope = "local", win = self.win })
  
  self:_register_viewport_mappings(opposite_instance)
end
--- Hook: Launches the active terminal process securely inside the open window context split
---@method
function Terminal:on_spawn()
  if self.job and self.job > 0 then return end

  local channel_id = vim.fn.termopen(M.config.shell, {
    on_stdout = function(j, d, e) self:on_stdout(j, d, e) end,
    on_stderr = function(j, d, e) self:on_stderr(j, d, e) end,
    on_exit   = function() self:on_exit() end
  })
  self.job = (channel_id and channel_id > 0) and channel_id or nil
end

--- Hook: Teardown split window viewports and select valid target focus redirection
---@method
function Terminal:on_quit()
  if self.win and vim.api.nvim_win_is_valid(self.win) then
    vim.api.nvim_win_close(self.win, true)
  end
  self.win = nil

  M.RestoreWorkspaceFocus()

  -- Balance rows atomically to match user layout height specifications
  vim.schedule(function()
    local cli = M.cli
    local mon = M.mon
    local target_height = math.ceil(vim.o.lines * (M.config.panel_height or 0.2))
    if cli and cli.win and vim.api.nvim_win_is_valid(cli.win) then
      pcall(vim.api.nvim_win_set_height, cli.win, target_height)
    end
    if mon and mon.win and vim.api.nvim_win_is_valid(mon.win) then
      pcall(vim.api.nvim_win_set_height, mon.win, target_height)
    end
    M.UpdateWinbarTitles()
  end)
end

function Terminal:close()
  self:on_close()
  self:on_quit()
end

function Terminal:hide()
  self:on_quit()
end

--- Main Entry Gateway Pass Coordinator - Lightweight OO Orchestrator
---@return boolean
function Terminal:show()
  local active_win = vim.api.nvim_get_current_win()
  if vim.api.nvim_win_is_valid(active_win) then
    local active_buf = vim.api.nvim_win_get_buf(active_win)
    local active_ft = vim.api.nvim_get_option_value("filetype", { buf = active_buf })
    local win_type = vim.fn.win_gettype(active_win)
    
    if active_ft ~= self.filetype and win_type == "" and active_ft ~= "neo-tree" and active_ft ~= "oil" and active_ft ~= "aerial" then
      self.last_win = active_win
    end
  end

  if not self.buf or not vim.api.nvim_buf_is_valid(self.buf) then
    self:on_create()
  end

  local opposite_instance = (self.term_type == "monitor") and M.cli or M.mon

  -- SILKY-SMOOTH WINDOW REUSE: Swaps terminal buffers natively without flashing splits
  if opposite_instance.win and vim.api.nvim_win_is_valid(opposite_instance.win) then
    self.win = opposite_instance.win
    opposite_instance.win = nil 
    
    vim.api.nvim_win_set_buf(self.win, self.buf)
    vim.api.nvim_set_current_win(self.win)

    if not self.job or self.job <= 0 then
      self:on_spawn()
    end

    vim.api.nvim_set_option_value("number", false, { scope = "local", win = self.win })
    vim.api.nvim_set_option_value("relativenumber", false, { scope = "local", win = self.win })
    vim.api.nvim_set_option_value("signcolumn", "no", { scope = "local", win = self.win })
    vim.api.nvim_set_option_value("winfixheight", true, { scope = "local", win = self.win })
    
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

function Terminal:_register_lifecycle_events(target_height)
  local platformio = vim.api.nvim_create_augroup("PioEvents_" .. self.buf, { clear = true })

  vim.api.nvim_create_autocmd('CmdlineLeave', {
    group = platformio, buffer = self.buf,
    callback = function()
      if vim.v.event and not vim.v.event.abort and vim.v.event.cmdtype == ':' then
        local cmd = vim.fn.getcmdline()
        if cmd == 'q' or cmd == 'q!' then
          if cmd == 'q!' then self:on_close() end
          vim.schedule(function() self:on_quit() end)
        end
      end
    end,
  })

  vim.api.nvim_create_autocmd('BufLeave', {
    group = platformio, buffer = self.buf,
    callback = function() vim.schedule(function() M.UpdateWinbarTitles() end) end,
  })

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

  vim.api.nvim_create_autocmd("WinEnter", {
    group = platformio, buffer = self.buf,
    callback = function()
      vim.schedule(function() 
        local current_win = vim.api.nvim_get_current_win()
        if current_win == self.win and self.win and vim.api.nvim_win_is_valid(self.win) then
          pcall(vim.api.nvim_win_set_height, self.win, target_height)
          local lines = vim.api.nvim_buf_line_count(self.buf)
          pcall(vim.api.nvim_win_set_cursor, self.win, { lines, 0 })
        end 
      end)
    end,
  })

  -- DEFENSIVE ANTI-COLLAPSE MONITOR LAYOUT TRACKER
  vim.api.nvim_create_autocmd({ "WinNew", "BufWinEnter", "WinClosed" }, {
    group = platformio,
    callback = function()
      if self.win and vim.api.nvim_win_is_valid(self.win) then
        vim.schedule(function()
          if self.win and vim.api.nvim_win_is_valid(self.win) then
            pcall(vim.api.nvim_win_set_height, self.win, target_height)
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

  vim.keymap.set("t", maps.move_up, function()
    local code_win = self.last_win or opposite_instance.last_win
    if code_win and vim.api.nvim_win_is_valid(code_win) then
      vim.api.nvim_set_current_win(code_win)
    else
      M.RestoreWorkspaceFocus()
    end
  end, { buffer = self.buf, silent = true })

  vim.keymap.set("n", maps.move_up, function()
    local code_win = self.last_win or opposite_instance.last_win
    if code_win and vim.api.nvim_win_is_valid(code_win) then
      vim.api.nvim_set_current_win(code_win)
    else
      M.RestoreWorkspaceFocus()
    end
  end, { buffer = self.buf, silent = true })

  vim.keymap.set("t", maps.switch_pane, function()
    local current_winbar = vim.api.nvim_get_option_value("winbar", { scope = "local" }) or ""
    if current_winbar:find("%[; Hide%]") or current_winbar:find("%[" .. maps.hide_pane .. " Hide%]") then
      self:on_quit()
      return
    end
    vim.schedule(function() opposite_instance:show() end)
  end, { buffer = self.buf, silent = true })

  vim.keymap.set("n", maps.switch_pane, function()
    vim.schedule(function() opposite_instance:show() end)
  end, { buffer = self.buf, silent = true })

  vim.api.nvim_buf_set_keymap(self.buf, "n", maps.move_left, "<C-w>h", { silent = true })
  vim.api.nvim_buf_set_keymap(self.buf, "n", maps.move_right, "<C-w>l", { silent = true })
  
  vim.keymap.set("n", maps.move_down, function()
    local open_check = self.win and vim.api.nvim_win_is_valid(self.win) and vim.api.nvim_win_get_buf(self.win) == self.buf
    if open_check then
      vim.api.nvim_set_current_win(self.win)
      self:enter_insert_mode()
    end 
  end, { buffer = self.buf, silent = true })
end

function M.UpdateWinbarTitles()
  local cli_alive = M.cli.buf and vim.api.nvim_buf_is_valid(M.cli.buf)
  local mon_alive = M.mon.buf and vim.api.nvim_buf_is_valid(M.mon.buf)
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

function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", M.config, opts or {})
end

return M
