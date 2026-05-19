local pio = require('nvimpio.pio.upkeep')
local M = {}

function M.select_env_picker()
  local current_active = pio.get_active_env('UI Picker: ')
  if not current_active or not _G.metadata or not _G.metadata.envs then
    return
  end

  -- 1. Build an optimized, numbered menu list using basic brackets
  local menu_lines = { '--- Select Active Target Environment ---' }
  local envs = {}
  for name, _ in pairs(_G.metadata.envs) do
    table.insert(envs, name)
  end
  table.sort(envs)

  for idx, name in ipairs(envs) do
    local checkbox = (name == current_active) and '[x]' or '[ ]'
    table.insert(menu_lines, string.format('%d. %s %s', idx, checkbox, name))
  end

  -- 2. Trigger Neovim's native selection engine instantly
  -- Users just tap numbers (1, 2, 3) or use arrows to select a board!
  local choice = vim.fn.inputlist(menu_lines)
  if choice > 0 and choice <= #envs then
    _G.metadata.active_env = envs[choice]
    vim.cmd('redrawstatus') -- Swaps your statusline indicators immediately
    OS.notify(string.format('PlatformIO target swapped -> %s', envs[choice]), 'info')
  end
end
return M
