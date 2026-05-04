local M = {}

-- local misc = require('nvimpio.utils.misc')
local ToggleTerminal = require('nvimpio.utils.term').ToggleTerminal
local misc = vim.misc

-- stylua: ignore
--INFO: PioLSP
------------------------------------------------------
function M.clangdRestart()
  require('nvimpio.clangd.tools').clangdRestart()
end

-- stylua: ignore
--INFO: Piocmd(h/f)
------------------------------------------------------
function M.piocmd(cmd_table, direction)
  if not misc.pio_install_check() then return end

  misc.cd_pioini()

  if cmd_table[1] == '' then ToggleTerminal('', direction)
  else
    local cmd = 'pio '
    for _, v in pairs(cmd_table) do cmd = cmd .. ' ' .. v end
    ToggleTerminal(cmd, direction)
  end
end

-- stylua: ignore
--INFO: Piodebug
------------------------------------------------------
function M.piodebug(args_table)
  if not misc.pio_install_check() then return end

  misc.cd_pioini()

  local command = 'pio debug --interface=gdb -- -x .pioinit'
  -- local command = string.format('pio debug --interface=gdb -- -x .pioinit %s', utils.extra)
  ToggleTerminal(command, 'float')
end

-- stylua: ignore
--INFO: Piomon
------------------------------------------------------
function M.piomon(args_table)
  if not misc.pio_install_check() then return end

  misc.cd_pioini()

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

  if command == nil then vim.notify('Usage: Piomon <baud> <port>', vim.log.levels.ERROR)
  else ToggleTerminal(command, 'horizontal') end
end

-- stylua: ignore
--INFO: Piorun
------------------------------------------------------
function M.piobuild()
  misc.cd_pioini()
  local command = 'pio run' -- .. utils.extra
  ToggleTerminal(command, 'float')
end

function M.pioupload()
  misc.cd_pioini()
  local command = 'pio run --target upload' -- .. utils.extra
  ToggleTerminal(command, 'float')
end

function M.piouploadfs()
  misc.cd_pioini()
  local command = 'pio run --target uploadfs' -- .. utils.extra
  ToggleTerminal(command, 'float')
end

function M.pioclean()
  misc.cd_pioini()
  local command = 'pio run --target clean' -- .. utils.extra
  ToggleTerminal(command, 'float')
end

function M.piorun(arg_table)
  if not misc.pio_install_check() then
    return
  end
  if arg_table[1] == '' then
    M.pioupload()
  elseif arg_table[1] == 'upload' then
    M.pioupload()
  elseif arg_table[1] == 'uploadfs' then
    M.piouploadfs()
  elseif arg_table[1] == 'build' then
    M.piobuild()
  elseif arg_table[1] == 'clean' then
    M.pioclean()
  else
    vim.notify('Invalid argument: build, upload, uploadfs or clean', vim.log.levels.WARN)
  end
end

return M
