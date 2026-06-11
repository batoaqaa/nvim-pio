-- stylua: ignore start
local M = {}

-- Default Public User Configuration Matrix
M.config = {
  panel_height = 0.25,
  winbar_bg = '#80a3d4',
  winbar_fg = '#000000',
  keymaps = {
    open_cli      = [[<leader>\t]],   -- Open primary CLI split panel
    open_monitor  = [[<leader>\gm]],  -- Open secondary hardware monitor
    hide_pane     = "q",              -- Hide panel split window
    switch_pane   = ";;",             -- Toggle back and forth between panel splits
    move_up       = "<C-k>",          -- Window focus jumps up
    move_down     = "<C-j>",          -- Window focus jumps down
    move_left     = "<C-h>",          -- Window focus jumps left
    move_right    = "<C-l>",          -- Window focus jumps right
  }
}

M.stdout_callback = nil
M.exit_callback = nil

--- Safe window manager close executor pass routine
---@param instance Terminal The specific object handle to clear down.
local function SafeCloseTerminal(instance)
  if not instance then return end
  if instance.win and vim.api.nvim_win_is_valid(instance.win) then
    vim.api.nvim_win_close(instance.win, true)
  end
  instance.win = nil
  vim.schedule(function()
    vim.cmd("wincmd =")
    M.UpdateWinbarTitles()
  end)
end

--- Visual redrawing loop engine applying winbar header tags
function M.UpdateWinbarTitles()
  local cli_alive = M.cli.buf and vim.api.nvim_buf_is_valid(M.cli.buf)
  local mon_alive = M.monitor.buf and vim.api.nvim_buf_is_valid(M.monitor.buf)
  local maps = M.config.keymaps
  local hint = (cli_alive and mon_alive) and " [" .. maps.switch_pane .. " Switch] " or " [" .. maps.hide_pane .. " Hide] "

  vim.api.nvim_set_hl(0, 'PioWinBar', { bg = M.config.winbar_bg, fg = M.config.winbar_fg })

  for _, instance in pairs({ M.cli, M.monitor }) do
    if instance and instance.win and vim.api.nvim_win_is_valid(instance.win) then
      vim.api.nvim_set_option_value('winbar', '%#PioWinBar#' .. instance.title .. hint .. '%*', { scope = 'local', win = instance.win })
    end
  end
end

----------------------------------------------------------------------------------------
-- 🌟 THE AUTONOMOUS TERMINAL CLASS ARCHITECTURE
----------------------------------------------------------------------------------------
---@class Terminal
---@field term_type string Unique lane configuration tracking tag ('cli' or 'monitor')
---@field title string The visual string printed on the window winbar header
---@field buf number|nil The native Neovim buffer ID handle for this panel split
---@field win number|nil The native Neovim window ID layout viewport handle
---@field job number|nil The active jobstart process channel tracking handle
---@field chan number|nil The native open_term headless channel pointer ID
local Terminal = {
  term_type = "",
  title     = "",
  buf       = nil,
  win       = nil,
  job       = nil,
  chan      = nil,
}
Terminal.__index = Terminal

--- Factory constructor for new terminal wrapper objects.
---@param term_type string The target channel lane allocation string.
---@param panel_title string The text string drawn onto the top winbar row.
---@return Terminal # A fully instantiated, self-contained terminal instance.
function Terminal.new(term_type, panel_title)
  local self = setmetatable({}, Terminal)
  self.term_type = term_type
  self.title = panel_title
  return self
end

--- Gracefully stop background job and tear down split windows safely.
---@method
---@return nil
function Terminal:close()
  if self.job and self.job > 0 then
    pcall(vim.fn.jobstop, self.job)
  end

  if self.win and vim.api.nvim_win_is_valid(self.win) then
    vim.api.nvim_win_close(self.win, true)
  end
  self.win = nil
  self.buf = nil
  self.job = nil
  self.chan = nil

  vim.schedule(function()
    vim.cmd("wincmd =")
    M.UpdateWinbarTitles()
  end)
end

--- Pure Hide Pass - Closes the split window layout viewport panel cleanly.
---@method
---@return nil
function Terminal:hide()
  if self.win and vim.api.nvim_win_is_valid(self.win) then
    vim.api.nvim_win_close(self.win, true)
  end
  self.win = nil
  vim.schedule(function()
    vim.cmd("wincmd =")
    M.UpdateWinbarTitles()
  end)
end

-- Status check querying layout visibility parameters
local function IsTerminalOpen(instance)
  if not instance then return false end
  return instance.win and vim.api.nvim_win_is_valid(instance.win) and vim.api.nvim_win_get_buf(instance.win) == instance.buf
end

function M.IsTerminalOpen(term_type)
  local instance = (term_type == "monitor") and M.monitor or M.cli
  return IsTerminalOpen(instance)
end

--- Pure Show Pass - Handles allocation and viewport generation natively.
---@method
---@return boolean # True if the split window canvas layout was drawn successfully.
function Terminal:show()
  local opposite_instance = (self.term_type == "monitor") and M.cli or M.monitor

  if opposite_instance.win and vim.api.nvim_win_is_valid(opposite_instance.win) then
    vim.api.nvim_win_close(opposite_instance.win, true)
    opposite_instance.win = nil
  end

  if self.win and vim.api.nvim_win_is_valid(self.win) then
    vim.api.nvim_set_current_win(self.win)
    return true
  end

  if not self.buf or not vim.api.nvim_buf_is_valid(self.buf) then
    self.buf = vim.api.nvim_create_buf(false, true)
    -- Allocate a modern raw terminal channel to draw incoming lines manually
    self.chan = vim.api.nvim_open_term(self.buf, {})
  end

  local target_height = math.ceil(vim.o.lines * (M.config.panel_height or 0.25))
  self.win = vim.api.nvim_open_win(self.buf, true, { split = "below", win = -1, height = target_height })

  vim.cmd("setlocal nonumber norelativenumber signcolumn=no")
  pcall(vim.api.nvim_set_option_value, "winfixheight", true, { scope = "local", win = self.win })
  M.UpdateWinbarTitles()

  self:_attach_events(target_height)
  self:_attach_keymaps(target_height, opposite_instance)
  return true
end

--- Spawn a discrete background system command and stream output lines.
---@method
---@param cmd_table table Pure linear array list of execution arguments (e.g., { "ls", "-la" })
---@return nil
function Terminal:run(cmd_table)
  -- Enforce view layer initialization before streaming text data
  self:show()

  -- Kill any stale background running task loops safely
  if self.job and self.job > 0 then
    pcall(vim.fn.jobstop, self.job)
  end

  -- Spawn the process via standard backend task streams cleanly
  local job_id = vim.fn.jobstart(cmd_table, {
    on_stdout = function(job_id, data, event)
      if data and self.chan then
        -- Forward clean lines visually to your open channel stream canvas
        for _, line in ipairs(data) do
          pcall(vim.api.nvim_chan_send, self.chan, line .. "\r\n")
        end
        -- Forward data logically straight to your Part 3 parser block
        if self.term_type == "cli" and type(M.stdout_callback) == "function" then
          M.stdout_callback(job_id, data, event)
        end
      end
    end,
    on_stderr = function(job_id, data, event)
      if data and self.chan then
        for _, line in ipairs(data) do
          pcall(vim.api.nvim_chan_send, self.chan, line .. "\r\n")
        end
        if self.term_type == "cli" and type(M.stdout_callback) == "function" then
          M.stdout_callback(job_id, data, event)
        end
      end
    end,
    on_exit = function() if type(M.exit_callback) == "function" then M.exit_callback() end end,
    stdout_buffered = false,
  })

  self.job = job_id
end

--- Encapsulate automated layout focus autocmd listeners.
---@method
---@param target_height number Calculated layout scaling limits constraints.
---@return nil
function Terminal:_attach_events(target_height)
  local scroll_group = vim.api.nvim_create_augroup("PioScroll_" .. self.buf, { clear = true })
  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
    group = scroll_group, buffer = self.buf,
    callback = function()
      local win_handle = vim.fn.bufwinid(self.buf)
      if win_handle and win_handle ~= -1 and vim.api.nvim_win_is_valid(win_handle) then
        vim.schedule(function() if vim.api.nvim_win_is_valid(win_handle) then vim.api.nvim_win_call(win_handle, function()
          vim.cmd("normal! G")
        end) end end)
      end
    end,
  })

  local guard_group = vim.api.nvim_create_augroup("PioGuard_" .. self.buf, { clear = true })
  vim.api.nvim_create_autocmd("WinEnter", {
    group = guard_group, buffer = self.buf,
    callback = function()
      vim.schedule(function() if IsTerminalOpen(self) then
        pcall(vim.api.nvim_win_set_height, self.win, target_height)
        vim.cmd("normal! G")
      end end)
    end,
  })
end

--- Encapsulate localized panel navigation keyboard bindings.
---@method
---@param target_height number The specific screen boundary height constraints.
---@param opposite_instance Terminal The mirror panel object target tracker.
---@return nil
function Terminal:_attach_keymaps(target_height, opposite_instance)
  local maps = M.config.keymaps

  vim.keymap.set("n", maps.hide_pane, function() SafeCloseTerminal(self) end, { buffer = self.buf })
  vim.keymap.set("n", maps.move_left, "<C-w>h", { buffer = self.buf })
  vim.keymap.set("n", maps.move_right, "<C-w>l", { buffer = self.buf })
  vim.keymap.set("n", maps.move_up, "<C-w>k", { buffer = self.buf })

  vim.keymap.set("n", maps.switch_pane, function()
    local current_winbar = vim.api.nvim_get_option_value("winbar", { scope = "local" }) or ""
    if current_winbar:find("%[; Hide%]") or current_winbar:find("%[" .. maps.hide_pane .. " Hide%]") then
      SafeCloseTerminal(self)
      return
    end
    SafeCloseTerminal(self)
    vim.schedule(function() opposite_instance:show() end)
  end, { buffer = self.buf, silent = true })

  vim.keymap.set("n", maps.move_down, function()
    vim.schedule(function() if IsTerminalOpen(self) then
      vim.api.nvim_set_current_win(self.win)
      pcall(vim.api.nvim_win_set_height, self.win, target_height)
      vim.cmd("normal! G")
    else vim.cmd("wincmd j") end end)
  end, { buffer = self.buf, silent = true })
end

---@type Terminal
M.cli = Terminal.new("cli", " Pio CLI> ")
---@type Terminal
M.monitor = Terminal.new("monitor", " Pio Monitor ")

local function SetGlobalKeymaps()
  pcall(vim.keymap.del, "n", [[<leader>\gm]])
  pcall(vim.keymap.del, "n", [[<leader>\t]])
  vim.keymap.set("n", M.config.keymaps.open_monitor, function() M.monitor:show() end, { silent = true })
  vim.keymap.set("n", M.config.keymaps.open_cli, function() M.cli:show() end, { silent = true })
end
SetGlobalKeymaps()

function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", M.config, opts or {})
  SetGlobalKeymaps()
end

return M
