local pio = require('nvimpio.pio.upkeep')

local M = {}

-- Interactive Environment Selection Panel
function M.select_env_picker()
  -- 1. Trigger JIT parsing to ensure _G.metadata state is completely fresh and populated
  local current_active = pio.get_active_env('UI Picker: ')

  -- Safety guard: Exit gracefully if platformio.ini was missing or empty
  if not current_active or not _G.metadata or not _G.metadata.envs then
    return
  end

  local display_options = {}
  local lookup_map = {}

  -- 2. Extract hardware keys directly out of our consolidated object dictionary
  for env_name, _ in pairs(_G.metadata.envs) do
    -- Active choice = Filled Circle (●), Available options = Empty Circle (○)
    local icon = (env_name == current_active) and '● ' or '○ '
    local row_text = string.format('%s%s', icon, env_name)

    table.insert(display_options, row_text)
    lookup_map[row_text] = env_name -- Maps the decorative UI row string back to the raw key
  end

  -- 3. Alphabetically sort display items so the picker rendering looks uniform
  table.sort(display_options)

  -- 4. Pass everything down to Neovim's native floating selection wrapper
  vim.ui.select(display_options, {
    prompt = ' Select Active Hardware Target ',
    kind = 'nvimpio_env_selector',
  }, function(choice)
    if not choice then
      return
    end -- Gracefully handle user escape or cancel events (ESC)

    local chosen_env = lookup_map[choice]
    if chosen_env then
      -- Commit choice to global reactive metadata register
      _G.metadata.active_env = chosen_env

      OS.notify(string.format('PlatformIO active_env swapped -> %s', chosen_env), 'info')
    end
  end)
end

return M
