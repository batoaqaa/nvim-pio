local pio = require('nvimpio.pio.upkeep')
local M = {}
function M.select_env_picker()
  -- Assume your engine populated _G.metadata.envs with your target table
  if not _G.metadata or not _G.metadata.envs then
    return
  end
  local current_active = _G.metadata.active_env

  -- 1. EXTRACT KEYS: Use pairs() to harvest the environment board names
  local envs = {}
  for env_name, _ in pairs(_G.metadata.envs) do
    table.insert(envs, env_name)
  end
  table.sort(envs) -- Alphabetical sort for UI presentation

  -- 2. Build the Centered Dropdown GUI Theme Geometry
  local theme = require('telescope.themes').get_dropdown({
    prompt_title = 'Select Environment',
    results_title = 'Available Boards', -- Forces the window open, preventing collapsing bugs!
    layout_config = { width = 38, height = #envs + 3 },
    borderchars = {
      prompt = { ' ', ' ', ' ', ' ', ' ', ' ', ' ', ' ' },
      results = { '─', '│', '─', '│', '╭', '╮', '╯', '╰' },
      preview = { '─', '│', '─', '│', '╭', '╮', '╯', '╰' },
    },
  })

  -- 3. Execute the standard Telescope Dialogue Window Card
  require('telescope.pickers')
    .new(theme, {
      initial_mode = 'insert', -- Immediate normal mode blocks command line typing inputs
      finder = require('telescope.finders').new_table({
        results = envs,
        entry_maker = function(name)
          local idx = vim.fn.index(envs, name) + 1
          local checkbox = (name == current_active) and '[x]' or '[ ]' -- Universal font-safe format
          return { value = name, display = string.format(' %d. %s %s', idx, checkbox, name), ordinal = name }
        end,
      }),
      sorter = require('telescope.config').values.generic_sorter(theme),
      attach_mappings = function(prompt_bufnr, map)
        local make_selection = function()
          local selection = require('telescope.actions.state').get_selected_entry()
          require('telescope.actions').close(prompt_bufnr)
          if selection then
            _G.metadata.active_env = selection.value
            vim.cmd('redrawstatus') -- Swaps your statusline indicators immediately
            OS.notify(string.format('PlatformIO target swapped -> %s', selection.value), 'info')
          end
        end
        map('n', '<CR>', make_selection)
        map('n', '<Space>', make_selection)

        -- Map Number Keys (1, 2, 3...) to trigger instant target updates
        for idx = 1, math.min(#envs, 9) do
          map('n', tostring(idx), function()
            require('telescope.actions.state').get_current_picker(prompt_bufnr):set_selection(idx - 1)
            make_selection()
          end)
        end
        return true
      end,
    })
    :find()
end

return M
