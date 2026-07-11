local M = {}

-- local term = require('nvimpio.device.terminal')
-- local term = require('nvimpio.device.terminal').terminals

local function getCli()
  local term = require('nvimpio.device.terminal').terminals
  if not term.terminals['cli'] then
    term.create_terminal('cli', ' CLI ', function(j, d, e)
      if type(term.stdout_callback) == 'function' then
        term.stdout_callback(j, d, e)
        return term.cli
      end
    end)
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

--- stylua: ignore start
--INFO: Generate idedata.json
------------------------------------------------------------------------------------
function M.buildIdedata(from, active_env, cb)
  vim.system({ 'pio', 'run', '-t', 'idedata', '-e', active_env, '-s' }, { timeout = 60000, text = true }, function(obj)
    vim.schedule(function()
      local ok = (obj.code == 0)
      if ok then
        OS.notify(string.format('%sbuild idedata success for %s.', from, active_env), 'info')
      else
        notify_system_error(from, string.format('build idedata for %s failed: ', active_env), obj)
      end

      if cb and type(cb) == 'function' then
        cb(ok)
      end
    end)
  end)
  return true
end

--INFO: Generate compiledb
------------------------------------------------------------------------------------
function M.buildCompileDB(from, active_env, cb)
  -- =========================================================================
  -- THE LEAK FINDER GADGET: Prints the exact file calling this on boot!
  -- =========================================================================
  -- print("DEBUG LEAK SOURCE DETECTED BY:")
  -- print(debug.traceback())
  -- =========================================================================

  active_env = active_env or _G.metadata.active_env
  vim.system({ 'pio', 'run', '-t', 'compiledb', '-e', active_env }, { timeout = 60000, text = true }, function(obj)
    vim.schedule(function()
      local ok = (obj.code == 0)
      if ok then
        OS.notify(string.format('%sbuild compiledb success for %s.', from, active_env), 'info')
      else
        notify_system_error(from, string.format('build compiledb for %s failed: ', active_env), obj)
      end
      if cb and type(cb) == 'function' then
        cb(ok)
      end
    end)
  end)
end

--INFO: Piocli
------------------------------------------------------
function M.piocli(cmd_table)
  -- local term = require('nvimpio.device.terminal').terminals
  -- local term = require('nvimpio.device.terminal')
  -- if not(term.terminals['cli']) then
  --  term.create_terminal('cli', ' CLI ', function(j, d, e)
  --    if type(M.stdout_callback) == 'function' then
  --      term.stdout_callback(j, d, e)
  --    end
  --  end)
  -- end
  local cli = getCli()
  if not cli then
    return
  end
  local cmd = (cmd_table[1] == '') and '' or ('pio ' .. table.concat(cmd_table, ' '))
  if cmd ~= '' then
    cli:send(cmd)
  else
    cli:show()
  end
end

--INFO: Piodebug
------------------------------------------------------
function M.piodebug(_)
  local term = require('nvimpio.device.terminal')
  local command = 'pio debug --interface=gdb -- -x .pioinit'
  term.cli:send(command)
end

--INFO: Piomon
------------------------------------------------------
function M.piomon(args_table)
  local term = require('nvimpio.device.terminal')
  local command = nil
  if #args_table == 0 then
    command = 'pio device monitor'
  elseif #args_table == 1 then
    local baud_rate = args_table[1]
    command = string.format('pio device monitor -b %s', baud_rate)
  elseif #args_table == 2 then
    local baud_rate = args_table[1]
    local port = args_table[2]
    command = string.format('pio device monitor -b %s -p %s', baud_rate, port)
  end

  if command == nil then
    OS.notify('Usage: Piomon <baud> <port>', 'error')
  else
    vim.schedule(function()
      term.mon:send(command)
    end)
    -- term.mon:send(command)
  end
end

--INFO: Piorun
------------------------------------------------------
function M.piobuild()
  local term = require('nvimpio.device.terminal')
  local command = 'pio run'
  term.cli:send(command)
end

function M.pioupload()
  local term = require('nvimpio.device.terminal')
  local command = 'pio run --target upload'
  term.cli:send(command)
end

function M.piouploadfs()
  local term = require('nvimpio.device.terminal')
  local command = 'pio run --target uploadfs'
  term.cli:send(command)
end

function M.pioclean()
  local term = require('nvimpio.device.terminal')
  local command = 'pio run --target clean'
  term.cli:send(command)
end

function M.piorun(arg_table)
  if arg_table[1] == '' then
    M.piobuild()
  elseif arg_table[1] == 'upload' then
    M.pioupload()
  elseif arg_table[1] == 'uploadfs' then
    M.piouploadfs()
  elseif arg_table[1] == 'build' then
    M.piobuild()
  elseif arg_table[1] == 'clean' then
    M.pioclean()
  else
    OS.notify('Invalid argument: build, upload, uploadfs or clean', 'warn')
  end
end
-- stylua: ignore end

return M
