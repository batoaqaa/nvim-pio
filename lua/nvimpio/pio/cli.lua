local M = {}

local pio_mon = require('nvimpio.device.terminal').mon
local pio_cli = require('nvimpio.device.terminal').cli
local function sendCmnd(command)
  -- Directly pull the raw pointer reference from the table object.
  -- 0% CPU cycles wasted running window layout functions! [INDEX]

  -- The custom internal Lazy-Spawn Guard takes care of everything!
  -- If it's closed, it opens it. If it's open, it pipes it straight down! [INDEX]
  -- pio_cli:show()
  pio_cli:send(command)
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
function M.buildIdedata(from, active_env, cb)
  vim.system({ 'pio', 'run', '-t', 'idedata', '-e', active_env, '-s' }, { timeout = 60000, text = true }, function(obj)
    vim.schedule(function()
      local ok = (obj.code == 0)
      if ok then
        OS.notify(string.format('%sbuild idedata success for %s.', from, active_env), 'info')
      else
        notify_system_error(from, string.format('build idedata for %s failed: ', active_env), obj)
      end

      if cb and type(cb) == "function" then cb(ok) end
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

--INFO: Piocli
------------------------------------------------------
function M.piocli(cmd_table)
  local cmd = (cmd_table[1] == '') and '' or ('pio ' .. table.concat(cmd_table, ' '))
  if cmd ~= '' then sendCmnd(cmd)
  else pio_cli:show() end
end

--INFO: Piodebug
------------------------------------------------------
function M.piodebug(_)
  local command = 'pio debug --interface=gdb -- -x .pioinit'
  sendCmnd(command)
end

--INFO: Piomon
------------------------------------------------------
function M.piomon(args_table)
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

  if command == nil then OS.notify('Usage: Piomon <baud> <port>', "error")
  else pio_mon:send(command) end
end

--INFO: Piorun
------------------------------------------------------
function M.piobuild()
  local command = 'pio run'
  sendCmnd(command)
end

function M.pioupload()
  local command = 'pio run --target upload'
  sendCmnd(command)
end

function M.piouploadfs()
  local command = 'pio run --target uploadfs'
  sendCmnd(command)
end

function M.pioclean()
  local command = 'pio run --target clean'
  sendCmnd(command)
end

function M.piorun(arg_table)
  if arg_table[1] == '' then M.piobuild()
  elseif arg_table[1] == 'upload' then M.pioupload()
  elseif arg_table[1] == 'uploadfs' then M.piouploadfs()
  elseif arg_table[1] == 'build' then M.piobuild()
  elseif arg_table[1] == 'clean' then M.pioclean()
  else vim.misc.notify('Invalid argument: build, upload, uploadfs or clean', 'warn') end
end
-- stylua: ignore end

return M
