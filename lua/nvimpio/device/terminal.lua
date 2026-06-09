-- stylua: ignore start
local M = {}

-- Core Inter-Module Event Callbacks
M.stdout_callback = nil
M.exit_callback = nil

-- Default Public User Configuration Matrix
M.config = {
  panel_height = 0.25,
  winbar_bg = '#80a3d4',
  winbar_fg = '#000000',
  shell = OS.is_win and {
    'pwsh.exe',
    '-NoExit',
    '-NoLogo',
    '-NoProfile',
    '-ExecutionPolicy', 'Bypass',
    '-Command', '[Console]::InputEncoding=[Console]::OutputEncoding=[System.Text.Encoding]::UTF8;'
  } or (function()
    local default_shell = vim.api.nvim_get_option_value('shell', {})
    -- If the Mac user defaults to zsh, pass the -f flag to bypass profile script leaks
    if default_shell:find("zsh") then
      return { default_shell, "-f" }
    end
    return default_shell
  end)(),
}

-- Isolated State Control Registry
local state = {
  cli =     { buf = nil, win = nil, title = " Pio CLI> " },
  monitor = { buf = nil, win = nil, title = " Pio Monitor " },
}

-- Absolute truth check to verify if a terminal panel split is actively drawn on screen
local function IsTerminalWindowOpen(term_type)
  local s = state[term_type]
  return s.win and vim.api.nvim_win_is_valid(s.win) and vim.api.nvim_win_get_buf(s.win) == s.buf
end

-- Telemetry Engine: Dynamic title generator based strictly on valid background buffers
local function UpdateWinbarTitles()
  local cli_alive = state.cli.buf and vim.api.nvim_buf_is_valid(state.cli.buf)
  local mon_alive = state.monitor.buf and vim.api.nvim_buf_is_valid(state.monitor.buf)
  local hint = (cli_alive and mon_alive) and " [;; Switch] " or " [; Hide] "

  vim.api.nvim_set_hl(0, 'PioWinBar', { bg = M.config.winbar_bg, fg = M.config.winbar_fg })

  for _, t in pairs({"cli", "monitor"}) do
    local s = state[t]
    if s.win and vim.api.nvim_win_is_valid(s.win) then
      vim.api.nvim_set_option_value('winbar', '%#PioWinBar#' .. s.title .. hint .. '%*', { scope = 'local', win = s.win })
    end
  end
end

local function SafeCloseTerminal(term_type)
  local s = state[term_type]
  if s.win and vim.api.nvim_win_is_valid(s.win) then
    vim.api.nvim_win_close(s.win, true)
  end
  s.win = nil
  vim.schedule(function()
    vim.cmd("wincmd =")
    UpdateWinbarTitles()
  end)
end

function M.IsTerminalOpen(term_type) return IsTerminalWindowOpen(term_type) end

function M.ToggleTerminal(command, terminal_type)
  local cmd_str = tostring(command or "")
  if terminal_type ~= "monitor" and terminal_type ~= "cli" then
    terminal_type = cmd_str:find("monitor") and "monitor" or "cli"
  end

  local opposite_type = (terminal_type == "monitor") and "cli" or "monitor"

  if IsTerminalWindowOpen(opposite_type) then
    SafeCloseTerminal(opposite_type)
    return M.ToggleTerminal(command, terminal_type)
  end

  -- Step 3: Always Open Target View Recycle Pass
  if IsTerminalWindowOpen(terminal_type) then
    vim.api.nvim_set_current_win(state[terminal_type].win)
    local target_h = math.ceil(vim.o.lines * M.config.panel_height)
    pcall(vim.api.nvim_win_set_height, state[terminal_type].win, target_h)

    local job_id = vim.b[state[terminal_type].buf].terminal_job_id
    if command and command ~= "" then
      if job_id then vim.fn.chansend(job_id, command .. (vim.fn.has("win32") == 1 and '\r\n' or '\n')) end
    end

    -- 🌟 CLI CONDITIONAL RETURN RULE: Returns channel handles exclusively for CLI loops!
    if terminal_type == "cli" then
      return job_id
    end
    return nil
  end

  -- Step 4: Clean Buffer Provision Pass
  local current = state[terminal_type]
  local is_new_buffer = false
  if not current.buf or not vim.api.nvim_buf_is_valid(current.buf) then
    current.buf = vim.api.nvim_create_buf(false, true)
    is_new_buffer = true
  end

  -- Step 5: Screen Split Window Layout Spawner
  local target_h = math.ceil(vim.o.lines * M.config.panel_height)
  local win_opts = { split = "below", win = -1, height = target_h }
  current.win = vim.api.nvim_open_win(current.buf, true, win_opts)

  if is_new_buffer then
    local spawned_job_id = vim.fn.jobstart(M.config.shell, {
      term = true,
      on_stdout = function(j, d, e)
        if terminal_type == "cli" and type(M.stdout_callback) == "function" then M.stdout_callback(j, d, e) end
      end,
      on_stderr = function(j, d, e)
        if terminal_type == "cli" and type(M.stdout_callback) == "function" then M.stdout_callback(j, d, e) end
      end,
      on_exit = function()
        if type(M.exit_callback) == "function" then M.exit_callback() end
      end
    })
    vim.b[current.buf].terminal_job_id = spawned_job_id

    local scroll_group = vim.api.nvim_create_augroup("PioAutoScroll_" .. current.buf, { clear = true })
    vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
      group = scroll_group, buffer = current.buf,
      callback = function()
        local w = vim.fn.bufwinid(current.buf)
        if w and w ~= -1 and vim.api.nvim_win_is_valid(w) then
          vim.schedule(function()
            if vim.api.nvim_win_is_valid(w) then
              vim.api.nvim_win_call(w, function()
                if vim.api.nvim_get_mode().mode:sub(1,1) ~= "t" then vim.cmd("normal! G") end
              end)
            end
          end)
        end
      end,
    })
  end

  vim.cmd("setlocal nonumber norelativenumber signcolumn=no")
  vim.api.nvim_set_option_value("winfixheight", true, { scope = "local", win = current.win })

  local pio_group = vim.api.nvim_create_augroup("PioFocusGuard_" .. current.buf, { clear = true })
  vim.api.nvim_create_autocmd("WinEnter", {
    group = pio_group, buffer = current.buf,
    callback = function()
      vim.schedule(function()
        if IsTerminalWindowOpen(terminal_type) then
          pcall(vim.api.nvim_win_set_height, current.win, target_h)
          if vim.api.nvim_get_mode().mode:sub(1,1) ~= "t" then vim.cmd("normal! G") end
        end
      end)
    end,
  })

  UpdateWinbarTitles()

  vim.keymap.set("t", "<Esc>", [[<C-\><C-n>]], { buffer = current.buf })
  vim.keymap.set("n", "q", function() SafeCloseTerminal(terminal_type) end, { buffer = current.buf })

  vim.keymap.set({"n", "t"}, "<C-k>", function()
    if vim.api.nvim_get_mode().mode == "t" then vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes([[<C-\><C-n>]], true, true, true), "n", false) end
    vim.schedule(function() vim.cmd("wincmd k") end)
  end, { buffer = current.buf, silent = true })

  vim.keymap.set({"n", "t"}, ";;", function()
    if vim.api.nvim_get_mode().mode == "t" then vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes([[<C-\><C-n>]], true, true, true), "n", false) end

    local current_winbar = vim.api.nvim_get_option_value("winbar", { scope = "local" }) or ""
    if current_winbar:find("%[; Hide%]") then
      SafeCloseTerminal(terminal_type)
      return
    end

    SafeCloseTerminal(terminal_type)
    vim.schedule(function() M.ToggleTerminal("", opposite_type) end)
  end, { buffer = current.buf, silent = true })

  vim.keymap.set("n", "<C-h>", "<C-w>h")
  vim.keymap.set("n", "<C-l>", "<C-w>l")
  vim.keymap.set("n", "<C-j>", function()
    vim.schedule(function()
      if IsTerminalWindowOpen(terminal_type) then
        vim.api.nvim_set_current_win(current.win)
        pcall(vim.api.nvim_win_set_height, current.win, target_h)
        if vim.api.nvim_get_mode().mode:sub(1,1) ~= "t" then vim.cmd("normal! G") end
      else vim.cmd("wincmd j") end
    end)
  end, { silent = true })

  local final_job_id = vim.b[current.buf].terminal_job_id
  if command and command ~= "" then
    if final_job_id then vim.fn.chansend(final_job_id, command .. (vim.fn.has("win32") == 1 and '\r\n' or '\n')) end
  end

  -- 🌟 CLI CONDITIONAL RETURN RULE: Returns channel handles exclusively for CLI loops!
  if terminal_type == "cli" then
    return final_job_id
  end
  return nil
end

vim.keymap.set("n", [[<leader>\gm]], function() M.ToggleTerminal("pio device monitor", "monitor") end, { silent = true })
vim.keymap.set("n", [[<leader>\t]], function() M.ToggleTerminal("", "cli") end, { silent = true })
-- function M.terminal(command, terminal_type)
--   local cmd_str = tostring(command or "")
--   if terminal_type ~= "monitor" and terminal_type ~= "cli" then
--     terminal_type = cmd_str:find("monitor") and "monitor" or "cli"
--   end
--
--   local opposite_type = (terminal_type == "monitor") and "cli" or "monitor"
--
--   if IsTerminalWindowOpen(opposite_type) then
--     SafeCloseTerminal(opposite_type)
--     vim.schedule(function() M.terminal(command, terminal_type) end)
--     return
--   end
--
--   -- Step 3: Always Open Target View Recycle Pass
--   if IsTerminalWindowOpen(terminal_type) then
--     vim.api.nvim_set_current_win(state[terminal_type].win)
--     local target_h = math.ceil(vim.o.lines * M.config.panel_height)
--     pcall(vim.api.nvim_win_set_height, state[terminal_type].win, target_h)
--
--     if command and command ~= "" then
--       local job_id = vim.b[state[terminal_type].buf].terminal_job_id
--       if job_id then vim.fn.chansend(job_id, command .. (vim.fn.has("win32") == 1 and '\r\n' or '\n')) end
--     end
--     return
--   end
--
--   -- Step 4: Clean Buffer Provision Pass
--   local current = state[terminal_type]
--   local is_new_buffer = false
--   if not current.buf or not vim.api.nvim_buf_is_valid(current.buf) then
--     current.buf = vim.api.nvim_create_buf(false, true)
--     is_new_buffer = true
--   end
--
--   -- Step 5: Screen Canvas Opening Pass
--   local target_h = math.ceil(vim.o.lines * M.config.panel_height)
--   local win_opts = { split = "below", win = -1, height = target_h }
--   current.win = vim.api.nvim_open_win(current.buf, true, win_opts)
--
--   if is_new_buffer then
--     local spawned_job_id = vim.fn.jobstart(M.config.shell, {
--       term = true,
--       on_stdout = function(j, d, e)
--         if terminal_type == "cli" and type(M.stdout_callback) == "function" then M.stdout_callback(j, d, e) end
--       end,
--       on_stderr = function(j, d, e)
--         if terminal_type == "cli" and type(M.stdout_callback) == "function" then M.stdout_callback(j, d, e) end
--       end,
--       on_exit = function() if type(M.exit_callback) == "function" then M.exit_callback() end end
--     })
--     vim.b[current.buf].terminal_job_id = spawned_job_id
--
--     local scroll_group = vim.api.nvim_create_augroup("PioAutoScroll_" .. current.buf, { clear = true })
--     vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
--       group = scroll_group, buffer = current.buf,
--       callback = function()
--         local w = vim.fn.bufwinid(current.buf)
--         if w and w ~= -1 and vim.api.nvim_win_is_valid(w) then
--           vim.schedule(function() if vim.api.nvim_win_is_valid(w) then vim.api.nvim_win_call(w, function()
--             if vim.api.nvim_get_mode().mode:sub(1,1) ~= "t" then vim.cmd("normal! G") end
--           end) end end)
--         end
--       end,
--     })
--   end
--
--   vim.cmd("setlocal nonumber norelativenumber signcolumn=no")
--   vim.api.nvim_set_option_value("winfixheight", true, { scope = "local", win = current.win })
--
--   local pio_group = vim.api.nvim_create_augroup("PioFocusGuard_" .. current.buf, { clear = true })
--   vim.api.nvim_create_autocmd("WinEnter", {
--     group = pio_group, buffer = current.buf,
--     callback = function()
--       vim.schedule(function()
--         if IsTerminalWindowOpen(terminal_type) then
--           pcall(vim.api.nvim_win_set_height, current.win, target_h)
--           if vim.api.nvim_get_mode().mode:sub(1,1) ~= "t" then vim.cmd("normal! G") end
--         end
--       end)
--     end,
--   })
--
--   UpdateWinbarTitles()
--
--   vim.keymap.set("t", "<Esc>", [[<C-\><C-n>]], { buffer = current.buf })
--   vim.keymap.set("n", "q", function() SafeCloseTerminal(terminal_type) end, { buffer = current.buf })
--
--   vim.keymap.set({"n", "t"}, "<C-k>", function()
--     if vim.api.nvim_get_mode().mode == "t" then vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes([[<C-\><C-n>]], true, true, true), "n", false) end
--     vim.schedule(function() vim.cmd("wincmd k") end)
--   end, { buffer = current.buf, silent = true })
--
--   vim.keymap.set({"n", "t"}, ";;", function()
--     if vim.api.nvim_get_mode().mode == "t" then vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes([[<C-\><C-n>]], true, true, true), "n", false) end
--     local current_winbar = vim.api.nvim_get_option_value("winbar", { scope = "local" }) or ""
--     if current_winbar:find("%[; Hide%]") then
--       SafeCloseTerminal(terminal_type)
--       return
--     end
--     SafeCloseTerminal(terminal_type)
--     vim.schedule(function() M.terminal("", opposite_type) end)
--   end, { buffer = current.buf, silent = true })
--
--   vim.keymap.set("n", "<C-h>", "<C-w>h")
--   vim.keymap.set("n", "<C-l>", '<C-w>l')
--   vim.keymap.set("n", "<C-j>", function()
--     vim.schedule(function()
--       if IsTerminalWindowOpen(terminal_type) then
--         vim.api.nvim_set_current_win(current.win)
--         pcall(vim.api.nvim_win_set_height, current.win, target_h)
--         if vim.api.nvim_get_mode().mode:sub(1,1) ~= "t" then vim.cmd("normal! G") end
--       else vim.cmd("wincmd j") end
--     end)
--   end, { silent = true })
--
--   -- 🌟 FIXED PIPELINE DELIVERY BRIDGE:
--   -- This executes at the very bottom of the function to capture initial generation commands
--   -- and send them down the raw active job channel instantly!
--   if command and command ~= "" then
--     local job_id = vim.b[current.buf].terminal_job_id
--     if job_id then
--       vim.fn.chansend(job_id, command .. (vim.fn.has("win32") == 1 and '\r\n' or '\n'))
--     end
--   end
-- end
--
-- -- Core User Shortcut Trigger Mappings: Make sure your macro string fields are explicitly passed!
-- vim.keymap.set('n', [[<leader>\gm]], function() M.terminal("pio device monitor", "monitor") end, { silent = true })
-- vim.keymap.set('n', [[<leader>\t]], function() M.terminal("", "cli") end, { silent = true })
-- function M.setup(opts)
--   M.config = vim.tbl_deep_extend("force", M.config, opts or {})
-- end

return M
