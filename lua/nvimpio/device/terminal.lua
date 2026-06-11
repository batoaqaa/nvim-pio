-- stylua: ignore start

local M = {}

-- Default Public User Configuration Matrix
M.config = {
  panel_height = 0.25,
  winbar_bg = '#80a3d4',
  winbar_fg = '#000000',
  shell = OS.shell,
  keymaps = {
    open_cli      = [[<leader>\t]],
    open_monitor  = [[<leader>\gm]],
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

  -- 🌟 UNIFIED LOOKUP LOOK: Winbar now reads directly from the shared class definition! [INDEX]
  vim.api.nvim_set_hl(0, 'PioWinBar', { bg = M.config.winbar_bg, fg = M.config.winbar_fg })

  for _, instance in pairs({ M.cli, M.monitor }) do
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
---@field job number|nil The asynchronous terminal channel ID backend process loop handle
---@field newline string Pre-cached cross-platform row end carriage return delimiter
---@field shell table The sequential array list configuration running the shell executable
---@field keymaps table The user configurable map table schema containing shortcuts [INDEX]
local Terminal = {
  term_type = "",
  title     = "",
  buf       = nil,
  win       = nil,
  job       = nil,
  newline   = OS.eol,
  shell     = {},
  keymaps   = {}, -- Both configuration states live fully encapsulated inside the prototype block [INDEX]!
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

--- Pipe manual strings down channels autonomously.
---@method
---@param command string|number The raw text instruction string payload to evaluate.
---@return nil
function Terminal:send(command)
  local cmd_str = tostring(command or "")

  if not self.job or self.job <= 0 or not self.win or not vim.api.nvim_win_is_valid(self.win) then
    self:show()
  end

  if not self.job or self.job <= 0 then return end
  vim.fn.chansend(self.job, cmd_str .. self.newline)
end

--- Gracefully stop background job and tear down split windows safely.
---@method
---@return nil
function Terminal:close()
  if not self.job or self.job <= 0 then return end
  pcall(vim.fn.jobstop, self.job)

  if self.win and vim.api.nvim_win_is_valid(self.win) then
    vim.api.nvim_win_close(self.win, true)
  end
  self.win = nil
  self.buf = nil
  self.job = nil

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

--- Pure Show Pass - Handles allocation and spawning natively.
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

  local is_new_buffer = false
  if not self.buf or not vim.api.nvim_buf_is_valid(self.buf) then
    self.buf = vim.api.nvim_create_buf(false, true)
    is_new_buffer = true
  end

  local target_height = math.ceil(vim.o.lines * (M.config.panel_height or 0.25))
  self.win = vim.api.nvim_open_win(self.buf, true, { split = "below", win = -1, height = target_height })

  if is_new_buffer then
    self:_spawn(target_height, opposite_instance)
  end

  vim.cmd("setlocal nonumber norelativenumber signcolumn=no")
  pcall(vim.api.nvim_set_option_value, "winfixheight", true, { scope = "local", win = self.win })
  M.UpdateWinbarTitles()

  -- vim.cmd("startinsert")
  return true
end

--- Internal process spawner mapping pipeline channels natively.
---@method
---@param target_height number Calculated pane height boundaries constraints row scale.
---@param opposite_instance Terminal The alternative lane object singleton reference.
---@return nil
function Terminal:_spawn(target_height, opposite_instance)
  local channel_id = vim.fn.termopen(self.shell, {
    on_stdout = function(j, d, e) if self.term_type == "cli" and type(M.stdout_callback) == "function" then M.stdout_callback(j, d, e) end end,
    on_stderr = function(j, d, e) if self.term_type == "cli" and type(M.stdout_callback) == "function" then M.stdout_callback(j, d, e) end end,
    on_exit = function() if type(M.exit_callback) == "function" then M.exit_callback() end end
  })

  if not channel_id or channel_id <= 0 then return end
  self.job = channel_id

  if OS.is_win then
    local clear_group = vim.api.nvim_create_augroup("PioClearGuard_" .. self.buf, { clear = true })
    vim.api.nvim_create_autocmd("TermRequest", {
      group = clear_group, buffer = self.buf, once = true,
      -- callback = function()
      --   vim.schedule(function()
      --     vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes([[<C-c><C-l>]], true, true, true), "t", false)
      --     vim.cmd("startinsert")
      --   end)
      -- end
    })
  end

  self:_attach_events(target_height)
  self:_attach_keymaps(target_height, opposite_instance)
end

-- Encapsulate automated layout focus autocmd listeners
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
      vim.schedule(function() if IsTerminalOpen(self) then
        pcall(vim.api.nvim_win_set_height, self.win, target_height)
        if vim.api.nvim_get_mode().mode:sub(1,1) ~= "t" then vim.cmd("normal! G") end
      end end)
    end,
  })
end

-- Encapsulate localized panel navigation keyboard bindings
function Terminal:_attach_keymaps(target_height, opposite_instance)
  -- 🌟 PROTOTYPE REFACTOR LOOP: Nav maps now read straight from self.keymaps! [INDEX]
  local maps = self.keymaps

  vim.keymap.set("t", maps.escape_term, [[<C-\><C-n>]], { buffer = self.buf })
  vim.keymap.set("n", maps.hide_pane, function() SafeCloseTerminal(self) end, { buffer = self.buf })

  vim.keymap.set({"n", "t"}, maps.move_up, function()
    if vim.api.nvim_get_mode().mode == "t" then vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes([[<C-\><C-n>]], true, true, true), "n", false) end
    vim.schedule(function() vim.cmd("wincmd k") end)
  end, { buffer = self.buf, silent = true })

  vim.keymap.set({"n", "t"}, maps.switch_pane, function()
    if vim.api.nvim_get_mode().mode == "t" then vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes([[<C-\><C-n>]], true, true, true), "n", false) end
    local current_winbar = vim.api.nvim_get_option_value("winbar", { scope = "local" }) or ""
    if current_winbar:find("%[; Hide%]") or current_winbar:find("%[" .. maps.hide_pane .. " Hide%]") then
      SafeCloseTerminal(self)
      return
    end
    SafeCloseTerminal(self)
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

-- Prime the prototype class template with initial baseline specifications layout [INDEX]
Terminal.shell = M.config.shell
Terminal.keymaps = M.config.keymaps

---@type Terminal
M.cli = Terminal.new("cli", " Pio CLI> ")
---@type Terminal
M.monitor = Terminal.new("monitor", " Pio Monitor ")

-- Global hotkey binder pass loop
local function BindGlobalTriggers()
  pcall(vim.keymap.del, "n", [[<leader>\gm]])
  pcall(vim.keymap.del, "n", [[<leader>\t]])
  vim.keymap.set("n", Terminal.keymaps.open_monitor, function() M.monitor:show() M.monitor:send("pio device monitor") end, { silent = true })
  vim.keymap.set("n", Terminal.keymaps.open_cli, function() M.cli:show() end, { silent = true })
end
BindGlobalTriggers()

function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", M.config, opts or {})

  -- 🌟 THE ULTIMATE UNIFIED PROTOTYPE ASSIGNMENT GATEWAY:
  -- We pass BOTH user parameters directly straight onto the parent prototype master class [INDEX]!
  -- Metatable inheritance fallback handles updating all shortcuts and shells identically and cleanly [INDEX]!
  if opts and opts.shell then Terminal.shell = opts.shell end
  if opts and opts.keymaps then Terminal.keymaps = M.config.keymaps end

  -- Re-register global hotkey shortcuts mapping arrays seamlessly [INDEX]
  BindGlobalTriggers()
end

return M
