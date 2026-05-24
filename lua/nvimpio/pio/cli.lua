local M = {}

local ToggleTerminal = require('nvimpio.utils.term').ToggleTerminal
local misc = require('nvimpio.utils.misc')

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
        OS.notify(string.format('%s build idedata success for %s.', from, active_env), 'info')
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
  active_env = active_env or _G.metadata.active_env
  vim.system({ 'pio', 'run', '-t', 'compiledb', '-e', active_env }, { timeout = 60000,  text = true }, function(obj)
    vim.schedule(function()
      local ok = (obj.code == 0)
      if ok then
        OS.notify(string.format('%s build compiledb success for %s.', from, active_env), 'info')
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

  if cmd_table[1] == '' then ToggleTerminal('', direction)
  else
    local cmd = 'pio '
    for _, v in pairs(cmd_table) do cmd = cmd .. ' ' .. v end
    ToggleTerminal(cmd, direction)
  end
end

--INFO: Piodebug
------------------------------------------------------
function M.piodebug(args_table)
  if not misc.pio_install_check() then return end

  local command = 'pio debug --interface=gdb -- -x .pioinit'
  -- local command = string.format('pio debug --interface=gdb -- -x .pioinit %s', utils.extra)
  ToggleTerminal(command, 'float')
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
  else ToggleTerminal(command, 'horizontal') end
end

--INFO: Piorun
------------------------------------------------------
function M.piobuild()
  local command = 'pio run' -- .. utils.extra
  ToggleTerminal(command, 'float')
end

function M.pioupload()
  local command = 'pio run --target upload' -- .. utils.extra
  ToggleTerminal(command, 'float')
end

function M.piouploadfs()
  local command = 'pio run --target uploadfs' -- .. utils.extra
  ToggleTerminal(command, 'float')
end

function M.pioclean()
  local command = 'pio run --target clean' -- .. utils.extra
  ToggleTerminal(command, 'float')
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
