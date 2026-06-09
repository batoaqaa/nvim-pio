local M = {}

local misc = require('nvimpio.utils.misc')
---@type Terminal
-- local terminal = require('nvimpio.utils.term').terminal
-- local terminal = require('nvimpio.device.terminal').terminal

-- local pio_cli = _G.metadata.pio_cli
-- local function sendCmnd(command)
--   pio_cli = pio_cli or require('nvimpio.device.terminal').PioTerminal('', 'cli')
--   if pio_cli then
--     pio_cli:show()
--     pio_cli:send(command)
--   end
-- end
-- =====================================================================
-- 🛠️ FIXED CRASH-PROOF AUTOMATION SEQUENCE (Inside cli.lua)
-- =====================================================================
local function sendCmnd(command)
  -- Always reference the live table key directly at runtime!
  -- This is 100% immune to variable snapshot desynchronization leaks.
  _G.metadata.pio_cli = _G.metadata.pio_cli or require('nvimpio.device.terminal').PioTerminal('', 'cli')

  -- Isolate the verified live object reference for the current execution pass block
  local active_cli = _G.metadata.pio_cli

  if active_cli then
    -- Safely call your prototype methods with absolute zero risk of nil crashes!
    active_cli:show()
    active_cli:send(command)
  else
    vim.notify('[PlatformIO] Error: Terminal pipeline failed to resolve a valid class instance.', vim.log.levels.ERROR)
  end
end

--- Handles and formats asynchronous vim.system errors cleanly
---@param from string The notification origin tag
---@param prefix_msg string The introductory text (e.g., "build compiledb failed: ")
---@param obj table The raw result object returned from vim.system
local function notify_system_error(from, prefix_msg, obj)
  local error_map = {
    [1] = 'PlatformIO general execution failure (Check code syntax or profile constraints)',
    [2] = 'Configuration file formatting conflict (Check platformio.ini structure)',
    [124] = 'Asynchronous timeout operation exceeded limits (Hard Timeout reached)',
    [127] = "Executable environment missing (PlatformIO command 'pio' was not found in your $PATH variables)",
  }

  -- Handle native operating system timeout signals (SIGTERM = 15 or exit code 124)
  local is_timeout = (obj.code == 124 or obj.signal == 15)
  local err_code = is_timeout and 124 or obj.code

  -- Resolve the text message using the lookup table, falling back to the raw integer code
  local error_text = error_map[err_code] or string.format('OS Shell Exit Code (%d)', obj.code)

  -- Safely grab the standard error block, or default to a safe blank fallback string
  local details = (obj.stderr and obj.stderr ~= '') and ('\nDetails: ' .. obj.stderr) or ''

  -- Send a singular clean notification
  OS.notify(from .. prefix_msg .. error_text .. details, 'error')
end

-- stylua: ignore start
--INFO: Generate idedata.json
------------------------------------------------------------------------------------
-- Dedicated in-memory pointer to isolate and track the background IDE data job tree
local idedata_job_handle = nil
---Compiles PlatformIO project IDE framework metadata asynchronously with cancellation hooks
---@param from string Logging context tracker prefix string
---@param active_env string? The targeted microchip environment block choice
---@param cb fun(success: boolean)? Optional callback hook to execute on completion or failure
---@return boolean success Returns true immediately to signify the background job was spawned
function M.buildIdedata(from, active_env, cb)
  from = (type(from) == 'string' and from ~= '') and from or 'PIO: '
  active_env = active_env or _G.metadata.active_env

  -- 1. Concurrent Execution Guard: Block redundant multiple scans from thrashing the CPU
  if idedata_job_handle then
    vim.notify("NVIM-PIO: IDE metadata generation is already running.", vim.log.levels.WARN)
    return true
  end

  -- Update global metadata parameters state instantly
  _G.metadata.isBusy = true
  _G.metadata.idedata_status = "Generating"

  -- 2. Visual Status Update Notification
  local msg = string.format("Extracting IDE Metadata configurations for [%s]...", active_env)
  if _G.OS and type(_G.OS.notify) == 'function' then
    _G.OS.notify(msg .. "\nUse :PioAbortIdeData to cancel if it hangs.", 'info')
  else
    vim.notify("NVIM-PIO: " .. msg, vim.log.levels.INFO)
  end

  -- 3. Provision the On-Demand Abort User Command Interceptor
  vim.api.nvim_create_user_command('PioAbortIdeData', function()
    if idedata_job_handle then
      -- Terminate the entire system sub-process tree instantly using SIGKILL (9)
      pcall(function() idedata_job_handle:kill(9) end)
      idedata_job_handle = nil
      _G.metadata.isBusy = false
      _G.metadata.idedata_status = "Aborted"

      local abort_txt = "IDE structural metadata build forcefully cancelled by user request."
      if _G.OS and type(_G.OS.notify) == 'function' then
        _G.OS.notify(abort_txt, 'warn')
      else
        vim.notify("NVIM-PIO: " .. abort_txt, vim.log.levels.WARN)
      end
      if cb then cb(false) end
    end
  end, { force = true, desc = "Forcefully kill the running background PlatformIO idedata compilation task" })

  -- 4. REMOVED CONSTRICTOR TIMEOUT: Run via raw non-blocking background streaming process handle
  local ok, handle = pcall(function()
    return vim.system({ 'pio', 'run', '-t', 'idedata', '-e', active_env, '-s' }, { text = true }, function(obj)
      -- Clear the temporary process reference pointer from memory immediately upon exit
      idedata_job_handle = nil

      vim.schedule(function()
        _G.metadata.isBusy = false
        local success = (obj and obj.code == 0)

        if success then
          _G.metadata.idedata_status = "Ready"
          local succ_txt = string.format('%sBuild idedata success for %s.', from, active_env)
          if _G.OS and type(_G.OS.notify) == 'function' then
            _G.OS.notify(succ_txt, 'info')
          else
            vim.notify("NVIM-PIO: " .. succ_txt, vim.log.levels.INFO)
          end
        else
          -- If the job exited due to a SIGKILL or user cancellation, handle the states gracefully
          if obj.code == 9 or _G.metadata.idedata_status == "Aborted" then
            _G.metadata.idedata_status = "Cancelled"
          else
            _G.metadata.idedata_status = "Failed"
            if type(notify_system_error) == "function" then
              notify_system_error(from, string.format('Build idedata for %s failed: ', active_env), obj)
            else
              vim.notify(string.format("NVIM-PIO: Build idedata failed with exit code %s", obj.code), vim.log.levels.ERROR)
            end
          end
        end

        -- Delete the placeholder command interceptor immediately once the thread closes
        pcall(function() vim.api.nvim_del_user_command('PioAbortIdeData') end)

        if cb and type(cb) == "function" then cb(success) end
      end)
    end)
  end)

  if ok and handle then
    idedata_job_handle = handle
  else
    idedata_job_handle = nil
    _G.metadata.isBusy = false
    _G.metadata.idedata_status = "Failed"
    vim.notify("NVIM-PIO: Failed to initialize background system execution process pipeline.", vim.log.levels.ERROR)
    pcall(function() vim.api.nvim_del_user_command('PioAbortIdeData') end)
    if cb then cb(false) end
  end

  return true
end


-- function M.buildIdedata(from, active_env, cb)
--   vim.system({ 'pio', 'run', '-t', 'idedata', '-e', active_env, '-s' }, { timeout = 60000, text = true }, function(obj)
--     vim.schedule(function()
--       local ok = (obj.code == 0)
--       if ok then
--         OS.notify(string.format('%sbuild idedata success for %s.', from, active_env), 'info')
--       else
--         notify_system_error(from, string.format('build idedata for %s failed: ', active_env), obj)
--       end
--
--       if cb and type(cb) == "function" then cb(ok) end
--     end)
--   end)
--   return true
-- end

--INFO: Generate compiledb
------------------------------------------------------------------------------------
-- In-memory state tracking to prevent multiple concurrent database compilations
-- local compile_job_handle = nil
--
-- ---Compiles the project compilation database asynchronously with user feedback and kill hooks
-- ---@param from string Logging context tracker prefix
-- ---@param active_env string? The targeted environment layout choice
-- ---@param cb fun(success: boolean)? Optional callback hook to execute on termination
-- function M.buildCompileDB(from, active_env, cb)
--   from = (type(from) == 'string' and from ~= '') and from or 'PIO: '
--   active_env = active_env or _G.metadata.active_env
--
--   -- 1. Concurrent Execution Guard
--   if compile_job_handle then
--     vim.notify("NVIM-PIO: Compilation database generation is already running.", vim.log.levels.WARN)
--     return
--   end
--
--   -- Update global metadata states immediately
--   _G.metadata.isBusy = true
--   _G.metadata.compiledb_status = "Generating"
--
--   -- 2. Visual Progress Feedback System
--   local msg = string.format("Generating Compilation Database for [%s]...", active_env)
--   if _G.OS and type(_G.OS.notify) == 'function' then
--     _G.OS.notify(msg .. "\nUse :PioAbortCompile to cancel if it takes too long.", 'info')
--   else
--     vim.notify("NVIM-PIO: " .. msg, vim.log.levels.INFO)
--   end
--
--   -- 3. Provision the On-Demand Abort User Command Interceptor
--   vim.api.nvim_create_user_command('PioAbortCompile', function()
--     if compile_job_handle then
--       -- Send a strict SIGKILL system signal to terminate the terminal job tree immediately
--       pcall(function() compile_job_handle:kill(9) end)
--       compile_job_handle = nil
--       _G.metadata.isBusy = false
--       _G.metadata.compiledb_status = "Aborted"
--
--       local abort_txt = "Compilation database build aborted by user command."
--       if _G.OS and type(_G.OS.notify) == 'function' then
--         _G.OS.notify(abort_txt, 'warn')
--       else
--         vim.notify("NVIM-PIO: " .. abort_txt, vim.log.levels.WARN)
--       end
--       if cb then cb(false) end
--     end
--   end, { force = true, desc = "Abort the running background PlatformIO database compilation job" })
--
--   -- 4. REMOVED STRUCTURAL TIMEOUT: Spawn background stream via process handles engine
--   -- This lets the background compilation take as long as it needs without throwing exceptions
--   local ok, handle = pcall(function()
--     return vim.system({ 'pio', 'run', '-t', 'compiledb', '-e', active_env }, { text = true }, function(obj)
--       -- Clean up the persistent memory process pointer handle references
--       compile_job_handle = nil
--
--       vim.schedule(function()
--         _G.metadata.isBusy = false
--         local success = (obj and obj.code == 0)
--
--         if success then
--           _G.metadata.compiledb_status = "Ready"
--           local succ_txt = string.format('%sBuild compiledb success for %s.', from, active_env)
--           if _G.OS and type(_G.OS.notify) == 'function' then
--             _G.OS.notify(succ_txt, 'info')
--           else
--             vim.notify("NVIM-PIO: " .. succ_txt, vim.log.levels.INFO)
--           end
--         else
--           -- If code is 9, it means the user canceled it, so we don't dump a noisy error panel
--           if obj.code == 9 or _G.metadata.compiledb_status == "Aborted" then
--             _G.metadata.compiledb_status = "Cancelled"
--           else
--             _G.metadata.compiledb_status = "Failed"
--             -- Helper to format stack logs dynamically
--             if type(notify_system_error) == "function" then
--               notify_system_error(from, string.format('Build compiledb for %s failed: ', active_env), obj)
--             else
--               vim.notify(string.format("NVIM-PIO: Build compiledb failed with exit code %s", obj.code), vim.log.levels.ERROR)
--             end
--           end
--         end
--
--         -- Delete the placeholder abort command cleanly once execution thread completes
--         pcall(function() vim.api.nvim_del_user_command('PioAbortCompile') end)
--
--         if cb and type(cb) == "function" then cb(success) end
--       end)
--     end)
--   end)
--
--   if ok and handle then
--     compile_job_handle = handle
--   else
--     compile_job_handle = nil
--     _G.metadata.isBusy = false
--     _G.metadata.compiledb_status = "Failed"
--     vim.notify("NVIM-PIO: Failed to spawn background system process loop.", vim.log.levels.ERROR)
--     pcall(function() vim.api.nvim_del_user_command('PioAbortCompile') end)
--     if cb then cb(false) end
--   end
-- end
function M.buildCompileDB(from, active_env, cb)
  -- =========================================================================
  -- THE LEAK FINDER GADGET: Prints the exact file calling this on boot!
  -- =========================================================================
  -- print("DEBUG LEAK SOURCE DETECTED BY:")
  -- print(debug.traceback())
  -- =========================================================================

  active_env = active_env or _G.metadata.active_env
  vim.system({ 'pio', 'run', '-t', 'compiledb', '-e', active_env }, { timeout = 60000,  text = true }, function(obj)
    vim.schedule(function()
      local ok = (obj.code == 0)
      if ok then
        OS.notify(string.format('%sbuild compiledb success for %s.', from, active_env), 'info')
      else
        notify_system_error(from, string.format('build compiledb for %s failed: ', active_env), obj)
      end
      if cb and type(cb) == "function" then cb(ok) end
    end)
  end)
end

--INFO: Piocmd(h/f)
------------------------------------------------------
function M.piocmd(cmd_table, direction)
  if not misc.pio_install_check() then return end

  local cmd = (cmd_table[1] == '') and '' or ('pio ' .. table.concat(cmd_table, ' '))
  sendCmnd(cmd)
  -- cmd = 'pio ' .. cmd
  -- if cmd_table[1] == '' then terminal('', direction)
  -- else
  --   local cmd = 'pio '
  --   for _, v in pairs(cmd_table) do cmd = cmd .. ' ' .. v end
  --   terminal(cmd, direction)
  -- end
end

--INFO: Piodebug
------------------------------------------------------
function M.piodebug(_)
  if not misc.pio_install_check() then return end

  local command = 'pio debug --interface=gdb -- -x .pioinit'
  -- local command = string.format('pio debug --interface=gdb -- -x .pioinit %s', utils.extra)
  -- terminal(command, 'float')
  sendCmnd(command)
end

--INFO: Piomon
------------------------------------------------------
function M.piomon(args_table)
  if not misc.pio_install_check() then return end

  local command = nil
  if #args_table == 0 then command = 'pio device monitor'
  elseif #args_table == 1 then
    local baud_rate = args_table[1]
    command = string.format('pio device monitor -b %s', baud_rate)
  elseif #args_table == 2 then
    local baud_rate = args_table[1]
    local port = args_table[2]
    command = string.format('pio device monitor -b %s -p %s', baud_rate, port)
  end

  if command == nil then vim.misc.notify('Usage: Piomon <baud> <port>', "error")
  else
    sendCmnd(command)
    -- terminal(command, 'horizontal') 
  end
end

--INFO: Piorun
------------------------------------------------------
function M.piobuild()
  local command = 'pio run' -- .. utils.extra
  sendCmnd(command)
  -- terminal(command, 'float')
end

function M.pioupload()
  local command = 'pio run --target upload' -- .. utils.extra
  sendCmnd(command)
  -- terminal(command, 'float')
end

function M.piouploadfs()
  local command = 'pio run --target uploadfs' -- .. utils.extra
  sendCmnd(command)
  -- terminal(command, 'float')
end

function M.pioclean()
  local command = 'pio run --target clean' -- .. utils.extra
  sendCmnd(command)
  -- terminal(command, 'float')
end

function M.piorun(arg_table)
  if not misc.pio_install_check() then return end
  if arg_table[1] == '' then M.pioupload()
  elseif arg_table[1] == 'upload' then M.pioupload()
  elseif arg_table[1] == 'uploadfs' then M.piouploadfs()
  elseif arg_table[1] == 'build' then M.piobuild()
  elseif arg_table[1] == 'clean' then M.pioclean()
  else vim.misc.notify('Invalid argument: build, upload, uploadfs or clean', 'warn') end
end
-- stylua: ignore end

return M
