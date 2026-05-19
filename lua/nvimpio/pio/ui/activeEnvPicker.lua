local pio = require('nvimpio.pio.upkeep')
local M = {}

function M.select_env_picker()
  -- Assume your engine populated _G.metadata.envs with your target table
  if not _G.metadata or not _G.metadata.envs then
    return
  end
  -- local current_active = _G.metadata.active_env
  local current_active = pio.get_active_env('UI Picker: ')

  -- 1. EXTRACT KEYS: Use pairs() to harvest the environment board names
  local envs = {}
  for env_name, _ in pairs(_G.metadata.envs) do
    table.insert(envs, env_name)
  end
  table.sort(envs) -- Alphabetical sort for UI presentation

  -- 2. Build the Centered Dropdown GUI Theme Geometry
  local theme = require('telescope.themes').get_dropdown({
    prompt_title = 'Select Environment',
    results_title = 'Available Boards',

    -- ADJUSTMENT 1: Increase the height container envelope size multiplier!
    -- Changing this to #envs + 5 or #envs + 6 gives the window plenty of extra row lines.
    layout_config = {
      width = 38,
      height = #envs + 5,
    },

    -- ADJUSTMENT 2: Restore the top framing borders of the prompt container window canopy.
    -- Wiping these entirely causes the dropdown engine to collapse internal height spaces.
    borderchars = {
      prompt = { '─', '│', ' ', '│', '╭', '╮', '│', '│' },
      results = { '─', '│', '─', '│', '├', '┤', '╯', '╰' },
      preview = { '─', '│', '─', '│', '╭', '╮', '╯', '╰' },
    },
  })

  -- 3. Execute the standard Telescope Dialogue Window Card
  require('telescope.pickers')
    .new(theme, {
      initial_mode = 'insert',
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

        -- Map normal mode keys
        map('n', '<CR>', make_selection)
        map('n', '<Space>', make_selection)

        -- Map insert mode keys (Since your config sets initial_mode = 'insert'!)
        map('i', '<CR>', make_selection)

        -- Map Number Keys (1, 2, 3...) to trigger instant target updates
        -- Added both normal ('n') and insert ('i') support so typing numbers jumps instantly!
        for idx = 1, math.min(#envs, 9) do
          local handler = function()
            require('telescope.actions.state').get_current_picker(prompt_bufnr):set_selection(idx - 1)
            make_selection()
          end
          map('n', tostring(idx), handler)
          map('i', tostring(idx), handler)
        end
        return true
      end,
    })
    :find()
end
return M
