-- stylua: ignore start

local M = {}

-- Default Public User Configuration Matrix
M.config = {
  panel_height = 0.2,
  winbar_bg = '#80a3d4',
  winbar_fg = '#000000',
  shell = OS.shell,
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

--- Safe window manager close executor pass routine
---@param instance Terminal The specific object handle to clear down.
local function SafeCloseTerminal(instance)
  if not instance then return end

  -- If our custom keymap is pressed, simply close the window viewport split.
  -- Our localized WinLeave autocommand handles the focus redirection automatically!
  if instance.win and vim.api.nvim_win_is_valid(instance.win) then
    vim.api.nvim_win_close(instance.win, true)
  end
end

--- Visual redrawing loop engine applying winbar header tags
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

----------------------------------------------------------------------------------------
-- 🌟 THE TRUE UNIFIED SELF-CONTAINED TERMINAL CLASS ARCHITECTURE
----------------------------------------------------------------------------------------
---@class Terminal
---@field term_type string Unique lane configuration tracking tag ('cli' or 'monitor')
---@field title string The visual string printed on the window winbar header
---@field buf number|nil The native Neovim buffer ID handle for this panel split
---@field win number|nil The native Neovim window ID layout viewport handle
---@field last_win number|nil The exact originating window ID handle prior to open routines
---@field job number|nil The asynchronous terminal channel ID backend process loop handle
---@field newline string Pre-cached cross-platform row end carriage return delimiter
---@field shell table The sequential array list configuration running the shell executable
---@field keymaps table The user configurable map table schema containing shortcuts
local Terminal = {
  term_type = "",
  title     = "",
  buf       = nil,
  win       = nil,
  last_win  = nil,
  job       = nil,
  newline   = OS.eol,
  filetype  = "pio_terminal",
  shell     = {},
  keymaps   = {},
}
Terminal.__index = Terminal

function Terminal.new(term_type, panel_title)
  local self = setmetatable({}, Terminal)
  self.term_type = term_type
  self.title = panel_title
  return self
end

function Terminal:send(command)
  local cmd_str = tostring(command or "")
  if not self.job or self.job <= 0 or not self.win or not vim.api.nvim_win_is_valid(self.win) then
    self:show()
  end
  if not self.job or self.job <= 0 then return end
  vim.fn.chansend(self.job, cmd_str .. self.newline)
end

function Terminal:close()
  if not self.job or self.job <= 0 then return end
  pcall(vim.fn.jobstop, self.job)

  if self.win and vim.api.nvim_win_is_valid(self.win) then
    vim.api.nvim_win_close(self.win, true)
  end
  self.win = nil
  self.buf = nil
  self.job = nil
end

function Terminal:hide()
  if self.win and vim.api.nvim_win_is_valid(self.win) then
    vim.api.nvim_win_close(self.win, true)
  end
  self.win = nil
end

local function IsTerminalOpen(instance)
  if not instance then return false end
  return instance.win and vim.api.nvim_win_is_valid(instance.win) and vim.api.nvim_win_get_buf(instance.win) == instance.buf
end

function M.IsTerminalOpen(term_type)
  local instance = (term_type == "monitor") and M.mon or M.cli
  return IsTerminalOpen(instance)
end

--- Pure Show Pass - Handles allocation, smooth reuse, and spawning natively.
---@method
---@return boolean # True if the split window canvas layout was drawn successfully.
function Terminal:show()
  local active_win = vim.api.nvim_get_current_win()
  if vim.api.nvim_win_is_valid(active_win) then
    local active_buf = vim.api.nvim_win_get_buf(active_win)
    local active_ft = vim.api.nvim_get_option_value("filetype", { buf = active_buf })
    local win_type = vim.fn.win_gettype(active_win)

    if active_ft ~= self.filetype and win_type == "" and active_ft ~= "neo-tree" then
      self.last_win = active_win
    end
  end

  local opposite_instance = (self.term_type == "monitor") and M.cli or M.mon

  -- 🌟 FLICKER-FREE REUSE LAYER: If sibling window is open, steal it and replace its buffer!
  if opposite_instance.win and vim.api.nvim_win_is_valid(opposite_instance.win) then
    self.win = opposite_instance.win
    self.last_win = opposite_instance.last_win or self.last_win
    opposite_instance.win = nil -- Detach sibling window pointer safely

    -- Switch the current window to our terminal buffer instantly with zero layout shifts
    vim.api.nvim_set_current_win(self.win)
  end

  -- Fast path return: If our viewport window is already alive and focused, stop here
  if self.win and vim.api.nvim_win_is_valid(self.win) then
    vim.api.nvim_set_current_win(self.win)
    return true
  end

  local is_new_buffer = false
  if not self.buf or not vim.api.nvim_buf_is_valid(self.buf) then
    self.buf = vim.api.nvim_create_buf(false, true)
    is_new_buffer = true
  end

  if self.buf and vim.api.nvim_buf_is_valid(self.buf) then
    vim.api.nvim_set_option_value("filetype", self.filetype, { buf = self.buf })
  end

  -- Fallback: Only create a brand new split if no windows exist yet
  local target_height = math.ceil(vim.o.lines * (M.config.panel_height or 0.25))
  self.win = vim.api.nvim_open_win(self.buf, true, { split = "below", win = -1, height = target_height })

  if is_new_buffer then
    self:_spawn(target_height, opposite_instance)
  else
    -- If buffer already exists but we're rendering it freshly, push it onto the window canvas
    vim.api.nvim_win_set_buf(self.win, self.buf)
  end

  vim.cmd("setlocal nonumber norelativenumber signcolumn=no")
  pcall(vim.api.nvim_set_option_value, "winfixheight", true, { scope = "local", win = self.win })
  M.UpdateWinbarTitles()

  vim.cmd("startinsert")
  return true
end
-- function Terminal:show()
--   -- Inspect active window tree structure dynamically prior to splitting
--   local active_win = vim.api.nvim_get_current_win()
--   if vim.api.nvim_win_is_valid(active_win) then
--     local active_buf = vim.api.nvim_win_get_buf(active_win)
--     local active_ft = vim.api.nvim_get_option_value("filetype", { buf = active_buf })
--     local win_type = vim.fn.win_gettype(active_win)
--
--     -- Cache target window ONLY if it is a standard file viewport (skips float popups & neo-tree sidebars)
--     if active_ft ~= self.filetype and win_type == "" and active_ft ~= "neo-tree" then
--       self.last_win = active_win
--     end
--   end
--
--   local opposite_instance = (self.term_type == "monitor") and M.cli or M.mon
--
--   -- Tear down sibling viewport if open to avoid visual layout pollution
--   if opposite_instance.win and vim.api.nvim_win_is_valid(opposite_instance.win) then
--     self.last_win = opposite_instance.last_win or self.last_win
--     vim.api.nvim_win_close(opposite_instance.win, true)
--     opposite_instance.win = nil
--   end
--
--   -- Fast path return: If this exact viewport window is already alive, jump focus directly
--   if self.win and vim.api.nvim_win_is_valid(self.win) then
--     vim.api.nvim_set_current_win(self.win)
--     return true
--   end
--
--   local is_new_buffer = false
--   if not self.buf or not vim.api.nvim_buf_is_valid(self.buf) then
--     self.buf = vim.api.nvim_create_buf(false, true)
--     is_new_buffer = true
--   end
--
--   -- Explicitly bind the custom filetype from your class architecture
--   if self.buf and vim.api.nvim_buf_is_valid(self.buf) then
--     vim.api.nvim_set_option_value("filetype", self.filetype, { buf = self.buf })
--   end
--
--   -- Native split creation directly under the currently active workspace layout focus window
--   local target_height = math.ceil(vim.o.lines * (M.config.panel_height or 0.25))
--   self.win = vim.api.nvim_open_win(self.buf, true, { split = "below", win = -1, height = target_height })
--
--   if is_new_buffer then
--     self:_spawn(target_height, opposite_instance)
--   end
--
--   vim.cmd("setlocal nonumber norelativenumber signcolumn=no")
--   pcall(vim.api.nvim_set_option_value, "winfixheight", true, { scope = "local", win = self.win })
--   M.UpdateWinbarTitles()
--
--   -- vim.cmd("startinsert")
--   return true
-- end


function Terminal:_spawn(target_height, opposite_instance)
  local channel_id = vim.fn.termopen(self.shell, {
    on_stdout = function(j, d, e) if self.term_type == "cli" and type(M.stdout_callback) == "function" then M.stdout_callback(j, d, e) end end,
    on_stderr = function(j, d, e) if self.term_type == "cli" and type(M.stdout_callback) == "function" then M.stdout_callback(j, d, e) end end,
    on_exit = function() if type(M.exit_callback) == "function" then M.exit_callback() end end
  })

  if not channel_id or channel_id <= 0 then return end
  self.job = channel_id

  -- 🌟 INTERCEPT :q AND :q! COMMANDS
  -- Redirects native manual exits back to your true code window split
  local quit_group = vim.api.nvim_create_augroup("PioQuit_" .. self.buf, { clear = true })
  vim.api.nvim_create_autocmd("BufWinLeave", {
    group = quit_group,
    buffer = self.buf,
    callback = function()
      vim.schedule(function()
        if self.last_win and vim.api.nvim_win_is_valid(self.last_win) then
          vim.api.nvim_set_current_win(self.last_win)
        end
        self.win = nil
        self.last_win = nil
      end)
    end,
  })

  if OS.is_win then
    local clear_group = vim.api.nvim_create_augroup("PioClearGuard_" .. self.buf, { clear = true })
    vim.api.nvim_create_autocmd("TermRequest", {
      group = clear_group, buffer = self.buf, once = true,
      callback = function()
        vim.schedule(function()
          vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes([[<C-c><C-l>]], true, true, true), "t", false)
        end)
      end
    })
  end

  self:_attach_events(target_height)
  self:_attach_keymaps(target_height, opposite_instance)
end

function Terminal:_attach_events(target_height)
  local scroll_group = vim.api.nvim_create_augroup("PioScroll_" .. self.buf, { clear = true })
  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
    group = scroll_group, buffer = self.buf,
    callback = function()
      local win_handle = vim.fn.bufwinid(self.buf)
      if win_handle and win_handle ~= -1 and vim.api.nvim_win_is_valid(win_handle) then
        vim.schedule(function() if vim.api.nvim_win_is_valid(win_handle) then vim.api.nvim_win_call(win_handle, function()
          if vim.api.nvim_get_mode().mode:sub(1,1) ~= "t" then vim.cmd("normal! G") end
        end) end end)
      end
    end,
  })

  local guard_group = vim.api.nvim_create_augroup("PioGuard_" .. self.buf, { clear = true })
  vim.api.nvim_create_autocmd("WinEnter", {
    group = guard_group, buffer = self.buf,
    callback = function()
      vim.schedule(function()
        local current_win = vim.api.nvim_get_current_win()
        if current_win == self.win and IsTerminalOpen(self) then
          pcall(vim.api.nvim_win_set_height, self.win, target_height)
          if vim.api.nvim_get_mode().mode:sub(1,1) ~= "t" then
            vim.cmd("normal! G")
            vim.cmd("startinsert")
          end
        end
      end)
    end,
  })
end

function Terminal:_attach_keymaps(target_height, opposite_instance)
  local maps = self.keymaps

  vim.keymap.set("t", maps.escape_term, [[<C-\><C-n>]], { buffer = self.buf })
  vim.keymap.set("n", maps.hide_pane, function() SafeCloseTerminal(self) end, { buffer = self.buf })

  vim.keymap.set({"n", "t"}, maps.move_up, function()
    if vim.api.nvim_get_mode().mode == "t" then vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes([[<C-\><C-n>]], true, true, true), "n", false) end
    vim.schedule(function() vim.cmd("wincmd k") end)
  end, { buffer = self.buf, silent = true })

  vim.keymap.set("n", maps.switch_pane, function()
    if vim.api.nvim_get_mode().mode == "t" then vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes([[<C-\><C-n>]], true, true, true), "n", false) end
    local current_winbar = vim.api.nvim_get_option_value("winbar", { scope = "local" }) or ""
    if current_winbar:find("%[; Hide%]") or current_winbar:find("%[" .. maps.hide_pane .. " Hide%]") then
      SafeCloseTerminal(self)
      return
    end

    opposite_instance.last_win = self.last_win

    if self.win and vim.api.nvim_win_is_valid(self.win) then
      vim.api.nvim_win_close(self.win, true)
    end
    self.win = nil

    vim.schedule(function() opposite_instance:show() end)
  end, { buffer = self.buf, silent = true })

  vim.keymap.set("n", maps.move_left, "<C-w>h", { buffer = self.buf })
  local target_buf = self.buf
  vim.keymap.set("n", maps.move_right, "<C-w>l", { buffer = target_buf })
  vim.keymap.set("n", maps.move_down, function()
    vim.schedule(function() if IsTerminalOpen(self) then
      vim.api.nvim_set_current_win(self.win)
      pcall(vim.api.nvim_win_set_height, self.win, target_height)
      if vim.api.nvim_get_mode().mode:sub(1,1) ~= "t" then vim.cmd("normal! G") end
    else vim.cmd("wincmd j") end end)
  end, { buffer = self.buf, silent = true })
end

Terminal.shell = M.config.shell
Terminal.keymaps = M.config.keymaps

---@type Terminal
M.cli = Terminal.new("cli", " Pio CLI> ")
---@type Terminal
M.mon = Terminal.new("monitor", " Pio Monitor ")

function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", M.config, opts or {})
  if opts and opts.shell then Terminal.shell = opts.shell end
  if opts and opts.keymaps then Terminal.keymaps = M.config.keymaps end
end

return M
