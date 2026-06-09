local M = {}

-- Assigned dynamically by external sub-modules like 'platformio.utils.pio'
M.stdout_callback = nil
M.exit_callback = nil

-- Persistent background storage buffers for running shell processes
local pio_cli_buf = nil
local pio_mon_buf = nil

-- Display window tracking handles
local pio_cli_win = nil
local pio_mon_win = nil

-- HARD-LOCK HEIGHT PROFILE METRIC: Stores the static target height globally
local target_panel_height = 0

----------------------------------------------------------------------------------------
-- INFO: Safe terminal exit routine (Cleans up window IDs to stop duplicate spawning)
local function SafeCloseTerminal(buf_id)
  if buf_id and vim.api.nvim_buf_is_valid(buf_id) then
    local win_id = vim.fn.bufwinid(buf_id)
    if win_id and win_id ~= -1 and vim.api.nvim_win_is_valid(win_id) then
      vim.api.nvim_win_close(win_id, true)
    end
  end

  -- Synchronize tracking pointer handles immediately on window destruction
  if buf_id == pio_cli_buf then
    pio_cli_win = nil
  end
  if buf_id == pio_mon_buf then
    pio_mon_win = nil
  end

  vim.schedule(function()
    vim.cmd('wincmd =')
  end)
end

----------------------------------------------------------------------------------------
-- INFO: Core Layout Spawner (Global Edge-Anchored Window Partition Architecture)
function M.ToggleTerminal(command, terminal_type)
  -- 1. FIXED TYPE RESOLUTION: Enforce type prioritizing explicit string signatures
  if terminal_type ~= 'monitor' and terminal_type ~= 'cli' then
    if command and string.find(command, ' monitor') then
      terminal_type = 'monitor'
    else
      terminal_type = 'cli'
    end
  end

  local title = (terminal_type == 'monitor') and ' Pio Monitor ' or ' Pio CLI> '
  local target_win = (terminal_type == 'monitor') and pio_mon_win or pio_cli_win
  local other_win = (terminal_type == 'monitor') and pio_cli_win or pio_mon_win
  local target_buf = (terminal_type == 'monitor') and pio_mon_buf or pio_cli_buf
  local other_buf = (terminal_type == 'monitor') and pio_cli_buf or pio_mon_buf

  -- Validate tracking references defensively before evaluating layout changes
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
      pio_cli_win = nil
    else
      pio_mon_win = nil
    end
    other_win = nil
  end

  -- 2. MUTUAL EXCLUSION ASYNC BRIDGE: Hide other panel before rendering target
  if other_win and vim.api.nvim_win_is_valid(other_win) then
    SafeCloseTerminal(other_buf)

    -- Defer layout calculations to the next event loop tick to clear screen space cleanly
    vim.schedule(function()
      M.ToggleTerminal(command, terminal_type)
    end)
    return
  end

  -- 3. ALWAYS-OPEN TARGET ENGINE: Focus pre-existing window handle instead of duplicating
  if target_win and vim.api.nvim_win_is_valid(target_win) then
    vim.api.nvim_set_current_win(target_win)
    pcall(vim.api.nvim_win_set_height, target_win, target_panel_height)

    -- If a new execution command macro was passed, pipe it directly down to the shell channel
    if command and command ~= '' then
      local job_id = vim.b[target_buf].terminal_job_id
      if job_id then
        vim.fn.chansend(job_id, command .. (vim.fn.has('win32') == 1 and '\r\n' or '\n'))
      end
    end
    return
  end

  -- 4. CLEAN BUFFER PROVISION: Instantiates an unlisted scratch buffer cleanly
  local is_new_buffer = false
  if not target_buf or not vim.api.nvim_buf_is_valid(target_buf) then
    target_buf = vim.api.nvim_create_buf(false, true)
    is_new_buffer = true
    if terminal_type == 'monitor' then
      pio_mon_buf = target_buf
    else
      pio_cli_buf = target_buf
    end
  end

  -- 5. ABSOLUTE GLOBAL GRID TREE CONFIGURATION:
  target_panel_height = math.ceil(vim.o.lines * 0.28)

  local win_opts = {
    split = 'below', -- Directions token to open the partition beneath upper nodes
    win = -1, -- HARDLOCK GRID: Breaks out of local columns into top-level monitor screen frame
    height = target_panel_height,
  }

  -- 6. RENDER THE STABLE WINDOW PANE
  local new_win = vim.api.nvim_open_win(target_buf, true, win_opts)
  if terminal_type == 'monitor' then
    pio_mon_win = new_win
  else
    pio_cli_win = new_win
  end

  -- 7. PROCESS LAUNCHER: Spawns the shell thread strictly after the layout window is alive
  if is_new_buffer then
    local target_shell = vim.o.shell
    if vim.fn.has('win32') == 1 then
      if vim.fn.executable('pwsh.exe') == 1 then
        target_shell = 'pwsh.exe'
      else
        target_shell = 'powershell.exe'
      end
    end

    local spawned_job_id = vim.fn.jobstart(target_shell, {
      term = true,
      on_stdout = function(job_id, data, event)
        if type(M.stdout_callback) == 'function' then
          M.stdout_callback(job_id, data, event)
        end
      end,
      on_stderr = function(job_id, data, event)
        if type(M.stdout_callback) == 'function' then
          M.stdout_callback(job_id, data, event)
        end
      end,
      on_exit = function()
        if type(M.exit_callback) == 'function' then
          M.exit_callback()
        end
      end,
    })

    -- Bind job ID to the buffer variables so chansend targets the same persistent terminal shell
    vim.b[target_buf].terminal_job_id = spawned_job_id

    -- AUTOMATED VIEWPORT SCROLL REFLOW ENGINE:
    local scroll_group = vim.api.nvim_create_augroup('PioAutoScroll_' .. target_buf, { clear = true })
    vim.api.nvim_create_autocmd({ 'TextChanged', 'TextChangedI' }, {
      group = scroll_group,
      buffer = target_buf,
      callback = function()
        local active_term_win = vim.fn.bufwinid(target_buf)
        if active_term_win and active_term_win ~= -1 and vim.api.nvim_win_is_valid(active_term_win) then
          vim.schedule(function()
            if vim.api.nvim_win_is_valid(active_term_win) then
              vim.api.nvim_win_call(active_term_win, function()
                local mode = vim.api.nvim_get_mode().mode
                if mode == 'n' or mode == 'nt' then
                  vim.cmd('normal! G')
                end
              end)
            end
          end)
        end
      end,
    })
  end

  -- 8. CLEAN SYSTEM WINDOW FLAGS
  vim.cmd('setlocal nonumber norelativenumber signcolumn=no')
  vim.api.nvim_set_option_value('winfixheight', true, { scope = 'local', win = new_win })

  -- 9. FIXED ANTI-SHRINKING VIEWPORT GUARD WITH RACE-CONDITION EXCLUSION
  local pio_group = vim.api.nvim_create_augroup('PioFocusGuard_' .. target_buf, { clear = true })
  vim.api.nvim_create_autocmd('WinEnter', {
    group = pio_group,
    buffer = target_buf,
    callback = function()
      vim.schedule(function()
        local term_win = (terminal_type == 'monitor') and pio_mon_win or pio_cli_win
        if term_win and vim.api.nvim_win_is_valid(term_win) then
          pcall(vim.api.nvim_win_set_height, term_win, target_panel_height)
          local mode = vim.api.nvim_get_mode().mode
          if mode == 'n' or mode == 'nt' then
            vim.cmd('normal! G')
          end
        end
      end)
    end,
  })

  -- 10. VISUAL CUSTOM WINBAR STYLING
  local hl = { bg = '#80a3d4', fg = '#000000' }
  vim.api.nvim_set_hl(0, 'MyWinBar', { bg = hl.bg, fg = hl.fg })
  local winBartitle = '%#MyWinBar#' .. title .. '%*'
  vim.api.nvim_set_option_value('winbar', winBartitle, { scope = 'local', win = new_win })

  -----------------------------------------------------------------------------
  -- LOCAL MAPS (Scoped strictly to this terminal buffer layer instance)
  -----------------------------------------------------------------------------
  vim.keymap.set('t', '<Esc>', [[<C-\><C-n>]], { buffer = target_buf })
  vim.keymap.set('n', 'q', function()
    SafeCloseTerminal(target_buf)
  end, { buffer = target_buf })

  -- CRASH-FREE UPWARD NAVIGATION KEYMAP
  vim.keymap.set({ 'n', 't' }, '<C-k>', function()
    if vim.api.nvim_get_mode().mode == 't' then
      local esc = vim.api.nvim_replace_termcodes([[<C-\><C-n>]], true, true, true)
      vim.api.nvim_feedkeys(esc, 'n', false)
    end
    vim.schedule(function()
      vim.cmd('wincmd k')
    end)
  end, { buffer = target_buf, silent = true })

  -- DOUBLE SEMI-COLON CROSS SWITCHER LOGIC
  vim.keymap.set({ 'n', 't' }, ';;', function()
    if vim.api.nvim_get_mode().mode == 't' then
      local esc = vim.api.nvim_replace_termcodes([[<C-\><C-n>]], true, true, true)
      vim.api.nvim_feedkeys(esc, 'n', false)
    end

    local next_type = (terminal_type == 'monitor') and 'cli' or 'monitor'
    vim.schedule(function()
      M.ToggleTerminal('', next_type)
    end)
  end, { buffer = target_buf, silent = true, desc = 'Switch between PlatformIO terminals' })

  -----------------------------------------------------------------------------
  -- GLOBAL NAVIGATION & RECALL SHORTCUTS
  -----------------------------------------------------------------------------
  vim.keymap.set('n', '<C-h>', '<C-w>h')
  vim.keymap.set('n', '<C-l>', '<C-w>l')

  -- GLOBAL INTERCEPT DOWNWARD MOVEMENT HOOK:
  vim.keymap.set('n', '<C-j>', function()
    vim.schedule(function()
      local cur_win = (terminal_type == 'monitor') and pio_mon_win or pio_cli_win
      if cur_win and vim.api.nvim_win_is_valid(cur_win) then
        vim.api.nvim_set_current_win(cur_win)
        pcall(vim.api.nvim_win_set_height, cur_win, target_panel_height)
        local mode = vim.api.nvim_get_mode().mode
        if mode == 'n' or mode == 'nt' then
          vim.cmd('normal! G')
        end
      else
        vim.cmd('wincmd j')
      end
    end)
  end, { silent = true })

  -- CLEAN SHORTCUT REGISTRATION: Fully un-nested to activate keymaps across ALL session states safely
  if terminal_type == 'monitor' then
    vim.keymap.set('n', [[<leader>\gm]], function()
      M.ToggleTerminal('', 'monitor')
    end, { silent = true })
  else
    vim.keymap.set('n', [[<leader>\t]], function()
      M.ToggleTerminal('', 'cli')
    end, { silent = true })
  end

  -- Automatically run passed command strings via your platformio job channels
  if command and command ~= '' then
    local job_id = vim.b[target_buf].terminal_job_id
    if job_id then
      vim.fn.chansend(job_id, command .. (vim.fn.has('win32') == 1 and '\r\n' or '\n'))
    end
  end
end
-- -- INFO: Your unmodified parser logic block remains safely out here
-- function M.stdoutcallback(job_id, data, event)
--   if not data or #data == 0 then
--     return
--   end
--
--   if not current_token or current_token == "" then
--     return
--   end
--
--   local processed_lines = {}
--   for i, line in ipairs(data) do
--     processed_lines[i] = line:gsub("\r", ""):gsub("\x1b%[[0-9;]*%a", "")
--   end
--   local chunk_count = #processed_lines
--
--   if chunk_count > 1 then
--     content = content .. pio_buffer .. table.concat(processed_lines, '', 1, chunk_count)
--     pio_buffer = processed_lines[chunk_count]
--   else
--     -- FIXED ARRAY INDEX SLICER: Maps index 1 to safely extract text strings out of array tables
--     content = content .. pio_buffer .. processed_lines[1]
--     pio_buffer = processed_lines[1]
--   end
--
--   local pass_target = 'PASS' .. current_id
--   local has_pass = content:find('_CMMNDS_' .. current_token .. ':' .. pass_target) ~= nil
--   local has_done = content:find('_CMMNDS_' .. current_token .. ':DONE') ~= nil
--   local has_fail = content:find('_CMMNDS_' .. current_token .. ':FAIL') ~= nil
--
--   if has_pass or has_fail or has_done then
--     local active_cb = callBack
--     local final_status = has_fail and 'FAIL' or (has_done and 'DONE' or pass_target)
--
--     if has_fail or has_done then
--       callBack = nil
--       M.queue = {}
--
--       if clangd_check_active then
--         clangd_extracted_args = {}
--
--         local end_pattern = '_CMMNDS_' .. current_token .. ':' .. final_status
--         local end_idx = content:find(end_pattern, 1, true)
--
--         local start_idx = nil
--         if end_idx then
--           local start_pattern = '_CMMNDS_' .. current_token .. '":"' .. final_status
--           local fallback_echo = '_CMMNDS_' .. current_token .. '":"DONE'
--           local search_zone = content:sub(1, end_idx - 1)
--
--           local current_pos = 1
--           while true do
--             local next_start, next_end = search_zone:find(start_pattern, current_pos, true)
--             if not next_start then
--               if not start_idx then
--                 local fb_start, fb_end = search_zone:find(fallback_echo, current_pos, true)
--                 if fb_start then start_idx = fb_end end
--               end
--               break
--             end
--             start_idx = next_end
--             current_pos = next_start + 1
--           end
--         end
--
--         if start_idx and end_idx and end_idx > start_idx then
--           local fresh_run_logs = string.sub(content, start_idx + 1, end_idx - 1)
--
--           if not string.find(fresh_run_logs, '%.clang%-format') then
--             local seen = {}
--             for arg in string.gmatch(fresh_run_logs, "unknown argument[:%s]+'([^']+)'") do
--               local clean_flag = string.format('"%s"', arg:gsub('[;%.]$', ''))
--               if not seen[clean_flag] then
--                 seen[clean_flag] = true
--                 table.insert(clangd_extracted_args, clean_flag)
--               end
--             end
--           end
--         else
--           pio_buffer = ""
--           content = ""
--           return
--         end
--
--         clangd_check_active = false
--       end
--
--       pio_buffer = ''
--       content = ''
--     end
--
--     if final_status and active_cb then
--       vim.schedule(function()
--         active_cb(final_status)
--       end)
--     end
--
--     return
--   end
-- end

return M
-- INFO: Your unmodified parser logic block remains safely out here
