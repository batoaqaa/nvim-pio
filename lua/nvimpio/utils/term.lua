local M = {}

local current_token -- = tostring(math.random(10000, 99999))
local session_counter = 1 -- Our high-performance integer counter
local current_id = -1

local callBack = nil
M.queue = {}

local clangd_extracted_args = {}
local clangd_check_active = false

local fromMsg = ''
-- Clean State Management Architecture
M.config = {
  panel_height = 0.28,
  winbar_bg = '#80a3d4',
  winbar_fg = '#000000',
}

M.stdout_callback = nil
M.exit_callback = nil

-- Clean Core State Storage Architecture
local state = {
  cli = { buf = nil, win = nil, title = ' Pio CLI> ' },
  monitor = { buf = nil, win = nil, title = ' Pio Monitor ' },
}

local pio_buffer = ''
local content = ''

-- Safe runtime check to see if a terminal window viewport is open on your grid right now
local function IsTerminalWindowOpen(term_type)
  local s = state[term_type]
  return s.win and vim.api.nvim_win_is_valid(s.win) and vim.api.nvim_win_get_buf(s.win) == s.buf
end

-- 🌟 FIXED METRIC STATE TELEMETRY ENGINE:
local function UpdateWinbarTitles()
  -- Check if BOTH background terminal process buffers are valid inside Neovim's history memory stack
  local cli_alive = state.cli.buf and vim.api.nvim_buf_is_valid(state.cli.buf)
  local mon_alive = state.monitor.buf and vim.api.nvim_buf_is_valid(state.monitor.buf)

  -- If BOTH background processes exist in cache, display [;; Switch]
  -- If only ONE background process exists, display [; Hide]
  local hint = (cli_alive and mon_alive) and ' [;; Switch] ' or ' [; Hide] '

  vim.api.nvim_set_hl(0, 'PioWinBar', { bg = M.config.winbar_bg, fg = M.config.winbar_fg })

  for _, t in pairs({ 'cli', 'monitor' }) do
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
    vim.cmd('wincmd =')
    UpdateWinbarTitles()
  end)
end

-- Expose verification helpers safely to the public module namespaces
function M.IsTerminalOpen(term_type)
  return IsTerminalWindowOpen(term_type)
end
function M.ToggleTerminal(command, terminal_type)
  -- 1. Defend type inputs elegantly against null or type mutations
  local cmd_str = tostring(command or '')
  if terminal_type ~= 'monitor' and terminal_type ~= 'cli' then
    terminal_type = cmd_str:find('monitor') and 'monitor' or 'cli'
  end

  local opposite_type = (terminal_type == 'monitor') and 'cli' or 'monitor'

  -- 2. Mutual Exclusion Pass: If opposite viewport is visible, close it down cleanly
  if IsTerminalWindowOpen(opposite_type) then
    SafeCloseTerminal(opposite_type)
    vim.schedule(function()
      M.ToggleTerminal(command, terminal_type)
    end)
    return
  end

  if IsTerminalWindowOpen(terminal_type) then
    vim.api.nvim_set_current_win(state[terminal_type].win)
    local target_h = math.ceil(vim.o.lines * M.config.panel_height)
    pcall(vim.api.nvim_win_set_height, state[terminal_type].win, target_h)
    return
  end -- 3. Always Open Target View: Move focus straight into pre-existing viewports

  -- 4. Clean Buffer Allocation Provision Pass
  local current = state[terminal_type]
  local is_new_buffer = false
  if not current.buf or not vim.api.nvim_buf_is_valid(current.buf) then
    current.buf = vim.api.nvim_create_buf(false, true)
    is_new_buffer = true
  end

  -- 5. Open Bottom Screen Layout Partition Block
  local target_h = math.ceil(vim.o.lines * M.config.panel_height)
  local win_opts = { split = 'below', win = -1, height = target_h }

  -- [FIXED]: Saves the newly spawned window handle directly into the structured state tree matrix [INDEX]
  current.win = vim.api.nvim_open_win(current.buf, true, win_opts)

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
    vim.b[current.buf].terminal_job_id = spawned_job_id

    -- Auto Scroll Autocmd Loop Block
    local scroll_group = vim.api.nvim_create_augroup('PioAutoScroll_' .. current.buf, { clear = true })
    vim.api.nvim_create_autocmd({ 'TextChanged', 'TextChangedI' }, {
      group = scroll_group,
      buffer = current.buf,
      callback = function()
        local w = vim.fn.bufwinid(current.buf)
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

  -- 6. Local Sizing Configuration Adjusters Pass
  vim.cmd('setlocal nonumber norelativenumber signcolumn=no')
  vim.api.nvim_set_option_value('winfixheight', true, { scope = 'local', win = current.win })

  local pio_group = vim.api.nvim_create_augroup('PioFocusGuard_' .. current.buf, { clear = true })
  vim.api.nvim_create_autocmd('WinEnter', {
    group = pio_group,
    buffer = current.buf,
    callback = function()
      vim.schedule(function()
        if IsTerminalOpen(terminal_type) then
          pcall(vim.api.nvim_win_set_height, current.win, target_h)
          if vim.api.nvim_get_mode().mode:sub(1, 1) ~= 't' then
            vim.cmd('normal! G')
          end
        end
      end)
    end,
  })

  UpdateWinbarTitles()

  -- 7. Context Local Mapping Bundles Registration
  vim.keymap.set('t', '<Esc>', [[<C-\><C-n>]], { buffer = current.buf })
  vim.keymap.set('n', 'q', function()
    SafeCloseTerminal(terminal_type)
  end, { buffer = current.buf })

  vim.keymap.set({ 'n', 't' }, '<C-k>', function()
    if vim.api.nvim_get_mode().mode == 't' then
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes([[<C-\><C-n>]], true, true, true), 'n', false)
    end
    vim.schedule(function()
      vim.cmd('wincmd k')
    end)
  end, { buffer = current.buf, silent = true })

  -- Pure Decoupled Switcher Mapping implementation
  vim.keymap.set({ 'n', 't' }, ';;', function()
    if vim.api.nvim_get_mode().mode == 't' then
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes([[<C-\><C-n>]], true, true, true), 'n', false)
    end

    local current_winbar = vim.api.nvim_get_option_value('winbar', { scope = 'local' }) or ''
    if current_winbar:find('%[; Hide%]') then
      SafeCloseTerminal(terminal_type)
      return
    end

    SafeCloseTerminal(terminal_type)
    vim.schedule(function()
      M.ToggleTerminal('', opposite_type)
    end)
  end, { buffer = current.buf, silent = true })

  vim.keymap.set('n', '<C-h>', '<C-w>h')
  vim.keymap.set('n', '<C-l>', '<C-w>l')
  vim.keymap.set('n', '<C-j>', function()
    vim.schedule(function()
      if IsTerminalOpen(terminal_type) then
        vim.api.nvim_set_current_win(current.win)
        pcall(vim.api.nvim_win_set_height, current.win, target_h)
        if vim.api.nvim_get_mode().mode:sub(1, 1) ~= 't' then
          vim.cmd('normal! G')
        end
      else
        vim.cmd('wincmd j')
      end
    end)
  end, { silent = true })

  if command and command ~= '' then
    local job_id = vim.b[current.buf].terminal_job_id
    if job_id then
      vim.fn.chansend(job_id, command .. (vim.fn.has('win32') == 1 and '\r\n' or '\n'))
    end
  end
end

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

-- Public plugin init framework config function
function M.setup(opts)
  M.config = vim.tbl_deep_extend('force', M.config, opts or {})
end

return M
