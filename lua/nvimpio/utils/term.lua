-- stylua: ignore start
local M = {}

-- -- =============================================================================
local current_token -- = tostring(math.random(10000, 99999))
local session_counter = 1 -- Our high-performance integer counter
local current_id = -1

local callBack = nil
M.queue = {}

local clangd_extracted_args = {}
local clangd_check_active = false

local fromMsg = ''
-- Assigned dynamically by external sub-modules like 'platformio.utils.pio'
M.stdout_callback = nil
M.exit_callback = nil

local pio_cli_buf = nil
local pio_mon_buf = nil

local pio_cli_win = nil
local pio_mon_win = nil

local target_panel_height = 0
local pio_buffer = ""
local content = ""

-- AUTOMATED TELEMETRY STATE ENGINE: Updates winbar hints based on visible splits presence
local function UpdateWinbarTitles()
  local cli_visible = pio_cli_win and vim.api.nvim_win_is_valid(pio_cli_win)
  local mon_visible = pio_mon_win and vim.api.nvim_win_is_valid(pio_mon_win)

  -- Displays [;; Switch] ONLY if both window splits are actively open on screen right now
  local hint = (cli_visible and mon_visible) and " [;; Switch] " or " [; Hide] "

  vim.api.nvim_set_hl(0, 'MyWinBar', { bg = '#80a3d4', fg = '#000000' })
  if pio_cli_win and vim.api.nvim_win_is_valid(pio_cli_win) then
    vim.api.nvim_set_option_value('winbar', '%#MyWinBar# Pio CLI>' .. hint .. '%*', { scope = 'local', win = pio_cli_win })
  end
  if pio_mon_win and vim.api.nvim_win_is_valid(pio_mon_win) then
    vim.api.nvim_set_option_value('winbar', '%#MyWinBar# Pio Monitor' .. hint .. '%*', { scope = 'local', win = pio_mon_win })
  end
end

local function SafeCloseTerminal(buf_id)
  if buf_id and vim.api.nvim_buf_is_valid(buf_id) then
    local win_id = vim.fn.bufwinid(buf_id)
    if win_id and win_id ~= -1 and vim.api.nvim_win_is_valid(win_id) then
      vim.api.nvim_win_close(win_id, true)
    end
  end
  if buf_id == pio_cli_buf then pio_cli_win = nil end
  if buf_id == pio_mon_buf then pio_mon_win = nil end
  vim.schedule(function()
    vim.cmd("wincmd =")
    UpdateWinbarTitles()
  end)
end


function M.ToggleTerminal(command, terminal_type)
  if terminal_type ~= "monitor" and terminal_type ~= "cli" then
    terminal_type = (command and string.find(command, ' monitor')) and "monitor" or "cli"
  end

  local target_win = (terminal_type == "monitor") and pio_mon_win or pio_cli_win
  local other_win = (terminal_type == "monitor") and pio_cli_win or pio_mon_win
  local target_buf = (terminal_type == "monitor") and pio_mon_buf or pio_cli_buf
  local other_buf = (terminal_type == "monitor") and pio_cli_buf or pio_mon_buf

  if target_win and not vim.api.nvim_win_is_valid(target_win) then
    if terminal_type == "monitor" then pio_mon_win = nil else pio_cli_win = nil end
    target_win = nil
  end
  if other_win and not vim.api.nvim_win_is_valid(other_win) then
    if terminal_type == "monitor" then pio_cli_win = nil else pio_mon_win = nil end
    other_win = nil
  end

  if other_win and vim.api.nvim_win_is_valid(other_win) then
    SafeCloseTerminal(other_buf)
    vim.schedule(function() M.ToggleTerminal(command, terminal_type) end)
    return
  end

  if target_win and vim.api.nvim_win_is_valid(target_win) then
    vim.api.nvim_set_current_win(target_win)
    pcall(vim.api.nvim_win_set_height, target_win, target_panel_height)
    if command and command ~= '' then
      local job_id = vim.b[target_buf].terminal_job_id
      if job_id then vim.fn.chansend(job_id, command .. (vim.fn.has('win32') == 1 and '\r\n' or '\n')) end
    end
    return
  end

  local is_new_buffer = false
  if not target_buf or not vim.api.nvim_buf_is_valid(target_buf) then
    target_buf = vim.api.nvim_create_buf(false, true)
    is_new_buffer = true
    if terminal_type == "monitor" then pio_mon_buf = target_buf else pio_cli_buf = target_buf end
  end

  target_panel_height = math.ceil(vim.o.lines * 0.28)
  local win_opts = { split = "below", win = -1, height = target_panel_height }

  local new_win = vim.api.nvim_open_win(target_buf, true, win_opts)
  if terminal_type == "monitor" then pio_mon_win = new_win else pio_cli_win = new_win end

  if is_new_buffer then
    local target_shell = vim.fn.has('win32') == 1 and "pwsh.exe" or vim.o.shell
    local spawned_job_id = vim.fn.jobstart(target_shell, {
      term = true,
      on_stdout = function(j, d, e) if terminal_type == "cli" and type(M.stdout_callback) == 'function' then M.stdout_callback(j, d, e) end end,
      on_stderr = function(j, d, e) if terminal_type == "cli" and type(M.stdout_callback) == 'function' then M.stdout_callback(j, d, e) end end,
      on_exit = function() if type(M.exit_callback) == 'function' then M.exit_callback() end end
    })
    vim.b[target_buf].terminal_job_id = spawned_job_id

    local scroll_group = vim.api.nvim_create_augroup("PioAutoScroll_" .. target_buf, { clear = true })
    vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
      group = scroll_group, buffer = target_buf,
      callback = function()
        local w = vim.fn.bufwinid(target_buf)
        if w and w ~= -1 and vim.api.nvim_win_is_valid(w) then
          vim.schedule(function() if vim.api.nvim_win_is_valid(w) then vim.api.nvim_win_call(w, function()
            if vim.api.nvim_get_mode().mode:sub(1,1) ~= 't' then vim.cmd('normal! G') end
          end) end end)
        end
      end,
    })
  end

  vim.cmd("setlocal nonumber norelativenumber signcolumn=no")
  vim.api.nvim_set_option_value("winfixheight", true, { scope = "local", win = new_win })

  local pio_group = vim.api.nvim_create_augroup("PioFocusGuard_" .. target_buf, { clear = true })
  vim.api.nvim_create_autocmd("WinEnter", {
    group = pio_group, buffer = target_buf,
    callback = function()
      vim.schedule(function()
        local tw = (terminal_type == "monitor") and pio_mon_win or pio_cli_win
        if tw and vim.api.nvim_win_is_valid(tw) then
          pcall(vim.api.nvim_win_set_height, tw, target_panel_height)
          if vim.api.nvim_get_mode().mode:sub(1,1) ~= 't' then vim.cmd('normal! G') end
        end
      end)
    end,
  })

  UpdateWinbarTitles()

  vim.keymap.set('t', '<Esc>', [[<C-\><C-n>]], { buffer = target_buf })
  vim.keymap.set('n', 'q', function() SafeCloseTerminal(target_buf) end, { buffer = target_buf })

  vim.keymap.set({'n', 't'}, '<C-k>', function()
    if vim.api.nvim_get_mode().mode == 't' then vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes([[<C-\><C-n>]], true, true, true), 'n', false) end
    vim.schedule(function() vim.cmd("wincmd k") end)
  end, { buffer = target_buf, silent = true })

  -- FIXED WINDOW CHECK BINDING: Safely prevents creation leaks from thin air on ';;' shortcuts [INDEX]
  vim.keymap.set({'n', 't'}, ';;', function()
    if vim.api.nvim_get_mode().mode == 't' then
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes([[<C-\><C-n>]], true, true, true), 'n', false)
    end

    local nt = (terminal_type == "monitor") and "cli" or "monitor"
    local nw = (nt == "monitor") and pio_mon_win or pio_cli_win

    -- FIXED WINDOW VISIBILITY CHECK: If opposite layout panel isn't open on screen, act as a hide shortcut [INDEX]
    if not nw or not vim.api.nvim_win_is_valid(nw) then
      SafeCloseTerminal(target_buf)
      return
    end

    SafeCloseTerminal(target_buf)
    vim.schedule(function() M.ToggleTerminal("", nt) end)
  end, { buffer = target_buf, silent = true })

  vim.keymap.set('n', '<C-h>', '<C-w>h')
  vim.keymap.set('n', '<C-l>', '<C-w>l')
  vim.keymap.set('n', '<C-j>', function()
    vim.schedule(function()
      local cw = (terminal_type == "monitor") and pio_mon_win or pio_cli_win
      if cw and vim.api.nvim_win_is_valid(cw) then
        vim.api.nvim_set_current_win(cw)
        pcall(vim.api.nvim_win_set_height, cw, target_panel_height)
        if vim.api.nvim_get_mode().mode:sub(1,1) ~= 't' then vim.cmd('normal! G') end
      else vim.cmd("wincmd j") end
    end)
  end, { silent = true })

  if terminal_type == "monitor" then
    vim.keymap.set('n', [[<leader>\gm]], function() M.ToggleTerminal("", "monitor") end, { silent = true })
  else
    vim.keymap.set('n', [[<leader>\t]], function() M.ToggleTerminal("", "cli") end, { silent = true })
  end

  if command and command ~= '' then
    local job_id = vim.b[target_buf].terminal_job_id
    if job_id then vim.fn.chansend(job_id, command .. (vim.fn.has('win32') == 1 and '\r\n' or '\n')) end
  end
end
-- function M.stdoutcallback(job_id, data, event)
function M.stdoutcallback(_, data, _)
  if not data or #data == 0 or not current_token or current_token == "" then return end
  local processed_lines = {}
  for i, line in ipairs(data) do processed_lines[i] = line:gsub("\r", ""):gsub("\x1b%[[0-9;]*%a", "") end
  local chunk_count = #processed_lines

  if chunk_count > 1 then
    content = content .. pio_buffer .. table.concat(processed_lines, '', 1, chunk_count)
    pio_buffer = processed_lines[chunk_count]
  else
    -- FIXED INDEX BOUNDARY: Explicitly references index 1 to capture the string text literal
    content = content .. pio_buffer .. processed_lines[1]
    pio_buffer = processed_lines[1]
  end

  local pass_target = 'PASS' .. current_id
  local has_pass = content:find('_CMMNDS_' .. current_token .. ':' .. pass_target) ~= nil
  local has_done = content:find('_CMMNDS_' .. current_token .. ':DONE') ~= nil
  local has_fail = content:find('_CMMNDS_' .. current_token .. ':FAIL') ~= nil

  if has_pass or has_fail or has_done then
    local active_cb = callBack
    local final_status = has_fail and 'FAIL' or (has_done and 'DONE' or pass_target)

    if has_fail or has_done then
      callBack = nil
      M.queue = {}

      if clangd_check_active then
        clangd_extracted_args = {}
        local end_pattern = '_CMMNDS_' .. current_token .. ':' .. final_status
        local end_idx = content:find(end_pattern, 1, true)
        local start_idx = nil

        if end_idx then
          local start_pattern = '_CMMNDS_' .. current_token .. '":"' .. final_status
          local fallback_echo = '_CMMNDS_' .. current_token .. '":"DONE'
          local search_zone = content:sub(1, end_idx - 1)
          local current_pos = 1
          while true do
            local next_start, next_end = search_zone:find(start_pattern, current_pos, true)
            if not next_start then
              if not start_idx then
                local fb_start, fb_end = search_zone:find(fallback_echo, current_pos, true)
                if fb_start then start_idx = fb_end end
              end
              break
            end
            start_idx = next_end
            current_pos = next_start + 1
          end
        end

        if start_idx and end_idx and end_idx > start_idx then
          local fresh_run_logs = string.sub(content, start_idx + 1, end_idx - 1)
          if not string.find(fresh_run_logs, '%.clang%-format') then
            local seen = {}
            for arg in string.gmatch(fresh_run_logs, "unknown argument[:%s]+'([^']+)'") do
              local clean_flag = string.format('"%s"', arg:gsub('[;%.]$', ''))
              if not seen[clean_flag] then
                seen[clean_flag] = true
                table.insert(clangd_extracted_args, clean_flag)
              end
            end
          end
        else
          pio_buffer = ""
          content = ""
          return
        end
        clangd_check_active = false
      end
      pio_buffer = ''
      content = ''
    end

    if final_status and active_cb then vim.schedule(function() active_cb(final_status) end) end
    return
  end
end

-- =============================================================================
local function pop(queue)
  local current_step = table.remove(queue, 1)
  local base_cmd = current_step[1]
  current_id = current_step[2]
  current_token = current_step[3]

  -- Formulate the target words dynamically
  local target_word = current_id == 0 and 'DONE' or ('PASS' .. current_id)

  -- Create your target echo layouts
  local pass_echo = string.format('_CMMNDS_%s":"%s', current_token, target_word)
  local fail_echo = string.format('_CMMNDS_%s":"FAIL', current_token)

  -- Format native platform operators properly to escape quotes securely
  local win_str = string.format('  && echo %s || echo %s', pass_echo, fail_echo)
  local nix_str = string.format('  && echo "%s" || echo "%s"', pass_echo, fail_echo)
  local full_shell_cmd = base_cmd .. (OS.is_win and win_str or nix_str)
  return full_shell_cmd
end

-- INFO: commands sequencer
-- stylua: ignore
-- =============================================================================
-- local nvimpio = require('nvimpio')
M.run_sequence = function(tasks)
  M.queue = {}
  local commands = tasks.cmnds
  fromMsg = tasks.from
  callBack = tasks.cb -- 1. Save the callback in a local variable

  local token = string.format('%04d', session_counter)

  session_counter = session_counter + 1
  if session_counter > 9999 then
    session_counter = 1
  end

  local total = #commands
  for i, cmd in ipairs(commands) do
    local step_id = (i == total) and 0 or i
    table.insert(M.queue, { cmd, step_id, token })
  end

  -- if not nvimpio.is_active then
  --   require('nvimpio.pio.metadata')
  -- end

  if callBack then
    vim.schedule(function()
      content = ''
      pio_buffer = ''
      clangd_extracted_args = {} -- Clear the collected flags table
      clangd_check_active = false -- Arm the parsing loop tracker

      M.stdout_callback = M.stdoutcallback
      callBack('INIT')
    end)
  end
end

------------------------------------------------------
-- Handle after pioinit execution
-- =============================================================================
-- stylua: ignore
function M.cleanSequencer()
  _G.metadata.isBusy = false
  M.stdout_callback = nil -- Careful: make sure this doesn't break other terms
  -- if trm then trm:close() end
end

return M
-- local M = {}
--
-- M.stdout_callback = nil
-- M.exit_callback = nil
--
-- local pio_cli_buf = nil
-- local pio_mon_buf = nil
--
-- local pio_cli_win = nil
-- local pio_mon_win = nil
--
-- local target_panel_height = 0
--
-- local function SafeCloseTerminal(buf_id)
--   if buf_id and vim.api.nvim_buf_is_valid(buf_id) then
--     local win_id = vim.fn.bufwinid(buf_id)
--     if win_id and win_id ~= -1 and vim.api.nvim_win_is_valid(win_id) then
--       vim.api.nvim_win_close(win_id, true)
--     end
--   end
--
--   if buf_id == pio_cli_buf then pio_cli_win = nil end
--   if buf_id == pio_mon_buf then pio_mon_win = nil end
--
--   vim.schedule(function() vim.cmd('wincmd =') end)
-- end
--
--
-- function M.ToggleTerminal(command, terminal_type)
--   if terminal_type ~= "monitor" and terminal_type ~= "cli" then
--     if command and string.find(command, ' monitor') then
--       terminal_type = "monitor"
--     else
--       terminal_type = "cli"
--     end
--   end
--
--   local title = (terminal_type == "monitor") and " Pio Monitor " or " Pio CLI> "
--   local target_win = (terminal_type == "monitor") and pio_mon_win or pio_cli_win
--   local other_win = (terminal_type == "monitor") and pio_cli_win or pio_mon_win
--   local target_buf = (terminal_type == "monitor") and pio_mon_buf or pio_cli_buf
--   local other_buf = (terminal_type == "monitor") and pio_cli_buf or pio_mon_buf
--
--   if target_win and not vim.api.nvim_win_is_valid(target_win) then
--     if terminal_type == "monitor" then pio_mon_win = nil else pio_cli_win = nil end
--     target_win = nil
--   end
--   if other_win and not vim.api.nvim_win_is_valid(other_win) then
--     if terminal_type == "monitor" then pio_mon_win = nil else pio_cli_win = nil end
--     other_win = nil
--   end
--
--   if other_win and vim.api.nvim_win_is_valid(other_win) then
--     SafeCloseTerminal(other_buf)
--     vim.schedule(function() M.ToggleTerminal(command, terminal_type) end)
--     return
--   end
--
--   if target_win and vim.api.nvim_win_is_valid(target_win) then
--     vim.api.nvim_set_current_win(target_win)
--     pcall(vim.api.nvim_win_set_height, target_win, target_panel_height)
--     if command and command ~= '' then
--       local job_id = vim.b[target_buf].terminal_job_id
--       if job_id then
--         vim.fn.chansend(job_id, command .. (vim.fn.has('win32') == 1 and '\r\n' or '\n'))
--       end
--     end
--     return
--   end
--
--   local is_new_buffer = false
--   if not target_buf or not vim.api.nvim_buf_is_valid(target_buf) then
--     target_buf = vim.api.nvim_create_buf(false, true)
--     is_new_buffer = true
--     if terminal_type == "monitor" then pio_mon_buf = target_buf else pio_cli_buf = target_buf end
--   end
--
--   target_panel_height = math.ceil(vim.o.lines * 0.28)
--   local win_opts = { split = "below", win = -1, height = target_panel_height }
--
--   local new_win = vim.api.nvim_open_win(target_buf, true, win_opts)
--   if terminal_type == "monitor" then pio_mon_win = new_win else pio_cli_win = new_win end
--
--   if is_new_buffer then
--     local target_shell = vim.o.shell
--     if vim.fn.has('win32') == 1 then
--       target_shell = "pwsh.exe"
--     end
--
--     local spawned_job_id = vim.fn.jobstart(target_shell, {
--       term = true,
--       on_stdout = function(j, d, e) if terminal_type == "cli" and type(M.stdout_callback) == 'function' then M.stdout_callback(j, d, e) end end,
--       on_stderr = function(j, d, e) if terminal_type == "cli" and type(M.stdout_callback) == 'function' then M.stdout_callback(j, d, e) end end,
--       on_exit = function() if type(M.exit_callback) == 'function' then M.exit_callback() end end
--     })
--     vim.b[target_buf].terminal_job_id = spawned_job_id
--
--     local scroll_group = vim.api.nvim_create_augroup("PioAutoScroll_" .. target_buf, { clear = true })
--     vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
--       group = scroll_group,
--       buffer = target_buf,
--       callback = function()
--         local w = vim.fn.bufwinid(target_buf)
--         if w and w ~= -1 and vim.api.nvim_win_is_valid(w) then
--           vim.schedule(function() if vim.api.nvim_win_is_valid(w) then vim.api.nvim_win_call(w, function()
--             if vim.api.nvim_get_mode().mode:sub(1,1) ~= 't' then vim.cmd('normal! G') end
--           end) end end)
--         end
--       end,
--     })
--   end
--
--   vim.cmd("setlocal nonumber norelativenumber signcolumn=no")
--   vim.api.nvim_set_option_value("winfixheight", true, { scope = "local", win = new_win })
--
--   local pio_group = vim.api.nvim_create_augroup("PioFocusGuard_" .. target_buf, { clear = true })
--   vim.api.nvim_create_autocmd("WinEnter", {
--     group = pio_group,
--     buffer = target_buf,
--     callback = function()
--       vim.schedule(function()
--         local tw = (terminal_type == "monitor") and pio_mon_win or pio_cli_win
--         if tw and vim.api.nvim_win_is_valid(tw) then
--           pcall(vim.api.nvim_win_set_height, tw, target_panel_height)
--           if vim.api.nvim_get_mode().mode:sub(1,1) ~= 't' then vim.cmd('normal! G') end
--         end
--       end)
--     end,
--   })
--
--   vim.api.nvim_set_hl(0, 'MyWinBar', { bg = '#80a3d4', fg = '#000000' })
--   vim.api.nvim_set_option_value('winbar', '%#MyWinBar#' .. title .. '%*', { scope = 'local', win = new_win })
--
--   vim.keymap.set('t', '<Esc>', [[<C-\><C-n>]], { buffer = target_buf })
--   vim.keymap.set('n', 'q', function() SafeCloseTerminal(target_buf) end, { buffer = target_buf })
--
--   vim.keymap.set({'n', 't'}, '<C-k>', function()
--     if vim.api.nvim_get_mode().mode == 't' then vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes([[<C-\><C-n>]], true, true, true), 'n', false) end
--     vim.schedule(function() vim.cmd("wincmd k") end)
--   end, { buffer = target_buf, silent = true })
--
--   -- FIXED SWITCHER LOCK: Validates screen window visibility status directly
--   vim.keymap.set({'n', 't'}, ';;', function()
--     if vim.api.nvim_get_mode().mode == 't' then
--       vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes([[<C-\><C-n>]], true, true, true), 'n', false)
--     end
--
--     local nt = (terminal_type == "monitor") and "cli" or "monitor"
--     local nb = (nt == "monitor") and pio_mon_buf or pio_cli_buf
--
--     -- HARD PROTECTION BOUNDARY: Check if the opposite terminal window is visible on screen.
--     -- If it isn't drawn anywhere, pressing ';;' does nothing, matching your exact intent!
--     if not nb or vim.fn.bufwinid(nb) == -1 then
--       return
--     end
--
--     SafeCloseTerminal(target_buf)
--     vim.schedule(function() M.ToggleTerminal("", nt) end)
--   end, { buffer = target_buf, silent = true })
--
--   vim.keymap.set('n', '<C-h>', '<C-w>h')
--   vim.keymap.set('n', '<C-l>', '<C-w>l')
--   vim.keymap.set('n', '<C-j>', function()
--     vim.schedule(function()
--       local cw = (terminal_type == "monitor") and pio_mon_win or pio_cli_win
--       if cw and vim.api.nvim_win_is_valid(cw) then
--         vim.api.nvim_set_current_win(cw)
--         pcall(vim.api.nvim_win_set_height, cw, target_panel_height)
--         if vim.api.nvim_get_mode().mode:sub(1,1) ~= 't' then vim.cmd('normal! G') end
--       else
--         vim.cmd("wincmd j")
--       end
--     end)
--   end, { silent = true })
--
--   if terminal_type == "monitor" then
--     vim.keymap.set('n', [[<leader>\gm]], function() M.ToggleTerminal("", "monitor") end, { silent = true })
--   else
--     vim.keymap.set('n', [[<leader>\t]], function() M.ToggleTerminal("", "cli") end, { silent = true })
--   end
--
--   if command and command ~= '' then
--     local job_id = vim.b[target_buf].terminal_job_id
--     if job_id then vim.fn.chansend(job_id, command .. (vim.fn.has('win32') == 1 and '\r\n' or '\n')) end
--   end
-- end
-- -- function M.stdoutcallback(job_id, data, event)
-- --   if not data or #data == 0 or not current_token or current_token == "" then return end
-- --
-- --   local processed_lines = {}
-- --   for i, line in ipairs(data) do processed_lines[i] = line:gsub("\r", ""):gsub("\x1b%[[0-9;]*%a", "") end
-- --   local chunk_count = #processed_lines
-- --
-- --   if chunk_count > 1 then
-- --     content = content .. pio_buffer .. table.concat(processed_lines, '', 1, chunk_count)
-- --     pio_buffer = processed_lines[chunk_count]
-- --   else
-- --     content = content .. pio_buffer .. processed_lines
-- --     pio_buffer = processed_lines
-- --   end
-- --
-- --   local pass_target = 'PASS' .. current_id
-- --   local has_pass = content:find('_CMMNDS_' .. current_token .. ':' .. pass_target) ~= nil
-- --   local has_done = content:find('_CMMNDS_' .. current_token .. ':DONE') ~= nil
-- --   local has_fail = content:find('_CMMNDS_' .. current_token .. ':FAIL') ~= nil
-- --
-- --   if has_pass or has_fail or has_done then
-- --     local active_cb = callBack
-- --     local final_status = has_fail and 'FAIL' or (has_done and 'DONE' or pass_target)
-- --
-- --     if has_fail or has_done then
-- --       callBack = nil
-- --       M.queue = {}
-- --
-- --       if clangd_check_active then
-- --         clangd_extracted_args = {}
-- --         local end_pattern = '_CMMNDS_' .. current_token .. ':' .. final_status
-- --         local end_idx = content:find(end_pattern, 1, true)
-- --         local start_idx = nil
-- --
-- --         if end_idx then
-- --           local start_pattern = '_CMMNDS_' .. current_token .. '":"' .. final_status
-- --           local fallback_echo = '_CMMNDS_' .. current_token .. '":"DONE'
-- --           local search_zone = content:sub(1, end_idx - 1)
-- --           local current_pos = 1
-- --           while true do
-- --             local next_start, next_end = search_zone:find(start_pattern, current_pos, true)
-- --             if not next_start then
-- --               if not start_idx then
-- --                 local fb_start, fb_end = search_zone:find(fallback_echo, current_pos, true)
-- --                 if fb_start then start_idx = fb_end end
-- --               end
-- --               break
-- --             end
-- --             start_idx = next_end
-- --             current_pos = next_start + 1
-- --           end
-- --         end
-- --
-- --         if start_idx and end_idx and end_idx > start_idx then
-- --           local fresh_run_logs = string.sub(content, start_idx + 1, end_idx - 1)
-- --           if not string.find(fresh_run_logs, '%.clang%-format') then
-- --             local seen = {}
-- --             for arg in string.gmatch(fresh_run_logs, "unknown argument[:%s]+'([^']+)'") do
-- --               local clean_flag = string.format('"%s"', arg:gsub('[;%.]$', ''))
-- --               if not seen[clean_flag] then
-- --                 seen[clean_flag] = true
-- --                 table.insert(clangd_extracted_args, clean_flag)
-- --               end
-- --             end
-- --           end
-- --         else
-- --           pio_buffer = ""
-- --           content = ""
-- --           return
-- --         end
-- --         clangd_check_active = false
-- --       end
-- --       pio_buffer = ''
-- --       content = ''
-- --     end
-- --
-- --     if final_status and active_cb then vim.schedule(function() active_cb(final_status) end) end
-- --     return
-- --   end
-- -- end
--
-- return M
