local M = {}

-- stylua: ignore start
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
local pio_buffer = ''
local content = ''

-- require('nvimpio.device.terminal').stdout_callback = M.stdoutcallback
function M.stdoutcallback(_, raw_incoming_data, _)
-- function M.stdoutcallback(job_id, raw_incoming_data, event)
  if not raw_incoming_data or #raw_incoming_data == 0 then return end
  if not current_token then return end

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

local cliTerm
-- INFO: commands sequencer
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
      cliTerm = require('nvimpio.device.terminal').cli
      -- cliTerm = require('nvimpio.device.terminal').terminals.cli
      -- cliTerm = require('nvimpio.device.terminal').PioTerminal("", "cli")
        _G.isBusy = true
        -- if require('nvimpio').is_active then _G.isBusy = true end
        cliTerm:show()
        callBack('INIT')
    end)
  end
end

------------------------------------------------------
-- Handle after pioinit execution
-- *=============================================================================
function M.cleanSequencer()
  _G.isBusy = false
  require('nvimpio.device.terminal').stdout_callback = nil -- Careful: make sure this doesn't break other terms
end

-- function M.handlePioinitDb(result, board, on_done)
--   local active_env
--   if result == 'INIT' then
--     boilerplate.core_dir = require('nvimpio').config.pio_storage_dir
--     boilerplate_gen([[platformio.ini]], OS.project_dir)
--     cliTerm:send(pop(M.queue))
--   elseif result == 'PASS1' then -- current_id
--     OS.notify('PIO init+db:  pass ' .. current_id, OS.debug)
--     local meta = require('nvimpio.pio.metadata')
--     active_env, _ = meta.get_active_env('PIO init+db: ')
--     -- if not active_env or (active_env == board) then
--     -- boilerplate_gen([[main.cpp]], vim.g.platformioRootDir .. '/src')
--     -- boilerplate_gen([[main.hpp]], vim.g.platformioRootDir .. '/include')
--     boilerplate_gen([[main.cpp]], vim.uv.cwd() .. '/src')
--     boilerplate_gen([[main.hpp]], vim.uv.cwd() .. '/include')
--     if #M.queue > 0 then cliTerm:send(pop(M.queue)) end
--     -- else
--     --   if on_done and type(on_done) == "function" then on_done(false) end
--     --   M.cleanSequencer()
--     -- end
--   -- elseif result == 'PASS2' then
--   elseif result == 'DONE' then -- result of the last command
--     OS.notify('PIO init+db: Done', OS.debug)
--     if not active_env or (active_env ~= board) then
--       OS.notify(string.format('PIO init+db active_env: %s', board), OS.debug)
--       _G.metadata.active_env = board
--     end
--     M.pio_refresh(function(success)
--       if on_done and type(on_done) == "function" then on_done(true) end
--       if success then boilerplate.core_dir = _G.metadata.core_dir end
--     end, 'PIO init+db: ')
--     cliTerm:hide()
--     M.cleanSequencer()
--   elseif result == 'FAIL' then
--     if on_done and type(on_done) == "function" then on_done(false) end
--     M.cleanSequencer()
--   end
-- end

function M.handlePioinit(result, framework, board, on_done)
  if result == 'INIT' then
    -- OS.notify(string.format("active_env=%s board=%s", active_env, board), OS.debug)
    boilerplate.core_dir = require('nvimpio').config.pio_storage_dir
    -- boilerplate_gen([[platformio.ini]], vim.g.platformioRootDir)
    boilerplate_gen([[platformio.ini]])
    boilerplate_gen(framework)
    cliTerm:send(pop(M.queue))
  -- elseif result == 'PASS1' then
  elseif result == 'DONE' then -- result of the last command
    OS.notify(fromMsg .. 'project init Done', OS.debug)
    cliTerm:hide()
    if on_done and type(on_done) == "function" then on_done(true) end
    -- _G.metadata.active_env = board
    M.cleanSequencer()
  elseif result == 'FAIL' then
    if on_done and type(on_done) == "function" then on_done(false) end
    M.cleanSequencer()
  end
end

function M.handlePioInstall(result, on_done)
  if result == 'INIT' then
    if on_done and type(on_done) == "function" then
      vim.keymap.set('n', '<leader>\\t', function() cliTerm:show() end, { desc = 'open Term' })
    end
    cliTerm:send(pop(M.queue))
  elseif result == 'PASS' .. current_id then
      OS.notify('PIO install:  pass ' .. current_id, OS.debug)
      if #M.queue > 0 then cliTerm:send(pop(M.queue)) end
  -- elseif result == 'PASS2' then
  elseif result == 'DONE' then -- result of the only and the last command
    OS.notify('PIO install: Done', OS.debug)

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
    M.cleanSequencer()
  elseif result == 'FAIL' then
    OS.notify('Installation failed!', 'error')
    if on_done and type(on_done) == "function" then on_done(false) end
    M.cleanSequencer()
  end
end

function M.handlePioRepair(result, on_done)
  if result == 'INIT' then
    cliTerm:send(pop(M.queue))
  elseif result == 'PASS' .. current_id then
      OS.notify('PIO install:  pass ' .. current_id, OS.debug)
      if #M.queue > 0 then cliTerm:send(pop(M.queue)) end
  elseif result == 'DONE' then -- result of the only and the last command
     OS.notify(string.format('%s:  Done', fromMsg), OS.debug)
    if on_done and type(on_done) == "function" then on_done(true) end
    M.cleanSequencer()
  elseif result == 'FAIL' then
    OS.notify(string.format('%s:  Upgrade Failed', fromMsg), "info")
    if on_done and type(on_done) == "function" then on_done(false) end
    M.cleanSequencer()
  end
end

------------------------------------------------------
-- Handle create clang-format
-- =============================================================================
function M.clangFormat(result)
  if result == 'INIT' then
    cliTerm:send(pop(M.queue))
  elseif result == 'DONE' then -- result of the only and the last command
    OS.notify('Clang formatter: Done', OS.debug)
    if cliTerm then cliTerm:hide() end
    M.cleanSequencer()
  elseif result == 'FAIL' then
    M.cleanSequencer()
  end
end

------------------------------------------------------
-- Handle command
-- =============================================================================
function M.handleIdedata(result, active_env, on_done)
  if result == 'INIT' then
    cliTerm:send(pop(M.queue))
  elseif result == 'PASS' .. current_id then
    OS.notify(string.format('%sidedata handling  pass%s', fromMsg, current_id), OS.debug)
    if #M.queue > 0 then cliTerm:send(pop(M.queue)) end
  -- elseif result == 'PASS' .. current_id then
  --   OS.notify(string.format('%sbuild handling  pass%s', fromMsg, current_id), OS.debug)
  --   if #M.queue > 0 then cliTerm:send(pop(M.queue)) end
  -- elseif result == 'PASS2' then
  elseif result == 'DONE' then -- result of the only and the last command
    -- OS.notify(string.format('%s compiledb handling success for %s.', fromMsg, active_env), OS.debug)
    OS.notify(string.format('%scompiledb handling success for %s.', fromMsg, active_env), OS.debug)
    -- vim.defer_fn(function()
    --   require('nvimpio.clangd.control').getUnknownArgsCli(fromMsg)
    -- end, 50) -- 50ms delay, adjust as needed
    -- require('nvimpio.clangd.control').restart()
    if on_done and type(on_done) == 'function' then on_done(true) end
    cliTerm:hide()
    M.cleanSequencer()
  elseif result == 'FAIL' then
    if on_done and type(on_done) == 'function' then on_done(false) end
    M.cleanSequencer()
  end
end

-- local pass1 = false
-- =============================================================================
-- function M.handlePioDBArgs(result, active_env, on_done)
--   if result == 'INIT' then
--     cliTerm:send(pop(M.queue))
--   elseif result == 'PASS1' then -- .. current_id then                         -- compiledb PASS1
--     OS.notify(string.format('%s compiledb success for %s.', fromMsg, active_env), OS.debug)
--     pass1  = true
--
--     boilerplate.args = {}
--     boilerplate_gen('.clangd', vim.g.platformioRootDir) -- read user '.clangd'
--
--     clangd_extracted_args = {}       -- Clear the collected flags table
--     clangd_check_active = true
--     -- vim.defer_fn(function()
--       -- require('nvimpio.clangd.control').getUnknownArgs(fromMsg)
--       if #M.queue > 0 then cliTerm:send(pop(M.queue)) end
--     -- end, 50) -- 50ms delay, adjust as needed
--   elseif result == 'DONE' then -- result of the only and the last command
--     if on_done and type(on_done) == 'function' then
--       on_done(true)
--       if pass1 then
--         vim.defer_fn(function()
--           boilerplate.args = clangd_extracted_args
--           boilerplate_gen('.clangd', vim.g.platformioRootDir)
--           OS.notify(string.format('%s Clangd ✅Extracted %s flags', fromMsg, #clangd_extracted_args), OS.debug)
--           require('nvimpio.clangd.control').restart()
--         end, 500) -- 50ms delay, adjust as needed
--       end
--     end
--     cliTerm:hide()
--     M.cleanSequencer()
--   elseif result == 'FAIL' then
--     if on_done and type(on_done) == 'function' then
--       if pass1 then
--         vim.defer_fn(function()
--           boilerplate.args = clangd_extracted_args
--           boilerplate_gen('.clangd', vim.g.platformioRootDir)
--           OS.notify(string.format('%s Clangd ✅Extracted %s flags', fromMsg, #clangd_extracted_args), OS.debug)
--           require('nvimpio.clangd.control').restart()
--         end, 500) -- 50ms delay, adjust as needed
--         on_done(true)
--       else on_done(false) end
--     end
--     cliTerm:hide()
--     M.cleanSequencer()
--   end
-- end

-- *=============================================================================
function M.handlePioDB(result, active_env, on_done)
  if result == 'INIT' then
    cliTerm:send(pop(M.queue))
  elseif result == 'DONE' then -- .. current_id then                         -- compiledb PASS1
    vim.schedule(function()
      OS.notify(string.format('%s compiledb success for %s.', fromMsg, active_env), OS.debug)
      -- require('nvimpio.clangd.control').restart()
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
-- function M.handleIdedata1(result, active_env, on_done)
--   if result == 'INIT' then
--     cliTerm:send(pop(M.queue))
--   elseif result == 'PASS1' then -- .. current_id then                         -- idedata PASS1
--     OS.notify(string.format('%sidedata  for %s', fromMsg, active_env), OS.debug)
--     if #M.queue > 0 then cliTerm:send(pop(M.queue)) end
--   elseif result == 'PASS2' then -- .. current_id then                         -- compiledb PASS1
--     OS.notify(string.format('%s compiledb success for %s.', fromMsg, active_env), OS.debug)
--
--     boilerplate.args = {}
--     boilerplate_gen('.clangd', vim.g.platformioRootDir) -- read user '.clangd'
--
--     clangd_extracted_args = {}       -- Clear the collected flags table
--     clangd_check_active = true
--     -- vim.defer_fn(function()
--       -- require('nvimpio.clangd.control').getUnknownArgs(fromMsg)
--       if #M.queue > 0 then cliTerm:send(pop(M.queue)) end
--     -- end, 50) -- 50ms delay, adjust as needed
--   elseif result == 'DONE' then                                       -- unknown args DONE
--     if on_done and type(on_done) == 'function' then
--       on_done(true)
--       vim.defer_fn(function()
--         boilerplate.args = clangd_extracted_args
--         boilerplate_gen('.clangd', vim.g.platformioRootDir)
--         OS.notify(string.format('%s Clangd ✅Extracted %s flags', fromMsg, #clangd_extracted_args), OS.debug)
--         require('nvimpio.clangd.control').restart()
--       end, 500) -- 50ms delay, adjust as needed
--     end
--     if trm then trm:close() end
--     M.cleanSequencer()
--   elseif result == 'FAIL' then                                       -- FAIL
--     if on_done and type(on_done) == 'function' then
--       if pass2 then
--         vim.defer_fn(function()
--           boilerplate.args = clangd_extracted_args
--           boilerplate_gen('.clangd', vim.g.platformioRootDir)
--           OS.notify(string.format('%s Clangd ✅Extracted %s flags', fromMsg, #clangd_extracted_args), OS.debug)
--           require('nvimpio.clangd.control').restart()
--         end, 500) -- 50ms delay, adjust as needed
--         on_done(true)
--       else on_done(false) end
--     end
--     if trm then trm:close() end
--     M.cleanSequencer()
--   end
-- end

------------------------------------------------------
-- Handle command
-- =============================================================================
function M.handleClangdCheck(result, on_done)
  if result == 'INIT' then
    cliTerm:send(pop(M.queue))
  elseif result == 'DONE' then -- result of the only and the last command
    OS.notify(string.format('%sclangd check  done', fromMsg), OS.debug)
    local final_args = clangd_extracted_args -- Hold the pointer reference for the scheduled function
    vim.schedule(function()
      if on_done and type(on_done) == 'function' then on_done(true, final_args) end
    end)
    cliTerm:hide()
    M.cleanSequencer()
  elseif result == 'FAIL' then
    OS.notify(string.format('%s clangd check  fail', fromMsg), OS.debug)
    local final_args = clangd_extracted_args -- Hold the pointer reference for the scheduled function
    vim.schedule(function()
      if on_done and type(on_done) == 'function' then on_done(true, final_args) end
    end)
    cliTerm:hide()
    M.cleanSequencer()
  end
end

------------------------------------------------------
-- Handle after piolib execution
-- =============================================================================
function M.handlePiolib(result, active_env, pkgName, on_done)
  if result == 'INIT' then
    cliTerm:send(pop(M.queue))
  elseif result == 'PASS1' then -- .. current_id then                         -- idedata PASS1
    OS.notify(string.format('%s %s installed for %s', fromMsg, pkgName, active_env), OS.debug)
    -- OS.notify('PIO lib:  pass ' .. current_id, OS.debug)
    if on_done and type(on_done) == 'function' then on_done() end
    if #M.queue > 0 then cliTerm:send(pop(M.queue)) end
  elseif result == 'DONE' then -- result of the last command
    vim.schedule(function()
      if on_done and type(on_done) == 'function' then on_done() end
      OS.notify(string.format('%s compiledb updated for %s', fromMsg, active_env), OS.debug)
      -- M.pio_refresh(function(success)
      --   if success then
      --     do end
      --     -- require('nvimpio.clangd.control').getUnknownArgsCli('PIO lib+db: ')
      --   end
      -- end, 'PIO lib+db: ')
    end)
    cliTerm:hide()
    M.cleanSequencer()
  elseif result == 'FAIL' then
    M.cleanSequencer()
  end
end

return M
