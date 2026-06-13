-- stylua: ignore start
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
  -- local pio = require('nvimpio.pio.upkeep')
  local parser = require('nvimpio.device.parser')

  local sample_flag = '' --wizard_data.sample == 'Yes' and ' --sample-code' or ''
  local init_cmd = string.format('pio project init --board %s -O "framework=%s" %s', wizard_data.board_id, wizard_data.framework, sample_flag)
  -- local db_cmd = string.format('pio run -t compiledb -e %s', wizard_data.board_id)
  -- local commands = { init_cmd, db_cmd }
  local commands = { init_cmd }

  local final_cb = function(status)
    parser.handlePioinit(status, wizard_data.board_id, wizard_data.on_done)
  end

  OS.notify('Pioinit: Starting project setup for ' .. wizard_data.board_id .. '...')
  parser.run_sequence({ cmnds = commands, cb = final_cb, from = 'Pioinit: ' })
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
        preview_cutoff = 120,
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
          local b = entry.value
          local lines = { " 📋 " .. (b.name or "Unknown Board"), " ──────────────────────────────────────" }

          -- Flatten deeply nested metadata structures into single-depth rows
          local properties = {}
          local function extract_all_properties(t, prefix)
            if type(t) ~= "table" or rawequal(t, vim.empty_dict) then return end
            prefix = prefix or ""

            for k, v in pairs(t) do
              -- Ignore frameworks and debugging protocols here as they display below in lists
              if k ~= "frameworks" and k ~= "protocols" and k ~= "connectivity" then
                local label = prefix .. k:sub(1,1):upper() .. k:sub(2)
                if type(v) == "table" and not vim.tbl_isempty(v) then
                  extract_all_properties(v, label .. " ")
                elseif type(v) ~= "table" and v ~= nil and v ~= "" and not rawequal(v, vim.empty_dict) then
                  table.insert(properties, { label = label, val = tostring(v) })
                end
              end
            end
          end

          -- 1. Recursively digest the entire JSON object payload
          extract_all_properties(b)

          -- 2. SMART DELIMITER: Dynamically calculate padding based on the longest key name discovered
          local max_len = 0
          for _, p in ipairs(properties) do max_len = math.max(max_len, string.len(p.label)) end
          local format_str = string.format("  %%-%ds │  %%s", max_len)

          -- 3. Append all formatted, perfectly-aligned core data variables
          for _, p in ipairs(properties) do
            -- Format large numbers like CPU clock frequencies nicely with spaces
            if p.label:match("Fcpu") and tonumber(p.val) then
              p.val = tostring(p.val):gsub("^(-?%d+)(%d%d%d)", "%1 %2") .. " Hz"
            end
            table.insert(lines, string.format(format_str, p.label, p.val))
          end

          -- 4. Helper to append array list components as distinct sub-blocks
          local function add_list(title, data)
            if data and not rawequal(data, vim.empty_dict) and (type(data) ~= "table" or not vim.tbl_isempty(data)) then
              table.insert(lines, "") -- Safe empty spacing row
              table.insert(lines, " " .. title)
              table.insert(lines, " ──────────────────────────────────────")
              for _, item in ipairs(type(data) == "table" and data or { data }) do
                table.insert(lines, "   • " .. tostring(item))
              end
            end
          end

          add_list("🛠️  Supported Frameworks", b.frameworks)
          add_list("🔌  Debug Protocols", b.debug and b.debug.protocols)
          add_list("📡  Connectivity Options", b.connectivity)

          -- 5.Added safety check to verify buffer and window stability during resizes
          if self.state and self.state.bufnr and vim.api.nvim_buf_is_valid(self.state.bufnr) then
            -- Verify that the window id is still active before doing anything
            if self.state.winid and vim.api.nvim_win_is_valid(self.state.winid) then

              -- Perform the write operation safely
              vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, lines)
              vim.api.nvim_set_option_value('filetype', 'help', { buf = self.state.bufnr })

            end
          end
        end,
      }),
      -- previewer = previewers.new_buffer_previewer({
      --   title = 'Board Details',
      --   define_preview = function(self, entry)
      --     local board = entry.value
      --     local lines = {
      --       ' 📋 ' .. (board.name or 'Unknown Board'),
      --       ' ──────────────────────────────────────────────────',
      --     }
      --
      --     -- 1. Gather all core properties into a clean raw array
      --     local raw_specs = {
      --       { label = 'Board ID', val = board.id },
      --       { label = 'Platform', val = board.platform },
      --       { label = 'MCU Type', val = board.mcu },
      --     }
      --
      --     -- Parse frequency with clean space separators
      --     if board.fcpu then
      --       local formatted_num = tostring(board.fcpu)
      --       while true do
      --         local new_num, k = string.gsub(formatted_num, '^(-?%d+)(%d%d%d)', '%1 %2')
      --         if k == 0 then
      --           break
      --         end
      --         formatted_num = new_num
      --       end
      --       table.insert(raw_specs, { label = 'Frequency', val = formatted_num .. ' Hz' })
      --     end
      --
      --     -- Append vendor storage specs if they exist
      --     if board.vendor then
      --       if board.vendor.flash then
      --         table.insert(raw_specs, { label = 'Flash Size', val = board.vendor.flash })
      --       end
      --       if board.vendor.ram then
      --         table.insert(raw_specs, { label = 'RAM Size', val = board.vendor.ram })
      --       end
      --     end
      --
      --     -- 2. SMART DELIMITER: Find the length of the longest label to calculate padding width
      --     local max_label_len = 0
      --     for _, spec in ipairs(raw_specs) do
      --       if spec.val and not rawequal(spec.val, vim.empty_dict) then
      --         max_label_len = math.max(max_label_len, string.len(spec.label))
      --       end
      --     end
      --
      --     -- 3. Build perfectly aligned property rows
      --     for _, spec in ipairs(raw_specs) do
      --       local val = spec.val
      --       if val and not rawequal(val, vim.empty_dict) and (type(val) ~= 'table' or not vim.tbl_isempty(val)) then
      --         -- Calculate exact space padding needed for this specific row
      --         local padding = string.rep(' ', max_label_len - string.len(spec.label))
      --         table.insert(lines, string.format('  %s%s  │  %s', spec.label, padding, tostring(val)))
      --       end
      --     end
      --
      --     table.insert(lines, '') -- Visual break separator
      --
      --     -- Helper function to render arrays/tables safely into clean bullet lists
      --     local function append_list_section(title, data)
      --       if not data or rawequal(data, vim.empty_dict) or (type(data) == 'table' and vim.tbl_isempty(data)) then
      --         return
      --       end
      --       table.insert(lines, ' ' .. title)
      --       table.insert(lines, ' ──────────────────────────────────────')
      --       if type(data) == 'table' then
      --         for _, item in ipairs(data) do
      --           table.insert(lines, '   • ' .. tostring(item))
      --         end
      --       else
      --         table.insert(lines, '   • ' .. tostring(data))
      --       end
      --       table.insert(lines, '') -- Trailing section space divider
      --     end
      --
      --     -- 4. Append nested layouts cleanly as distinct sub-blocks
      --     append_list_section('🛠️  Supported Frameworks', board.frameworks)
      --     append_list_section('🔌  Debug Protocols', board.debug and board.debug.protocols)
      --     append_list_section('📡  Connectivity Options', board.connectivity)
      --
      --     -- 5. Flush the generated strings directly into the telescope preview buffer
      --     vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, lines)
      --
      --     -- Swapping to 'help' filetype loads a minimalist text renderer with beautiful boundary markers
      --     vim.api.nvim_set_option_value('filetype', 'help', { buf = self.state.bufnr })
      --   end,
      -- }),
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
