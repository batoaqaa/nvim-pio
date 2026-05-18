local pickers = require('telescope.pickers')
local finders = require('telescope.finders')
local actions = require('telescope.actions')
local action_state = require('telescope.actions.state')
local previewers = require('telescope.previewers')
local telescope_conf = require('telescope.config').values
local themes = require('telescope.themes')

local wizard_data = {}

-- -- Visual Notifications
-- local function notify(msg, level)
--   local misc = require('nvimpio.utils.misc')
--   misc.notify('PIO init+db: ' .. msg, level or 'info')
-- end

-- Reusable Small Menu for Yes/No and Frameworks
local function small_menu(title, results, callback)
  pickers
    .new(
      themes.get_dropdown({
        prompt_title = title,
        layout_config = { width = 0.3, height = 0.25 },
        previewer = false,
      }),
      {
        finder = finders.new_table({ results = results }),
        sorter = telescope_conf.generic_sorter({}),
        attach_mappings = function(prompt_bufnr)
          actions.select_default:replace(function()
            local selection = action_state.get_selected_entry()
            actions.close(prompt_bufnr)
            if selection then
              callback(selection[1])
            end
          end)
          return true
        end,
      }
    )
    :find()
end

-- FINAL STEP: Construction & Sequence Execution
local function finalize_setup()
  local pio = require('nvimpio.pio.upkeep')

  local sample_flag = '' --wizard_data.sample == 'Yes' and ' --sample-code' or ''
  local init_cmd = string.format('pio project init --board %s -O "framework=%s" %s', wizard_data.board_id, wizard_data.framework, sample_flag)
  -- local db_cmd = string.format('pio run -t compiledb -e %s', wizard_data.board_id)
  -- local commands = { init_cmd, db_cmd }
  local commands = { init_cmd }

  local final_cb = function(status)
    pio.handlePioinit(status, wizard_data.board_id, wizard_data.on_done)
  end

  OS.notify('Starting project setup for ' .. wizard_data.board_id .. '...')
  pio.run_sequence({ cmnds = commands, cb = final_cb })
end

--- SEQUENTIAL STEPS ---

-- Step 4: CompileDB
-- local function pick_compiledb()
--   small_menu('Generate Compilation Database (LSP)?', { 'Yes', 'No' }, function(choice)
--     wizard_data.use_compiledb = choice
--     finalize_setup()
--   end)
-- end

-- Step 3: Sample Code
-- local function pick_sample()
--   small_menu('Include Sample Code?', { 'Yes', 'No' }, function(choice)
--     wizard_data.sample = choice
--     -- pick_compiledb()
--     finalize_setup()
--   end)
-- end

-- Step 2: Framework
local function pick_framework(board_details)
  small_menu('Select Framework', board_details.frameworks, function(choice)
    wizard_data.framework = choice
    -- pick_sample()
    finalize_setup()
  end)
end

-- Step 1: Board (Entry Point)
local function pick_board(json_data)
  pickers
    .new({}, {
      prompt_title = 'Select Board',
      -- Define the layout behavior
      layout_strategy = 'horizontal',
      layout_config = {
        width = 0.9, -- Overall width of the Telescope window (90% of screen)
        preview_width = 0.70, -- 65% of the window goes to "Board Details", leaving 25% for results
      },
      finder = finders.new_table({
        results = json_data,
        entry_maker = function(entry)
          return {
            value = entry,
            display = entry.name or entry.id,
            ordinal = (entry.name or '') .. ' ' .. (entry.id or ''),
          }
        end,
      }),
      previewer = previewers.new_buffer_previewer({
        title = 'Board Details',
        define_preview = function(self, entry)
          local content = vim.split(vim.inspect(entry.value), '\n')
          vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, content)
          vim.api.nvim_set_option_value('filetype', 'lua', { buf = self.state.bufnr })
        end,
      }),
      sorter = telescope_conf.generic_sorter({}),
      attach_mappings = function(prompt_bufnr)
        actions.select_default:replace(function()
          local selection = action_state.get_selected_entry()
          actions.close(prompt_bufnr)
          if selection then
            wizard_data.board_id = vim.trim(selection.value.id)
            pick_framework(selection.value)
          end
        end)
        return true
      end,
    })
    :find()
end

-- Entry point
local function launch_project_init(on_done)
  wizard_data = {} -- Reset state

  if on_done and type(on_done) == 'function' then
    wizard_data.on_done = on_done
  end
  OS.notify('Fetching board database...')

  local handle = io.popen('pio boards --json-output')
  if not handle then
    return
  end
  local result = handle:read('*a')
  handle:close()

  local ok, json_data = pcall(vim.json.decode, result)
  if not ok or type(json_data) ~= 'table' then
    OS.notify('Failed to parse board data.', 'error')
    return
  end

  pick_board(json_data)
end

return {
  pioInit = launch_project_init,
}
