local M = {}

-- Platform capability detection table
local OS_CAPABILITIES = {
  is_windows_system = vim.fn.has('win32') == 1,
  line_ending_character = vim.fn.has('win32') == 1 and '\r\n' or '\n',
}

-- 1. Default Public User Configuration Matrix
-- -- Inherit global parameters from main plugin table
-- M.config = require('nvimpio').config
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
    '-Command',
    '[Console]::InputEncoding=[Console]::OutputEncoding=[System.Text.Encoding]::UTF8;',
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

local terminal_state_registry = {
  cli = { buffer_id = nil, window_id = nil, job_id = nil, panel_title = ' Pio CLI> ' },
  monitor = { buffer_id = nil, window_id = nil, job_id = nil, panel_title = ' Pio Monitor ' },
}

----------------------------------------------------------------------------------------
-- 🌟 TERMINAL CORE PROTOTYPE CLASS DECLARATIONS
----------------------------------------------------------------------------------------
---@class Terminal
---@field terminal_type string Layout track destination ('cli' or 'monitor')
---@field newline_delimiter string System text ending carriage return
local Terminal = {}
Terminal.__index = Terminal

function Terminal.new(target_lane)
  local self = setmetatable({}, Terminal)
  self.terminal_type = target_lane
  self.newline_delimiter = OS_CAPABILITIES.line_ending_character
  return self
end

function Terminal:send(command_payload)
  local target_state = terminal_state_registry[self.terminal_type]
  local command_string = tostring(command_payload or '')

  if not target_state.job_id or target_state.job_id <= 0 or not target_state.window_id or not vim.api.nvim_win_is_valid(target_state.window_id) then
    M.PioTerminal('', self.terminal_type)
  end

  if not target_state.job_id or target_state.job_id <= 0 then
    return
  end
  if command_string ~= '' then
    vim.fn.chansend(target_state.job_id, self.newline_delimiter)
  end
  vim.fn.chansend(target_state.job_id, command_string .. self.newline_delimiter)
end

function Terminal:close()
  local target_state = terminal_state_registry[self.terminal_type]
  if not target_state or not target_state.job_id or target_state.job_id <= 0 then
    return
  end
  pcall(vim.fn.jobstop, target_state.job_id)

  if target_state.window_id and vim.api.nvim_win_is_valid(target_state.window_id) then
    vim.api.nvim_win_close(target_state.window_id, true)
  end
  target_state.window_id = nil
  target_state.buffer_id = nil
  target_state.job_id = nil

  vim.schedule(function()
    vim.cmd('wincmd =')
    M.UpdateWinbarTitles()
  end)
end

function Terminal:hide()
  local target_state = terminal_state_registry[self.terminal_type]
  if target_state and target_state.window_id and vim.api.nvim_win_is_valid(target_state.window_id) then
    vim.api.nvim_win_close(target_state.window_id, true)
  end
  if target_state then
    target_state.window_id = nil
  end
  vim.schedule(function()
    vim.cmd('wincmd =')
    M.UpdateWinbarTitles()
  end)
end

function Terminal:show()
  local target_state = terminal_state_registry[self.terminal_type]
  if not target_state.buffer_id or not vim.api.nvim_buf_is_valid(target_state.buffer_id) then
    M.PioTerminal('', self.terminal_type)
    return true
  end

  if target_state.window_id and vim.api.nvim_win_is_valid(target_state.window_id) then
    vim.api.nvim_set_current_win(target_state.window_id)
    return true
  end

  local calculated_panel_height = math.ceil(vim.o.lines * M.config.panel_height)
  local window_spawn_options = { split = 'below', win = -1, height = calculated_panel_height }
  target_state.window_id = vim.api.nvim_open_win(target_state.buffer_id, true, window_spawn_options)

  vim.cmd('setlocal nonumber norelativenumber signcolumn=no')
  vim.api.nvim_set_option_value('winfixheight', true, { scope = 'local', win = target_state.window_id })

  M.UpdateWinbarTitles()
  vim.cmd('startinsert')
  return true
end

function Terminal:clear()
  local system_clear_command = OS_CAPABILITIES.is_windows and 'Clear-Host' or 'clear'
  self:send(system_clear_command)
end

function Terminal:get_buf()
  return terminal_state_registry[self.terminal_type].buffer_id
end
function Terminal:get_win()
  return terminal_state_registry[self.terminal_type].window_id
end

local function IsTerminalWindowOpen(term_type)
  local target_state = terminal_state_registry[term_type]
  return target_state.window_id
    and vim.api.nvim_win_is_valid(target_state.window_id)
    and vim.api.nvim_win_get_buf(target_state.window_id) == target_state.buffer_id
end

function M.UpdateWinbarTitles()
  local is_cli_buffer_valid = terminal_state_registry.cli.buffer_id and vim.api.nvim_buf_is_valid(terminal_state_registry.cli.buffer_id)
  local is_monitor_buffer_valid = terminal_state_registry.monitor.buffer_id and vim.api.nvim_buf_is_valid(terminal_state_registry.monitor.buffer_id)
  local status_hint_string = (is_cli_buffer_valid and is_monitor_buffer_valid) and ' [;; Switch] ' or ' [; Hide] '

  vim.api.nvim_set_hl(0, 'PioWinBar', { bg = M.config.winbar_bg, fg = M.config.winbar_fg })

  for _, current_lane_type in pairs({ 'cli', 'monitor' }) do
    local current_state = terminal_state_registry[current_lane_type]
    if current_state.window_id and vim.api.nvim_win_is_valid(current_state.window_id) then
      vim.api.nvim_set_option_value(
        'winbar',
        '%#PioWinBar#' .. current_state.panel_title .. status_hint_string .. '%*',
        { scope = 'local', win = current_state.window_id }
      )
    end
  end
end

local function SafeCloseTerminal(term_type)
  local target_state = terminal_state_registry[term_type]
  if not target_state then
    return
  end
  if target_state.window_id and vim.api.nvim_win_is_valid(target_state.window_id) then
    vim.api.nvim_win_close(target_state.window_id, true)
  end
  target_state.window_id = nil
  vim.schedule(function()
    vim.cmd('wincmd =')
    M.UpdateWinbarTitles()
  end)
end

function M.IsTerminalOpen(term_type)
  return IsTerminalWindowOpen(term_type)
end

function M.PioTerminal(command, terminal_type)
  local command_fallback_string = tostring(command or '')
  if terminal_type ~= 'monitor' and terminal_type ~= 'cli' then
    terminal_type = command_fallback_string:find('monitor') and 'monitor' or 'cli'
  end

  local opposite_lane_type = (terminal_type == 'monitor') and 'cli' or 'monitor'

  if IsTerminalWindowOpen(opposite_lane_type) then
    SafeCloseTerminal(opposite_lane_type)
  end

  if IsTerminalWindowOpen(terminal_type) then
    local active_state = terminal_state_registry[terminal_type]
    vim.api.nvim_set_current_win(active_state.window_id)

    local calculated_panel_height = math.ceil(vim.o.lines * M.config.panel_height)
    pcall(vim.api.nvim_win_set_height, active_state.window_id, calculated_panel_height)

    if command and command ~= '' then
      if active_state.job_id and active_state.job_id > 0 then
        vim.fn.chansend(active_state.job_id, command .. OS_CAPABILITIES.line_ending_character)
      end
    end
    return
  end

  local active_state = terminal_state_registry[terminal_type]
  local is_new_buffer_allocated = false
  if not active_state.buffer_id or not vim.api.nvim_buf_is_valid(active_state.buffer_id) then
    active_state.buffer_id = vim.api.nvim_create_buf(false, true)
    is_new_buffer_allocated = true
  end

  local calculated_panel_height = math.ceil(vim.o.lines * M.config.panel_height)
  local window_spawn_options = { split = 'below', win = -1, height = calculated_panel_height }
  active_state.window_id = vim.api.nvim_open_win(active_state.buffer_id, true, window_spawn_options)

  if is_new_buffer_allocated then
    local active_channel_id = vim.fn.jobstart(M.config.shell, {
      term = true,
      on_stdout = function(_, standard_output_data, _)
        if terminal_type == 'cli' and type(M.stdout_callback) == 'function' then
          M.stdout_callback(nil, standard_output_data, nil)
        end
      end,
      on_stderr = function(_, standard_error_data, _)
        if terminal_type == 'cli' and type(M.stdout_callback) == 'function' then
          M.stdout_callback(nil, standard_error_data, nil)
        end
      end,
      on_exit = function()
        if type(M.exit_callback) == 'function' then
          M.exit_callback()
        end
      end,
    })
    vim.b[active_state.buffer_id].terminal_job_id = active_channel_id
    active_state.job_id = active_channel_id

    if OS_CAPABILITIES.is_windows then
      local encoding_initialization_string = '[Console]::InputEncoding=[Console]::OutputEncoding=[System.Text.Encoding]::UTF8; Clear-Host;'
      vim.fn.chansend(active_channel_id, encoding_initialization_string .. OS_CAPABILITIES.line_ending_character)
    end

    local autoscroll_event_group = vim.api.nvim_create_augroup('PioAutoScroll_' .. active_state.buffer_id, { clear = true })
    vim.api.nvim_create_autocmd({ 'TextChanged', 'TextChangedI' }, {
      group = autoscroll_event_group,
      buffer = active_state.buffer_id,
      callback = function()
        local active_window_handle = vim.fn.bufwinid(active_state.buffer_id)
        if active_window_handle and active_window_handle ~= -1 and vim.api.nvim_win_is_valid(active_window_handle) then
          vim.schedule(function()
            if vim.api.nvim_win_is_valid(active_window_handle) then
              vim.api.nvim_win_call(active_window_handle, function()
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
  vim.api.nvim_set_option_value('winfixheight', true, { scope = 'local', win = active_state.window_id })

  local focus_guard_event_group = vim.api.nvim_create_augroup('PioFocusGuard_' .. active_state.buffer_id, { clear = true })
  vim.api.nvim_create_autocmd('WinEnter', {
    group = focus_guard_event_group,
    buffer = active_state.buffer_id,
    callback = function()
      vim.schedule(function()
        if IsTerminalWindowOpen(terminal_type) then
          pcall(vim.api.nvim_win_set_height, active_state.window_id, calculated_panel_height)
          if vim.api.nvim_get_mode().mode:sub(1, 1) ~= 't' then
            vim.cmd('normal! G')
          end
        end
      end)
    end,
  })

  M.UpdateWinbarTitles()

  vim.keymap.set('t', '<Esc>', [[<C-\><C-n>]], { buffer = active_state.buffer_id })
  vim.keymap.set('n', 'q', function()
    SafeCloseTerminal(terminal_type)
  end, { buffer = active_state.buffer_id })

  vim.keymap.set({ 'n', 't' }, '<C-k>', function()
    if vim.api.nvim_get_mode().mode == 't' then
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes([[<C-\><C-n>]], true, true, true), 'n', false)
    end
    vim.schedule(function()
      vim.cmd('wincmd k')
    end)
  end, { buffer = active_state.buffer_id, silent = true })

  vim.keymap.set({ 'n', 't' }, ';;', function()
    if vim.api.nvim_get_mode().mode == 't' then
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes([[<C-\><C-n>]], true, true, true), 'n', false)
    end
    local current_winbar_option = vim.api.nvim_get_option_value('winbar', { scope = 'local' }) or ''
    if current_winbar_option:find('%[; Hide%]') then
      SafeCloseTerminal(terminal_type)
      return
    end
    SafeCloseTerminal(terminal_type)
    vim.schedule(function()
      M[opposite_lane_type]:show()
    end)
  end, { buffer = active_state.buffer_id, silent = true })

  vim.keymap.set('n', '<C-h>', '<C-w>h')
  vim.keymap.set('n', '<C-l>', '<C-w>l')
  vim.keymap.set('n', '<C-j>', function()
    vim.schedule(function()
      if IsTerminalWindowOpen(terminal_type) then
        vim.api.nvim_set_current_win(active_state.window_id)
        pcall(vim.api.nvim_win_set_height, active_state.window_id, calculated_panel_height)
        if vim.api.nvim_get_mode().mode:sub(1, 1) ~= 't' then
          vim.cmd('normal! G')
        end
      else
        vim.cmd('wincmd j')
      end
    end)
  end, { silent = true })

  if command and command ~= '' then
    if active_state.job_id then
      vim.fn.chansend(active_state.job_id, command .. OS_CAPABILITIES.line_ending_character)
    end
  end
end

M.cli = Terminal.new('cli')
M.monitor = Terminal.new('monitor')

vim.keymap.set('n', [[<leader>\gm]], function()
  M.monitor:show()
  M.monitor:send('pio device monitor')
end, { silent = true })
vim.keymap.set('n', [[<leader>\t]], function()
  M.cli:show()
end, { silent = true })

-- function M.stdout_callback(_, raw_incoming_data, _)
--   if not raw_incoming_data or #raw_incoming_data == 0 then
--     return
--   end
--
--   if #raw_incoming_data > 1 then
--     content = content .. pio_buffer .. table.concat(raw_incoming_data, '', 1, #raw_incoming_data)
--     pio_buffer = raw_incoming_data[#raw_incoming_data]
--   else
--     content = content .. pio_buffer .. raw_incoming_data
--     pio_buffer = raw_incoming_data
--   end
--
--   local execution_pass_target = 'PASS' .. current_id
--   local is_build_passed = content:find('_CMMNDS_' .. current_token .. ':' .. execution_pass_target) ~= nil
--   local is_build_done = content:find('_CMMNDS_' .. current_token .. ':DONE') ~= nil
--   local is_build_failed = content:find('_CMMNDS_' .. current_token .. ':FAIL') ~= nil
--
--   if is_build_passed or is_build_failed or is_build_done then
--     local cached_active_callback = callBack
--     local final_execution_status = is_build_failed and 'FAIL' or (is_build_done and 'DONE' or execution_pass_target)
--
--     if is_build_failed or is_build_done then
--       callBack = nil
--       M.queue = {}
--
--       if clangd_check_active then
--         clangd_extracted_args = {}
--
--         local compilation_start_pattern = '_CMMNDS_' .. current_token .. '":"' .. final_execution_status
--         local _, extraction_start_index = string.find(content, compilation_start_pattern, 1, true)
--
--         if not extraction_start_index then
--           local compilation_fallback_pattern = '_CMMNDS_' .. current_token .. '":"DONE'
--           _, extraction_start_index = string.find(content, compilation_fallback_pattern, 1, true)
--         end
--
--         local compilation_end_pattern = '_CMMNDS_' .. current_token .. ':' .. final_execution_status
--         local extraction_end_index = string.find(content, compilation_end_pattern, 1, true)
--
--         if extraction_start_index and extraction_end_index and extraction_end_index > extraction_start_index then
--           local isolated_fresh_run_logs = string.sub(content, extraction_start_index + 1, extraction_end_index - 1)
--
--           if not string.find(isolated_fresh_run_logs, '%.clang%-format') then
--             local unique_seen_arguments = {}
--             for single_flag_argument in string.gmatch(isolated_fresh_run_logs, "unknown argument[:%s]+'([^']+)'") do
--               local sanitized_clean_flag = string.format('"%s"', single_flag_argument:gsub('[;%.]$', ''))
--               if not unique_seen_arguments[sanitized_clean_flag] then
--                 unique_seen_arguments[sanitized_clean_flag] = true
--                 table.insert(clangd_extracted_args, sanitized_clean_flag)
--               end
--             end
--           end
--         else
--           return
--         end
--         clangd_check_active = false
--       end
--
--       pio_buffer = ''
--       content = ''
--     end
--
--     if final_execution_status and cached_active_callback then
--       vim.schedule(function()
--         cached_active_callback(final_execution_status)
--       end)
--     end
--
--     return
--   end
-- end

function M.setup(user_configuration_options)
  M.config = vim.tbl_deep_extend('force', M.config, user_configuration_options or {})
end

return M
