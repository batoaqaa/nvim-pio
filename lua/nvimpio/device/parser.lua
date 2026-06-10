local M = {}

local boilerplate = require('nvimpio.boilerplate')
local boilerplate_gen = boilerplate.boilerplate_gen

-- -- =============================================================================
local current_token -- = tostring(math.random(10000, 99999))
local session_counter = 1 -- Our high-performance integer counter
local current_id = -1

local callBack = nil
M.queue = {}

local clangd_extracted_args = {}
local clangd_check_active = false

local fromMsg = ''
local trm
local pio_buffer = ''
local content = ''

-- require('nvimpio.device.terminal').stdout_callback = M.stdoutcallback
-- stylua: ignore
function M.stdoutcallback(_, raw_incoming_data, _)
-- function M.stdoutcallback(job_id, raw_incoming_data, event)
  _G.PioTraceLog = _G.PioTraceLog or {}
  
  if raw_incoming_data and #raw_incoming_data > 0 then
    for index, raw_text_row in ipairs(raw_incoming_data) do
      if raw_text_row ~= "" then
        -- Strips hidden ANSI control sequences to leave the characters pristine
        local sanitized_row = tostring(raw_text_row):gsub("\x1b%[[0-9;]*%a", "")
        table.insert(_G.PioTraceLog, string.format("[PACKET SLOT %d] %q", index, sanitized_row))
      end
    end
  end
  if not raw_incoming_data or #raw_incoming_data == 0 then return end
  -- if current_token then
  -----------------------------------------------------------------------------
  -- 🔍 DETECTIVE TRACE HOOKS: Run this snippet to verify active process triggers
  -----------------------------------------------------------------------------
  -- Trace Call #1: Logs the unique event name ("stdout") and incoming table length
  -- vim.notify(string.format('[PioTrace] Callback hit! Event: %s, Chunks received: %d', tostring(event), data and #data or 0), vim.log.levels.INFO)

  -- Trace Call #2: Dumps the raw log string block content to verify stream integrity
  -- if data and #data > 0 then
  --   vim.notify('[PioData Dump]: ' .. table.concat(data, ' | '), vim.log.levels.DEBUG)
  -- end
  -----------------------------------------------------------------------------

  if #raw_incoming_data > 1 then
    content = content .. pio_buffer .. table.concat(raw_incoming_data, '', 1, #raw_incoming_data)
    pio_buffer = raw_incoming_data[#raw_incoming_data]
  else
    content = content .. pio_buffer .. raw_incoming_data[1]
    pio_buffer = raw_incoming_data[1]
  end

  local execution_pass_target = 'PASS' .. current_id
  local is_build_passed = content:find('_CMMNDS_' .. current_token .. ':' .. execution_pass_target) ~= nil
  local is_build_done = content:find('_CMMNDS_' .. current_token .. ':DONE') ~= nil
  local is_build_failed = content:find('_CMMNDS_' .. current_token .. ':FAIL') ~= nil

  if is_build_passed or is_build_failed or is_build_done then
    local cached_active_callback = callBack
    local final_execution_status = is_build_failed and 'FAIL' or (is_build_done and 'DONE' or execution_pass_target)

    if is_build_failed or is_build_done then
      callBack = nil
      M.queue = {}

      -----------------------------------------------------------------------
      -- ONE-TIME ARGUMENT EXTRACTOR FROM BUILD TEXT LOGS
      -----------------------------------------------------------------------
      if clangd_check_active then
        clangd_extracted_args = {}

        -- 1. Find boundaries on the raw, un-truncated content string
         local compilation_start_pattern = '_CMMNDS_' .. current_token .. '":"' .. final_execution_status
        local _, extraction_start_index = string.find(content, compilation_start_pattern, 1, true)

        if not extraction_start_index then
          local compilation_fallback_pattern = '_CMMNDS_' .. current_token .. '":"DONE'
          _, extraction_start_index = string.find(content, compilation_fallback_pattern, 1, true)
        end

        local compilation_end_pattern = '_CMMNDS_' .. current_token .. ':' .. final_execution_status
        local extraction_end_index = string.find(content, compilation_end_pattern, 1, true)

        -- 2. Slice and parse the exact fresh run text block
         if extraction_start_index and extraction_end_index and extraction_end_index > extraction_start_index then
          local isolated_fresh_run_logs = string.sub(content, extraction_start_index + 1, extraction_end_index - 1)

          if not string.find(isolated_fresh_run_logs, '%.clang%-format') then
            local unique_seen_arguments = {}
            for single_flag_argument in string.gmatch(isolated_fresh_run_logs, "unknown argument[:%s]+'([^']+)'") do
              local sanitized_clean_flag = string.format('"%s"', single_flag_argument:gsub('[;%.]$', ''))
              if not unique_seen_arguments[sanitized_clean_flag] then
                unique_seen_arguments[sanitized_clean_flag] = true
                table.insert(clangd_extracted_args, sanitized_clean_flag)
              end
            end
          end
        else
          return
        end
        clangd_check_active = false
      end
      -----------------------------------------------------------------------

      -- 🏁 3. FLUSH THE BUFFER CLEAN HERE AT THE END OF THE COMMAND RUN
       pio_buffer = ''
      content = ''
    end

    if final_execution_status and cached_active_callback then
      vim.schedule(function() cached_active_callback(final_execution_status) end)
    end
    -- end
    return
  end
end
-- function M.stdoutcallback(_ , data, _)
-- -- function M.stdoutcallback(job_id , data, event)
--
--   if not data or #data == 0 then return end
--   -----------------------------------------------------------------------------
--   -- 🔍 DETECTIVE TRACE HOOKS: Run this snippet to verify active process triggers
--   -----------------------------------------------------------------------------
--   -- Trace Call #1: Logs the unique event name ("stdout") and incoming table length
--   -- vim.notify(string.format('[PioTrace] Callback hit! Event: %s, Chunks received: %d', tostring(event), data and #data or 0), vim.log.levels.INFO)
--
--   -- Trace Call #2: Dumps the raw log string block content to verify stream integrity
--   -- if data and #data > 0 then
--   --   vim.notify('[PioData Dump]: ' .. table.concat(data, ' | '), vim.log.levels.DEBUG)
--   -- end
--   -----------------------------------------------------------------------------
--
--   if #data > 1 then
--     content = content .. pio_buffer .. table.concat(data, '', 1, #data)
--     pio_buffer = data[#data]
--   else
--     content = content .. pio_buffer .. data[1]
--     pio_buffer = data[1]
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
--       -- ✅ SUCCESSFUL RUN DETECTED: Kill the countdown timer immediately!
--       callBack = nil
--       M.queue = {}
--
--       -----------------------------------------------------------------------
--       -- 🌟 ONE-TIME EXTRACTOR ON TERMINATION (HISTORY COMPLETELY INTACT!)
--       -----------------------------------------------------------------------
--       if clangd_check_active then
--         clangd_extracted_args = {}
--
--         -- 1. Find boundaries on the raw, un-truncated content string
--         local start_pattern = '_CMMNDS_' .. current_token .. '":"' .. final_status
--         local _, start_idx = string.find(content, start_pattern, 1, true)
--
--         if not start_idx then
--           local fallback_echo = '_CMMNDS_' .. current_token .. '":"DONE'
--           _, start_idx = string.find(content, fallback_echo, 1, true)
--         end
--
--         local end_pattern = '_CMMNDS_' .. current_token .. ':' .. final_status
--         local end_idx = string.find(content, end_pattern, 1, true)
--
--         -- 2. Slice and parse the exact fresh run text block
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
--         else return end
--         clangd_check_active = false
--       end
--       -----------------------------------------------------------------------
--
--       -- 🏁 3. FLUSH THE BUFFER CLEAN HERE AT THE END OF THE COMMAND RUN
--       pio_buffer = ''
--       content = ''
--     end
--
--     if final_status and active_cb then
--       vim.schedule(function() active_cb(final_status) end)
--     end
--
--     return
--   end
-- end
-- =============================================================================

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

  if callBack then
    vim.schedule(function()
      content = ''
      pio_buffer = ''
      ------------------------------------------------------
      clangd_extracted_args = {} -- Clear the collected flags table
      clangd_check_active = false -- Arm the parsing loop tracker
      ------------------------------------------------------

      require('nvimpio.device.terminal').stdout_callback = M.stdoutcallback
      pio_cli = require('nvimpio.device.terminal').cli
      -- pio_cli = require('nvimpio.device.terminal').PioTerminal("", "cli")
        if require('nvimpio').is_active then _G.metadata.isBusy = true end
        pio_cli:show()
        callBack('INIT')
    end)
  end
end

------------------------------------------------------
-- Handle after pioinit execution
-- *=============================================================================
-- stylua: ignore
function M.cleanSequencer()
  _G.metadata.isBusy = false
  require('nvimpio.device.terminal').stdout_callback = nil -- Careful: make sure this doesn't break other terms
end

-- stylua: ignore
function M.handlePioinitDb(result, board, on_done)
  local active_env
  if result == 'INIT' then
    boilerplate.core_dir = require('nvimpio').config.pio_storage_dir
    boilerplate_gen([[platformio.ini]], OS.project_dir)
    pio_cli:send(pop(M.queue))
  elseif result == 'PASS1' then -- current_id
    OS.notify('PIO init+db:  pass ' .. current_id, "info")
    local meta = require('nvimpio.pio.metadata')
    active_env, _ = meta.get_active_env('PIO init+db: ')
    -- if not active_env or (active_env == board) then
    -- boilerplate_gen([[main.cpp]], vim.g.platformioRootDir .. '/src')
    -- boilerplate_gen([[main.hpp]], vim.g.platformioRootDir .. '/include')
    boilerplate_gen([[main.cpp]], vim.uv.cwd() .. '/src')
    boilerplate_gen([[main.hpp]], vim.uv.cwd() .. '/include')
    if #M.queue > 0 then pio_cli:send(pop(M.queue)) end
    -- else
    --   if on_done and type(on_done) == "function" then on_done(false) end
    --   M.cleanSequencer()
    -- end
  -- elseif result == 'PASS2' then
  elseif result == 'DONE' then -- result of the last command
    OS.notify('PIO init+db: Done', "info")
    if not active_env or (active_env ~= board) then
      OS.notify(string.format('PIO init+db active_env: %s', board), 'info')
      _G.metadata.active_env = board
    end
    M.pio_refresh(function(success)
      if on_done and type(on_done) == "function" then on_done(true) end
      if success then boilerplate.core_dir = _G.metadata.core_dir end
    end, 'PIO init+db: ')
    pio_cli:hide()
    M.cleanSequencer()
  elseif result == 'FAIL' then
    if on_done and type(on_done) == "function" then on_done(false) end
    M.cleanSequencer()
  end
end

-- stylua: ignore
function M.handlePioinit(result, board, on_done)
  if result == 'INIT' then
    -- OS.notify(string.format("active_env=%s board=%s", active_env, board), 'info')
    boilerplate.core_dir = require('nvimpio').config.pio_storage_dir
    boilerplate_gen([[platformio.ini]], vim.g.platformioRootDir)
    pio_cli:send(pop(M.queue))
  -- elseif result == 'PASS1' then
  elseif result == 'DONE' then -- result of the last command
    OS.notify(fromMsg .. 'project init Done', "info")
    boilerplate_gen([[main.cpp]], vim.uv.cwd() .. '/src')
    boilerplate_gen([[main.hpp]], vim.uv.cwd() .. '/include')
    pio_cli:hide()
    if on_done and type(on_done) == "function" then on_done(true) end
    _G.metadata.active_env = board
    M.cleanSequencer()
  elseif result == 'FAIL' then
    if on_done and type(on_done) == "function" then on_done(false) end
    M.cleanSequencer()
  end
end

------------------------------------------------------
-- Handle after piolib execution
-- =============================================================================
-- stylua: ignore
function M.handlePioInstall(result, on_done)
  if result == 'INIT' then
    if on_done and type(on_done) == "function" then
      vim.keymap.set('n', '<leader>\\t', function() pio_cli:show() end, { desc = 'open Term' })
    end
    pio_cli:send(pop(M.queue))
  elseif result == 'PASS' .. current_id then
      OS.notify('PIO install:  pass ' .. current_id, "info")
      if #M.queue > 0 then pio_cli:send(pop(M.queue)) end
  -- elseif result == 'PASS2' then
  elseif result == 'DONE' then -- result of the only and the last command
    OS.notify('PIO install: Done', "info")

    -- 1. Always remove the script
    local script_path = vim.fs.joinpath(OS.cache_dir, 'get-platformio.py')
    os.remove(script_path)
    -- 2. Find and remove random temp folders like .piocore-installer-xxxx
    local temp_patterns = { ".piocore-installer-*", "platformio-core-installer-*" }
    for _, pattern in ipairs(temp_patterns) do
      local matches = vim.fn.glob(pattern, true, true)
      for _, path in ipairs(matches) do
        if vim.fn.isdirectory(path) == 1 then vim.fn.delete(path, "rf") end
      end
    end

    if on_done and type(on_done) == "function" then on_done(true) end
    -- if trm then trm:close() end
    M.cleanSequencer()
    -- trm:shutdown()
  elseif result == 'FAIL' then
     OS.notify('Installation failed! Check logs and press :q to close.', 'error')
    if on_done and type(on_done) == "function" then on_done(false) end
    M.cleanSequencer()
  end
end

------------------------------------------------------
-- Handle create clang-format
-- =============================================================================
-- stylua: ignore
function M.clangFormat(result)
  if result == 'INIT' then
    pio_cli:send(pop(M.queue))
  elseif result == 'DONE' then -- result of the only and the last command
    OS.notify('Clang formatter: Done', "info")
    if pio_cli then pio_cli:close() end
    M.cleanSequencer()
  elseif result == 'FAIL' then
    M.cleanSequencer()
  end
end

------------------------------------------------------
-- Handle command
-- =============================================================================
-- stylua: ignore
function M.handleIdedata0(result, active_env, on_done)
  if result == 'INIT' then
    pio_cli:send(pop(M.queue))
  elseif result == 'PASS' .. current_id then
    OS.notify(string.format('%sidedata  pass%s', fromMsg, current_id), "info")
    if #M.queue > 0 then pio_cli:send(pop(M.queue)) end
  -- elseif result == 'PASS2' then
  elseif result == 'DONE' then -- result of the only and the last command
    OS.notify(string.format('%s compiledb success for %s.', fromMsg, active_env), "info")
    vim.defer_fn(function()
      require('nvimpio.clangd.control').getUnknownArgsCli(fromMsg)
    end, 50) -- 50ms delay, adjust as needed
    if on_done and type(on_done) == 'function' then on_done(true) end
    -- vim.schedule(function()
    --   require('nvimpio.clangd.control').getUnknownArgs(fromMsg)
    --   if on_done and type(on_done) == 'function' then on_done(true) end
    -- end)
    pio_cli:hide()
    M.cleanSequencer()
  elseif result == 'FAIL' then
    M.cleanSequencer()
  end
end

-- =============================================================================
local pass1 = false
-- stylua: ignore
function M.handlePioDBArgs(result, active_env, on_done)
  if result == 'INIT' then
    pio_cli:send(pop(M.queue))
  elseif result == 'PASS1' then -- .. current_id then                         -- compiledb PASS1
    OS.notify(string.format('%s compiledb success for %s.', fromMsg, active_env), "info")
    pass1  = true

    boilerplate.args = {}
    boilerplate_gen('.clangd', vim.g.platformioRootDir) -- read user '.clangd'

    clangd_extracted_args = {}       -- Clear the collected flags table
    clangd_check_active = true
    -- vim.defer_fn(function()
      -- require('nvimpio.clangd.control').getUnknownArgs(fromMsg)
      if #M.queue > 0 then pio_cli:send(pop(M.queue)) end
    -- end, 50) -- 50ms delay, adjust as needed
  elseif result == 'DONE' then -- result of the only and the last command
    if on_done and type(on_done) == 'function' then
      on_done(true)
      if pass1 then
        vim.defer_fn(function()
          boilerplate.args = clangd_extracted_args
          boilerplate_gen('.clangd', vim.g.platformioRootDir)
          OS.notify(string.format('%s Clangd ✅Extracted %s flags', fromMsg, #clangd_extracted_args), 'info')
          require('nvimpio.clangd.control').restart()
        end, 500) -- 50ms delay, adjust as needed
      end
    end
    pio_cli:hide()
    M.cleanSequencer()
  elseif result == 'FAIL' then
    if on_done and type(on_done) == 'function' then
      if pass1 then
        vim.defer_fn(function()
          boilerplate.args = clangd_extracted_args
          boilerplate_gen('.clangd', vim.g.platformioRootDir)
          OS.notify(string.format('%s Clangd ✅Extracted %s flags', fromMsg, #clangd_extracted_args), 'info')
          require('nvimpio.clangd.control').restart()
        end, 500) -- 50ms delay, adjust as needed
        on_done(true)
      else on_done(false) end
    end
    pio_cli:hide()
    M.cleanSequencer()
  end
end
-- =============================================================================

-- stylua: ignore
-- *=============================================================================
function M.handlePioDB(result, active_env, on_done)
  if result == 'INIT' then
    pass1 = false
    pio_cli:send(pop(M.queue))
  elseif result == 'PASS1' then -- .. current_id then                         -- idedata PASS1
    OS.notify(string.format('%sls  for %s', fromMsg, active_env), "info")
    if #M.queue > 0 then pio_cli:send(pop(M.queue)) end
  elseif result == 'DONE' then -- .. current_id then                         -- compiledb PASS1
    vim.schedule(function()
      OS.notify(string.format('%s compiledb success for %s.', fromMsg, active_env), "info")
      require('nvimpio.clangd.control').restart()
      if on_done and type(on_done) == 'function' then on_done(true) end
    end)
    M.cleanSequencer()
  elseif result == 'FAIL' then
    if on_done and type(on_done) == 'function' then on_done(false) end
    M.cleanSequencer()
  end
end

------------------------------------------------------
-- Handle command
-- =============================================================================
local pass2 = false
-- stylua: ignore
function M.handleIdedata(result, active_env, on_done)
  if result == 'INIT' then
    pio_cli:send(pop(M.queue))
  elseif result == 'PASS1' then -- .. current_id then                         -- idedata PASS1
    OS.notify(string.format('%sidedata  for %s', fromMsg, active_env), "info")
    if #M.queue > 0 then pio_cli:send(pop(M.queue)) end
  elseif result == 'PASS2' then -- .. current_id then                         -- compiledb PASS1
    OS.notify(string.format('%s compiledb success for %s.', fromMsg, active_env), "info")
    pass2  = true

    boilerplate.args = {}
    boilerplate_gen('.clangd', vim.g.platformioRootDir) -- read user '.clangd'

    clangd_extracted_args = {}       -- Clear the collected flags table
    clangd_check_active = true
    -- vim.defer_fn(function()
      -- require('nvimpio.clangd.control').getUnknownArgs(fromMsg)
      if #M.queue > 0 then pio_cli:send(pop(M.queue)) end
    -- end, 50) -- 50ms delay, adjust as needed
  elseif result == 'DONE' then                                       -- unknown args DONE
    if on_done and type(on_done) == 'function' then
      on_done(true)
      if pass2 then
        vim.defer_fn(function()
          boilerplate.args = clangd_extracted_args
          boilerplate_gen('.clangd', vim.g.platformioRootDir)
          OS.notify(string.format('%s Clangd ✅Extracted %s flags', fromMsg, #clangd_extracted_args), 'info')
          require('nvimpio.clangd.control').restart()
        end, 500) -- 50ms delay, adjust as needed
      end
    end
    if trm then trm:close() end
    M.cleanSequencer()
  elseif result == 'FAIL' then                                       -- FAIL
    if on_done and type(on_done) == 'function' then
      if pass2 then
        vim.defer_fn(function()
          boilerplate.args = clangd_extracted_args
          boilerplate_gen('.clangd', vim.g.platformioRootDir)
          OS.notify(string.format('%s Clangd ✅Extracted %s flags', fromMsg, #clangd_extracted_args), 'info')
          require('nvimpio.clangd.control').restart()
        end, 500) -- 50ms delay, adjust as needed
        on_done(true)
      else on_done(false) end
    end
    if trm then trm:close() end
    M.cleanSequencer()
  end
end

------------------------------------------------------
-- Handle command
-- =============================================================================
-- stylua: ignore
function M.handleClangdCheck(result, on_done)
  if result == 'INIT' then
    pio_cli:send(pop(M.queue))
  elseif result == 'DONE' then -- result of the only and the last command
    OS.notify(string.format('%sclangd check  done', fromMsg), 'info')
    local final_args = clangd_extracted_args -- Hold the pointer reference for the scheduled function
    vim.schedule(function()
      if on_done and type(on_done) == 'function' then on_done(true, final_args) end
    end)
    pio_cli:hide()
    M.cleanSequencer()
  elseif result == 'FAIL' then
    OS.notify(string.format('%s clangd check  fail', fromMsg), 'info')
    local final_args = clangd_extracted_args -- Hold the pointer reference for the scheduled function
    vim.schedule(function()
      if on_done and type(on_done) == 'function' then on_done(true, final_args) end
    end)
    pio_cli:hide()
    M.cleanSequencer()
  end
end

------------------------------------------------------
-- Handle after piolib execution
-- =============================================================================
-- stylua: ignore
function M.handlePiolib(result)
  if result == 'INIT' then
    pio_cli:send(pop(M.queue))
  elseif result == 'PASS' then
    OS.notify('PIO lib+db:  pass ' .. current_id, "info")
    -- if #M.queue > 0 then trm:send(table.remove(M.queue, 1), false) end
    if #M.queue > 0 then pio_cli:send(pop(M.queue)) end
  elseif result == 'DONE' then -- result of the last command
    vim.schedule(function()
      OS.notify('PIO lib+db: Done', "info")
      M.pio_refresh(function(success)
        if success then require('nvimpio.clangd.control').getUnknownArgsCli('PIO lib+db: ') end
      end, 'PIO lib+db: ')
    end)
    pio_cli:hide()
    M.cleanSequencer()
  elseif result == 'FAIL' then
    M.cleanSequencer()
  end
end

return M
