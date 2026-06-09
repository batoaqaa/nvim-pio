local M = {}
local current_token -- = tostring(math.random(10000, 99999))
local session_counter = 1 -- Our high-performance integer counter
local current_id = -1

local callBack = nil
M.queue = {}

local clangd_extracted_args = {}
local clangd_check_active = false

local fromMsg = ''

M.stdout_callback = nil
M.exit_callback = nil

-- Hidden internal storage cells to keep the tracking metrics completely isolated

local pio_cli_win = nil
local pio_mon_win = nil

local target_panel_height = 0
local pio_buffer = ''
local content = ''

-- ----------------------------------------------------------------------------------------
-- -- 🔍 ABSOLUTE STATE TRACKING METATABLE PROXY
-- ----------------------------------------------------------------------------------------
-- -- This wraps the module keys. The exact millisecond any outside script attempts to
-- -- overwrite or read your buffer variables, it captures a complete system traceback map!
-- setmetatable(M, {
--   __newindex = function(table, key, value)
--     if key == 'pio_cli_buf' or key == 'pio_mon_buf' then
--       local trace = debug.traceback()
--       -- Safely isolate the exact filename and line number row from the stack array
--       local calling_line = trace:match('\n[^\n]+\n\t([^\n]+)') or 'Unknown Caller Layer'
--
--       vim.notify(
--         string.format('\n🚨 [MODULE OVERWRITE DETECTED]\nVariable: %s\nAssigned Value: %s\nCaller Path: %s', key, tostring(value), calling_line),
--         vim.log.levels.WARN
--       )
--
--       if key == 'pio_cli_buf' then
--         _internal_cli_buf = value
--       else
--         _internal_mon_buf = value
--       end
--     else
--       rawset(table, key, value)
--     end
--   end,
--   __index = function(table, key)
--     if key == 'pio_cli_buf' then
--       return _internal_cli_buf
--     elseif key == 'pio_mon_buf' then
--       return _internal_mon_buf
--     else
--       return rawget(table, key)
--     end
--   end,
-- })
-- AUTOMATED TELEMETRY: Updates text titles based on true visible split row presences
local function UpdateWinbarTitles()
  local cli_visible = pio_cli_win and vim.api.nvim_win_is_valid(pio_cli_win)
  local mon_visible = pio_mon_win and vim.api.nvim_win_is_valid(pio_mon_win)

  -- Hardlock rule: Display [;; Switch] ONLY if both panels are open on screen right now
  local hint = (cli_visible and mon_visible) and ' [;; Switch] ' or ' [; Hide] '

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
  if buf_id == M.pio_cli_buf then
    pio_cli_win = nil
  end
  if buf_id == M.pio_mon_buf then
    pio_mon_win = nil
  end
  vim.schedule(function()
    vim.cmd('wincmd =')
    UpdateWinbarTitles()
  end)
end

function M.ToggleTerminal(command, terminal_type)
  terminal_type = (terminal_type == 'monitor') and 'monitor' or 'cli'
  if terminal_type ~= 'monitor' and terminal_type ~= 'cli' then
    terminal_type = (command and string.find(command, ' monitor')) and 'monitor' or 'cli'
  end

  local target_win = (terminal_type == 'monitor') and pio_mon_win or pio_cli_win
  local other_win = (terminal_type == 'monitor') and pio_cli_win or pio_mon_win
  local target_buf = (terminal_type == 'monitor') and M.pio_mon_buf or M.pio_cli_buf
  local other_buf = (terminal_type == 'monitor') and M.pio_cli_buf or M.pio_mon_buf

  if target_win and not vim.api.nvim_win_is_valid(target_win) then
    if terminal_type == 'monitor' then
      pio_mon_win = nil
    else
      pio_cli_win = nil
    end
    target_win = nil
  end
  if other_win and not vim.api.nvim_win_is_valid(other_win) then
    if terminal_type == 'monitor' then
      pio_mon_win = nil
    else
      pio_cli_win = nil
    end
    other_win = nil
  end

  if other_win and vim.api.nvim_win_is_valid(other_win) then
    SafeCloseTerminal(other_buf)
    vim.schedule(function()
      M.ToggleTerminal(command, terminal_type)
    end)
    return
  end

  if target_win and vim.api.nvim_win_is_valid(target_win) then
    vim.api.nvim_set_current_win(target_win)
    pcall(vim.api.nvim_win_set_height, target_win, target_panel_height)
    return
  end

  local is_new_buffer = false
  if not target_buf or not vim.api.nvim_buf_is_valid(target_buf) then
    target_buf = vim.api.nvim_create_buf(false, true)
    is_new_buffer = true
    if terminal_type == 'monitor' then
      M.pio_mon_buf = target_buf
    else
      M.pio_cli_buf = target_buf
    end
  end

  target_panel_height = math.ceil(vim.o.lines * 0.28)
  local win_opts = { split = 'below', win = -1, height = target_panel_height }

  local new_win = vim.api.nvim_open_win(target_buf, true, win_opts)
  if terminal_type == 'monitor' then
    pio_mon_win = new_win
  else
    pio_cli_win = new_win
  end

  if is_new_buffer then
    local target_shell = vim.fn.has('win32') == 1 and 'pwsh.exe' or vim.o.shell
    local spawned_job_id = vim.fn.jobstart(target_shell, {
      term = true,
      on_stdout = function(j, d, e)
        if terminal_type == 'cli' and type(M.stdout_callback) == 'function' then
          M.stdout_callback(j, d, e)
        end
      end,
      on_stderr = function(j, d, e)
        if terminal_type == 'cli' and type(M.stdout_callback) == 'function' then
          M.stdout_callback(j, d, e)
        end
      end,
      on_exit = function()
        if type(M.exit_callback) == 'function' then
          M.exit_callback()
        end
      end,
    })
    vim.b[target_buf].terminal_job_id = spawned_job_id

    local scroll_group = vim.api.nvim_create_augroup('PioAutoScroll_' .. target_buf, { clear = true })
    vim.api.nvim_create_autocmd({ 'TextChanged', 'TextChangedI' }, {
      group = scroll_group,
      buffer = target_buf,
      callback = function()
        local w = vim.fn.bufwinid(target_buf)
        if w and w ~= -1 and vim.api.nvim_win_is_valid(w) then
          vim.schedule(function()
            if vim.api.nvim_win_is_valid(w) then
              vim.api.nvim_win_call(w, function()
                if vim.api.nvim_get_mode().mode:sub(1, 1) ~= 't' then
                  vim.cmd('normal! G')
                end
              end)
            end
          end)
        end
      end,
    })
  end

  vim.cmd('setlocal nonumber norelativenumber signcolumn=no')
  vim.api.nvim_set_option_value('winfixheight', true, { scope = 'local', win = new_win })

  local pio_group = vim.api.nvim_create_augroup('PioFocusGuard_' .. target_buf, { clear = true })
  vim.api.nvim_create_autocmd('WinEnter', {
    group = pio_group,
    buffer = target_buf,
    callback = function()
      vim.schedule(function()
        local tw = (terminal_type == 'monitor') and pio_mon_win or pio_cli_win
        if tw and vim.api.nvim_win_is_valid(tw) then
          pcall(vim.api.nvim_win_set_height, tw, target_panel_height)
          if vim.api.nvim_get_mode().mode:sub(1, 1) ~= 't' then
            vim.cmd('normal! G')
          end
        end
      end)
    end,
  })

  UpdateWinbarTitles()

  vim.keymap.set('t', '<Esc>', [[<C-\><C-n>]], { buffer = target_buf })
  vim.keymap.set('n', 'q', function()
    SafeCloseTerminal(target_buf)
  end, { buffer = target_buf })

  vim.keymap.set({ 'n', 't' }, '<C-k>', function()
    if vim.api.nvim_get_mode().mode == 't' then
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes([[<C-\><C-n>]], true, true, true), 'n', false)
    end
    vim.schedule(function()
      vim.cmd('wincmd k')
    end)
  end, { buffer = target_buf, silent = true })

  -- 🌟 UN-HIJACKABLE STATE-TITLE SWITCHER MAPPING 🌟
  vim.keymap.set({ 'n', 't' }, ';;', function()
    if vim.api.nvim_get_mode().mode == 't' then
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes([[<C-\><C-n>]], true, true, true), 'n', false)
    end

    -- Explicitly verify your active winbar layout string content directly
    local current_winbar = vim.api.nvim_get_option_value('winbar', { scope = 'local' }) or ''

    -- HARD PROTECTION BOUNDARY: If the winbar string contains the active hide parameter text '[; Hide]',
    -- treat ';;' as a safe window hider (a single ';') and close the current window panel cleanly!
    -- This makes it physically impossible to pass variables down or trigger a ToggleTerminal spawn!
    if current_winbar:find('%[; Hide%]') then
      SafeCloseTerminal(target_buf)
      return
    end

    local next_type = (terminal_type == 'monitor') and 'cli' or 'monitor'
    SafeCloseTerminal(target_buf)
    vim.schedule(function()
      M.ToggleTerminal('', next_type)
    end)
  end, { buffer = target_buf, silent = true })

  vim.keymap.set('n', '<C-h>', '<C-w>h')
  vim.keymap.set('n', '<C-l>', '<C-w>l')
  vim.keymap.set('n', '<C-j>', function()
    vim.schedule(function()
      local cw = (terminal_type == 'monitor') and pio_mon_win or pio_cli_win
      if cw and vim.api.nvim_win_is_valid(cw) then
        vim.api.nvim_set_current_win(cw)
        pcall(vim.api.nvim_win_set_height, cw, target_panel_height)
        if vim.api.nvim_get_mode().mode:sub(1, 1) ~= 't' then
          vim.cmd('normal! G')
        end
      else
        vim.cmd('wincmd j')
      end
    end)
  end, { silent = true })
end

vim.keymap.set('n', [[<leader>\gm]], function()
  M.ToggleTerminal('', 'monitor')
end, { silent = true })
vim.keymap.set('n', [[<leader>\t]], function()
  M.ToggleTerminal('', 'cli')
end, { silent = true })

vim.keymap.set('n', [[<leader>\gm]], function()
  M.ToggleTerminal('', 'monitor')
end, { silent = true })
vim.keymap.set('n', [[<leader>\t]], function()
  M.ToggleTerminal('', 'cli')
end, { silent = true })

function M.stdoutcallback(job_id, data, event)
  if not data or #data == 0 or not current_token or current_token == '' then
    return
  end
  local processed_lines = {}
  for i, line in ipairs(data) do
    processed_lines[i] = line:gsub('\r', ''):gsub('\x1b%[[0-9;]*%a', '')
  end
  local chunk_count = #processed_lines

  if chunk_count > 1 then
    content = content .. pio_buffer .. table.concat(processed_lines, '', 1, chunk_count)
    pio_buffer = processed_lines[chunk_count]
  else
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
                if fb_start then
                  start_idx = fb_end
                end
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
          pio_buffer = ''
          content = ''
          return
        end
        clangd_check_active = false
      end
      pio_buffer = ''
      content = ''
    end

    if final_status and active_cb then
      vim.schedule(function()
        active_cb(final_status)
      end)
    end
    return
  end
end

return M
