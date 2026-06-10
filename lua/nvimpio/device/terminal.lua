-- stylua: ignore start
local M = {}

-- 1. Default Public User Configuration Matrix
M.config = {
  panel_height = 0.2,
  winbar_bg = '#80a3d4',
  winbar_fg = '#000000',
  -- 🌟 ALL KEYMAP SHORTCUT VALUES EXTRACTED HERE FOR USER CONFIGURATION CONTROL
  keymaps = {
    open_cli      = [[<leader>\t]],   -- Normal mode shortcut to slide open primary panel
    open_monitor  = [[<leader>\gm]],  -- Normal mode shortcut to slide open hardware monitor
    hide_pane     = "q",              -- Normal mode shortcut inside panel buffer to hide split
    switch_pane   = "<Tab>",             -- Interactive modes shortcut to cross-toggle panels
    escape_term   = "<Esc>",          -- Terminal mode escape key sequence mapping
    move_up       = "<C-k>",          -- Cross split navigation moving cursor up
    move_down     = "<C-j>",          -- Cross split navigation moving cursor down
    move_left     = "<C-h>",          -- Cross split navigation moving cursor left
    move_right    = "<C-l>",          -- Cross split navigation moving cursor right
  }
}

M.stdout_callback = nil
M.exit_callback = nil

-- Central database tracking window states and details
local term_registry = {
  cli =     { buf = nil, win = nil, job = nil, title = " Pio CLI> " },
  monitor = { buf = nil, win = nil, job = nil, title = " Pio Monitor " },
}

-- Safe window manager close executor pass routine
local function SafeCloseTerminal(term_type)
  local state = term_registry[term_type]
  if not state then return end
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    vim.api.nvim_win_close(state.win, true)
  end
  state.win = nil
  vim.schedule(function()
    vim.cmd("wincmd =")
    M.UpdateWinbarTitles()
  end)
end

-- Visual redrawing loop engine applying winbar header tags
function M.UpdateWinbarTitles()
  local cli_alive = term_registry.cli.buf and vim.api.nvim_buf_is_valid(term_registry.cli.buf)
  local mon_alive = term_registry.monitor.buf and vim.api.nvim_buf_is_valid(term_registry.monitor.buf)
  local hint = (cli_alive and mon_alive) and " [" .. M.config.keymaps.switch_pane .. " Switch] " or " [" .. M.config.keymaps.hide_pane .. " Hide] "

  vim.api.nvim_set_hl(0, 'PioWinBar', { bg = M.config.winbar_bg, fg = M.config.winbar_fg })

  for _, term_type in pairs({"cli", "monitor"}) do
    local state = term_registry[term_type]
    if state and state.win and vim.api.nvim_win_is_valid(state.win) then
      vim.api.nvim_set_option_value('winbar', '%#PioWinBar#' .. state.title .. hint .. '%*', { scope = 'local', win = state.win })
    end
  end
end

----------------------------------------------------------------------------------------
-- 🌟 THE AUTONOMOUS TERMINAL CLASS ARCHITECTURE
----------------------------------------------------------------------------------------
---@class Terminal; @field term_type string; @field newline string; @field shell string|table
local Terminal = {
  term_type = "",
  newline   = OS.eol,
  shell     = OS.shell,
}
Terminal.__index = Terminal

-- Class object instance factory constructor
function Terminal.new(term_type)
  local self = setmetatable({}, Terminal)
  self.term_type = term_type
  return self
end

-- Pipe manual strings down channels autonomously
function Terminal:send(command)
  local state = term_registry[self.term_type]
  if not state then return end
  local cmd_str = tostring(command or "")

  if not state.job or state.job <= 0 or not state.win or not vim.api.nvim_win_is_valid(state.win) then
    self:show()
  end

  if not state.job or state.job <= 0 then return end
  if cmd_str ~= "" then
    vim.fn.chansend(state.job, self.newline)
  end
  vim.fn.chansend(state.job, cmd_str .. self.newline)
end

-- Hard stop background processes loops safely
function Terminal:close()
  local state = term_registry[self.term_type]
  if not state or not state.job or state.job <= 0 then return end
  pcall(vim.fn.jobstop, state.job)

  if state.win and vim.api.nvim_win_is_valid(state.win) then
    vim.api.nvim_win_close(state.win, true)
  end
  state.win = nil
  state.buf = nil
  state.job = nil

  vim.schedule(function()
    vim.cmd("wincmd =")
    M.UpdateWinbarTitles()
  end)
end

-- Conceal window views preserving active sessions
function Terminal:hide()
  local state = term_registry[self.term_type]
  if state and state.win and vim.api.nvim_win_is_valid(state.win) then
    vim.api.nvim_win_close(state.win, true)
  end
  if state then state.win = nil end
  vim.schedule(function()
    vim.cmd("wincmd =")
    M.UpdateWinbarTitles()
  end)
end

-- Status check querying layout visibility parameters
local function IsTerminalOpen(term_type)
  local state = term_registry[term_type]
  if not state then return false end
  return state.win and vim.api.nvim_win_is_valid(state.win) and vim.api.nvim_win_get_buf(state.win) == state.buf
end

function M.IsTerminalOpen(term_type) return IsTerminalOpen(term_type) end

-- High performance view manager layout switcher
function Terminal:show()
  local state = term_registry[self.term_type]
  if not state then return false end

  local opposite_type = (self.term_type == "monitor") and "cli" or "monitor"
  local opposite_state = term_registry[opposite_type]

  if opposite_state and opposite_state.win and vim.api.nvim_win_is_valid(opposite_state.win) then
    vim.api.nvim_win_close(opposite_state.win, true)
    opposite_state.win = nil
  end

  if state.win and vim.api.nvim_win_is_valid(state.win) then
    vim.api.nvim_set_current_win(state.win)
    return true
  end

  local is_new_buffer = false
  if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then
    state.buf = vim.api.nvim_create_buf(false, true)
    is_new_buffer = true
  end

  local target_height = math.ceil(vim.o.lines * (M.config.panel_height or 0.25))
  state.win = vim.api.nvim_open_win(state.buf, true, { split = "below", win = -1, height = target_height })

  if is_new_buffer then
    self:_spawn(state, target_height, opposite_type)
  end

  vim.cmd("setlocal nonumber norelativenumber signcolumn=no")
  pcall(vim.api.nvim_set_option_value, "winfixheight", true, { scope = "local", win = state.win })
  M.UpdateWinbarTitles()

  -- if not is_new_buffer then
  --   vim.cmd("startinsert")
  -- end
  return true
end

-- Core process spawner mapping pipeline channels
function Terminal:_spawn(state, target_height, opposite_type)
  local channel_id = vim.fn.jobstart(self.shell, {
    term = true,
    on_stdout = function(j, d, e) if self.term_type == "cli" and type(M.stdout_callback) == "function" then M.stdout_callback(j, d, e) end end,
    on_stderr = function(j, d, e) if self.term_type == "cli" and type(M.stdout_callback) == "function" then M.stdout_callback(j, d, e) end end,
    on_exit = function() if type(M.exit_callback) == "function" then M.exit_callback() end end
  })

  if not channel_id or channel_id <= 0 then return end
  vim.b[state.buf].terminal_job_id = channel_id
  state.job = channel_id

  -- if OS.is_win then
  --   local init_enc = "[Console]::InputEncoding=[Console]::OutputEncoding=[System.Text.Encoding]::UTF8; Clear-Host;"
  --   vim.fn.chansend(channel_id, init_enc .. self.newline)
  -- end

  self:_attach_events(state, target_height)
  self:_attach_keymaps(state, target_height, opposite_type)
end

-- Encapsulate automated layout focus autocmd listeners
function Terminal:_attach_events(state, target_height)
  local scroll_group = vim.api.nvim_create_augroup("PioScroll_" .. state.buf, { clear = true })
  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
    group = scroll_group, buffer = state.buf,
    callback = function()
      local win_handle = vim.fn.bufwinid(state.buf)
      if win_handle and win_handle ~= -1 and vim.api.nvim_win_is_valid(win_handle) then
        vim.schedule(function() if vim.api.nvim_win_is_valid(win_handle) then vim.api.nvim_win_call(win_handle, function()
          if vim.api.nvim_get_mode().mode:sub(1,1) ~= "t" then vim.cmd("normal! G") end
        end) end end)
      end
    end,
  })

  local guard_group = vim.api.nvim_create_augroup("PioGuard_" .. state.buf, { clear = true })
  vim.api.nvim_create_autocmd("WinEnter", {
    group = guard_group, buffer = state.buf,
    callback = function()
      vim.schedule(function() if IsTerminalOpen(self.term_type) then
        pcall(vim.api.nvim_win_set_height, state.win, target_height)
        if vim.api.nvim_get_mode().mode:sub(1,1) ~= "t" then vim.cmd("normal! G") end
      end end)
    end,
  })
end

-- Encapsulate localized panel navigation keyboard bindings
function Terminal:_attach_keymaps(state, target_height, opposite_type)
  local maps = M.config.keymaps

  -- 🌟 USER-CONFIGURED DYNAMIC TERMINAL SHORTCUTS MAPS BINDINGS
  vim.keymap.set("t", maps.escape_term, [[<C-\><C-n>]], { buffer = state.buf })
  vim.keymap.set("n", maps.hide_pane, function() SafeCloseTerminal(self.term_type) end, { buffer = state.buf })

  vim.keymap.set({"n", "t"}, maps.move_up, function()
    if vim.api.nvim_get_mode().mode == "t" then vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes([[<C-\><C-n>]], true, true, true), "n", false) end
    vim.schedule(function() vim.cmd("wincmd k") end)
  end, { buffer = state.buf, silent = true })

  local active_type = self.term_type
  vim.keymap.set({"n", "t"}, maps.switch_pane, function()
    if vim.api.nvim_get_mode().mode == "t" then vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes([[<C-\><C-n>]], true, true, true), "n", false) end
    local current_winbar = vim.api.nvim_get_option_value("winbar", { scope = "local" }) or ""
    if current_winbar:find("%[; Hide%]") or current_winbar:find("%[" .. maps.hide_pane .. " Hide%]") then
      SafeCloseTerminal(active_type)
      return
    end
    SafeCloseTerminal(active_type)
    vim.schedule(function() M[opposite_type]:show() end)
  end, { buffer = state.buf, silent = true })

  vim.keymap.set("n", maps.move_left, "<C-w>h", { buffer = state.buf })
  vim.keymap.set("n", maps.move_right, "<C-w>l", { buffer = state.buf })
  vim.keymap.set("n", maps.move_down, function()
    vim.schedule(function() if IsTerminalOpen(self.term_type) then
      vim.api.nvim_set_current_win(state.win)
      pcall(vim.api.nvim_win_set_height, state.win, target_height)
      if vim.api.nvim_get_mode().mode:sub(1,1) ~= "t" then vim.cmd("normal! G") end
    else vim.cmd("wincmd j") end end)
  end, { buffer = state.buf, silent = true })
end

function Terminal:clear()
  local clear_cmd = OS.is_win and "Clear-Host" or "clear"
  self:send(clear_cmd)
end

function Terminal:get_buf() return term_registry[self.term_type] and term_registry[self.term_type].buf or nil end
function Terminal:get_win() return term_registry[self.term_type] and term_registry[self.term_type].win or nil end

---@type Terminal
M.cli = Terminal.new("cli")
---@type Terminal
M.monitor = Terminal.new("monitor")

-- 🌟 USER CONFIGURABLE GLOBAL TRIGGER SHORTCUT KEYMAPS
local function SetGlobalKeymaps()
  pcall(vim.keymap.del, "n", [[<leader>\gm]])
  pcall(vim.keymap.del, "n", [[<leader>\t]])
  vim.keymap.set("n", M.config.keymaps.open_monitor, function() M.monitor:show() M.monitor:send("pio device monitor") end, { silent = true })
  vim.keymap.set("n", M.config.keymaps.open_cli, function() M.cli:show() end, { silent = true })
end
SetGlobalKeymaps()

function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", M.config, opts or {})
  if opts and opts.shell then Terminal.shell = opts.shell end

  -- 🌟 LIVE UPDATE GATES: Refresh key registration trees instantly upon setup call!
  SetGlobalKeymaps()
end

return M
