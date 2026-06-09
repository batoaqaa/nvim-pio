local M = {}

-- 1. Default Public User Configuration Matrix
M.config = {
  panel_height = 0.25,
  winbar_bg = '#80a3d4',
  winbar_fg = '#000000',
  shell = OS.is_win and {
    'pwsh.exe',
    '-NoExit',
    '-NoLogo',
    '-NoProfile',
    '-ExecutionPolicy',
    'Bypass',
    -- '-Command',
    -- '[Console]::InputEncoding=[Console]::OutputEncoding=[System.Text.Encoding]::UTF8;',
  } or (function()
    local default_shell = vim.api.nvim_get_option_value('shell', {})
    -- If the Mac user defaults to zsh, pass the -f flag to bypass profile script leaks
    if default_shell:find('zsh') then
      return { default_shell, '-f' }
    end
    return default_shell
  end)(),
  -- shell = (vim.fn.has("win32") == 1) and "pwsh.exe" or vim.api.nvim_get_option_value("shell", {}),
}

M.stdout_callback = nil
M.exit_callback = nil

-- The Immutable Global State Registry Core Matrix
local state = {
  cli = { buf = nil, win = nil, job_id = nil, title = ' Pio CLI> ' },
  monitor = { buf = nil, win = nil, job_id = nil, title = ' Pio Monitor ' },
}

----------------------------------------------------------------------------------------
-- 🌟 HIGH-PERFORMANCE PERSISTENT TERMINAL CLASS (PROTOTYPE ARCHITECTURE)
----------------------------------------------------------------------------------------
---@class Terminal
---@field type string The type of terminal instance ('cli' or 'monitor')
---@field newline string Pre-cached row delimiter row ends
local Terminal = {}
Terminal.__index = Terminal

---Constructor: Instantiates the single immutable reference fields
---@param term_type string The target engine lane selection ('cli' or 'monitor')
---@return Terminal
function Terminal.new(term_type)
  local self = setmetatable({}, Terminal)
  self.type = term_type
  self.newline = OS.eol
  return self
end

---Rigid Method 1: Send a string command. Automatically handles lazy window generation!
---@param command string The instruction text payload line to pipe down the channel
function Terminal:send(command)
  local s = state[self.type]
  local cmd_str = tostring(command or '')

  -- LAZY AUTO-SPAWN GUARD: If the window or process died behind the scenes,
  -- calling :send() will automatically rebuild and open the panel first! [INDEX]
  if not s.job_id or s.job_id <= 0 or not s.win or not vim.api.nvim_win_is_valid(s.win) then
    M.PioTerminal('', self.type)
  end

  if not s.job_id or s.job_id <= 0 then
    return
  end
  if cmd_str ~= '' then
    vim.fn.chansend(s.job_id, self.newline)
  end
  vim.fn.chansend(s.job_id, cmd_str .. self.newline)
end

---Rigid Method 2: Gracefully stop background job and tear down split windows safely
function Terminal:close()
  local s = state[self.type]
  if not s or not s.job_id or s.job_id <= 0 then
    return
  end
  pcall(vim.fn.jobstop, s.job_id)

  if s.win and vim.api.nvim_win_is_valid(s.win) then
    vim.api.nvim_win_close(s.win, true)
  end
  s.win = nil
  s.buf = nil
  s.job_id = nil

  vim.schedule(function()
    vim.cmd('wincmd =')
    M.UpdateWinbarTitles()
  end)
end

---Rigid Method 3: Pure Hide Pass - Closes the split window layout viewport panel cleanly
function Terminal:hide()
  local s = state[self.type]
  if s and s.win and vim.api.nvim_win_is_valid(s.win) then
    vim.api.nvim_win_close(s.win, true)
  end
  if s then
    s.win = nil
  end
  vim.schedule(function()
    vim.cmd('wincmd =')
    M.UpdateWinbarTitles()
  end)
end

---Rigid Method 4: Pure Show Pass - Re-splits open the bottom panel row layout instantly
---@return boolean # True if the split window canvas layout was drawn successfully
function Terminal:show()
  local s = state[self.type]
  -- If buffer is lost or completely uninitialized, trigger a fresh procedural generation loop pass
  if not s.buf or not vim.api.nvim_buf_is_valid(s.buf) then
    M.PioTerminal('', self.type)
    return true
  end

  if s.win and vim.api.nvim_win_is_valid(s.win) then
    vim.api.nvim_set_current_win(s.win)
    return true
  end

  local target_h = math.ceil(vim.o.lines * M.config.panel_height)
  local win_opts = { split = 'below', win = -1, height = target_h }
  s.win = vim.api.nvim_open_win(s.buf, true, win_opts)

  vim.cmd('setlocal nonumber norelativenumber signcolumn=no')
  vim.api.nvim_set_option_value('winfixheight', true, { scope = 'local', win = s.win })

  M.UpdateWinbarTitles()
  vim.cmd('startinsert')
  return true
end

---Rigid Method 5: Clear console screen prompt clean natively across platforms
function Terminal:clear()
  local clear_cmd = OS.is_win and 'Clear-Host' or 'clear'
  self:send(clear_cmd)
end

---Rigid Method 6: Fetch raw underlying buffer handle pointer index
---@return number|nil
function Terminal:get_buf()
  return state[self.type].buf
end

---Rigid Method 7: Fetch raw underlying window split handle pointer index
---@return number|nil
function Terminal:get_win()
  return state[self.type].win
end

-- 🌟 ZERO OVERHEAD STATIC INSTANCE INJECTIONS:
-- Pre-instantiate the objects on boot. They are permanently available on the module table. [INDEX]
---@type Terminal
M.cli = Terminal.new('cli')
---@type Terminal
M.monitor = Terminal.new('monitor')
----------------------------------------------------------------------------------------

local function IsTerminalWindowOpen(term_type)
  local s = state[term_type]
  return s.win and vim.api.nvim_win_is_valid(s.win) and vim.api.nvim_win_get_buf(s.win) == s.buf
end

function M.UpdateWinbarTitles()
  local cli_alive = state.cli.buf and vim.api.nvim_buf_is_valid(state.cli.buf)
  local mon_alive = state.monitor.buf and vim.api.nvim_buf_is_valid(state.monitor.buf)
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
    M.UpdateWinbarTitles()
  end)
end

function M.IsTerminalOpen(term_type)
  return IsTerminalWindowOpen(term_type)
end

---Core window layout allocator and partition spawner namespace
---@param command string Initial command payload text instruction to pipe down channel
---@param terminal_type string Layout selection mode profile target ('cli' or 'monitor')
function M.PioTerminal(command, terminal_type)
  local cmd_str = tostring(command or '')
  if terminal_type ~= 'monitor' and terminal_type ~= 'cli' then
    terminal_type = cmd_str:find('monitor') and 'monitor' or 'cli'
  end

  local opposite_type = (terminal_type == 'monitor') and 'cli' or 'monitor'

  if IsTerminalWindowOpen(opposite_type) then
    SafeCloseTerminal(opposite_type)
  end

  -- Step 3: Always Open Target View Recycle Pass
  if IsTerminalWindowOpen(terminal_type) then
    local current = state[terminal_type]
    vim.api.nvim_set_current_win(current.win)

    local target_h = math.ceil(vim.o.lines * M.config.panel_height)
    pcall(vim.api.nvim_win_set_height, current.win, target_h)

    if command and command ~= '' then
      if current.job_id and current.job_id > 0 then
        vim.fn.chansend(current.job_id, command .. OS.eol)
      end
    end
    return
  end

  -- Step 4: Scratch Buffer Allocation Provision Pass
  local current = state[terminal_type]
  local is_new_buffer = false
  if not current.buf or not vim.api.nvim_buf_is_valid(current.buf) then
    current.buf = vim.api.nvim_create_buf(false, true)
    is_new_buffer = true
  end

  -- Step 5: Screen Split Window Layout Spawner
  local target_h = math.ceil(vim.o.lines * M.config.panel_height)
  local win_opts = { split = 'below', win = -1, height = target_h }
  current.win = vim.api.nvim_open_win(current.buf, true, win_opts)

  if is_new_buffer then
    local spawned_job_id = vim.fn.jobstart(M.config.shell, {
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
    current.job_id = spawned_job_id

    if OS.is_win then
      local init_enc = '[Console]::InputEncoding=[Console]::OutputEncoding=[System.Text.Encoding]::UTF8; Clear-Host;\r\n'
      vim.fn.chansend(spawned_job_id, init_enc)
    end

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

  vim.cmd('setlocal nonumber norelativenumber signcolumn=no')
  vim.api.nvim_set_option_value('winfixheight', true, { scope = 'local', win = current.win })

  local pio_group = vim.api.nvim_create_augroup('PioFocusGuard_' .. current.buf, { clear = true })
  vim.api.nvim_create_autocmd('WinEnter', {
    group = pio_group,
    buffer = current.buf,
    callback = function()
      vim.schedule(function()
        if IsTerminalWindowOpen(terminal_type) then
          pcall(vim.api.nvim_win_set_height, current.win, target_h)
          if vim.api.nvim_get_mode().mode:sub(1, 1) ~= 't' then
            vim.cmd('normal! G')
          end
        end
      end)
    end,
  })

  M.UpdateWinbarTitles()

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
      M.PioTerminal('', opposite_type)
    end)
  end, { buffer = current.buf, silent = true })

  vim.keymap.set('n', '<C-h>', '<C-w>h')
  vim.keymap.set('n', '<C-l>', '<C-w>l')
  vim.keymap.set('n', '<C-j>', function()
    vim.schedule(function()
      if IsTerminalWindowOpen(terminal_type) then
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
    if current.job_id then
      vim.fn.chansend(current.job_id, command .. OS.newline)
    end
  end
end

vim.keymap.set('n', [[<leader>\gm]], function()
  M.PioTerminal('pio device monitor', 'monitor')
end, { silent = true })
vim.keymap.set('n', [[<leader>\t]], function()
  M.PioTerminal('', 'cli')
end, { silent = true })

-- function M.stdout_callback(job_id, data, event)
--   if not data or #data == 0 or not current_token or current_token == "" then return end
--   local processed_lines = {}
--   for i, line in ipairs(data) do processed_lines[i] = line:gsub("\r", ""):gsub("\x1b%[[0-9;]*%a", "") end
--   local chunk_count = #processed_lines
--
--   if chunk_count > 1 then
--     M.content = M.content .. M.pio_buffer .. table.concat(processed_lines, '', 1, chunk_count)
--     M.pio_buffer = processed_lines[chunk_count]
--   else
--     M.content = M.content .. M.pio_buffer .. processed_lines
--     M.pio_buffer = processed_lines
--   end
--
--   local pass_target = 'PASS' .. current_id
--   -- FIXED: Restored underscores to ensure matching against compiler token outputs
--   local has_pass = M.content:find('_CMMNDS_' .. current_token .. ':' .. pass_target) ~= nil
--   local has_done = M.content:find('_CMMNDS_' .. current_token .. ':DONE') ~= nil
--   local has_fail = M.content:find('_CMMNDS_' .. current_token .. ':FAIL') ~= nil
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
--         local end_pattern = '_CMMNDS_' .. current_token .. ':' .. final_status
--         local end_idx = M.content:find(end_pattern, 1, true)
--         local start_idx = nil
--
--         if end_idx then
--           local start_pattern = '_CMMNDS_' .. current_token .. '":"' .. final_status
--           local fallback_echo = '_CMMNDS_' .. current_token .. '":"DONE'
--           local search_zone = M.content:sub(1, end_idx - 1)
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
--           local fresh_run_logs = string.sub(M.content, start_idx + 1, end_idx - 1)
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
--           M.pio_buffer = ""
--           M.content = ""
--           return
--         end
--         clangd_check_active = false
--       end
--       M.pio_buffer = ''
--       M.content = ''
--     end
--
--     if final_status and active_cb then vim.schedule(function() active_cb(final_status) end) end
--     return
--   end
-- end

function M.setup(opts)
  M.config = vim.tbl_deep_extend('force', M.config, opts or {})
end

return M
