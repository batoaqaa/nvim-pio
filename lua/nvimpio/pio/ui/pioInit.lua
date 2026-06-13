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
-- local function pick_board(json_data)
--   pickers
--     .new({}, {
--       prompt_title = 'Select Board',
--       -- Define the layout behavior
--       layout_strategy = 'horizontal',
--       layout_config = {
--         width = 0.9, -- Overall width of the Telescope window (90% of screen)
--         preview_width = 0.70, -- 65% of the window goes to "Board Details", leaving 25% for results
--         preview_cutoff = 120,
--       },
--       finder = finders.new_table({
--         results = json_data,
--         entry_maker = function(entry)
--           return {
--             value = entry,
--             display = entry.name or entry.id,
--             ordinal = (entry.name or '') .. ' ' .. (entry.id or ''),
--           }
--         end,
--       }),

-- Step 1: Board (Entry Point)
local function pick_board(json_data)
  -- 1. Deduplicate the source json array cleanly before feeding it to Telescope
  local unique_boards = {}
  local seen_ids = {}
  for _, board in ipairs(json_data) do
    if board.id and not seen_ids[board.id] then
      seen_ids[board.id] = true
      table.insert(unique_boards, board)
    end
  end

  pickers
    .new({}, {
      prompt_title = 'Select Board',
      layout_strategy = 'horizontal',
      layout_config = {
        width = 0.9,
        preview_width = 0.70,
        preview_cutoff = 120,
      },
      finder = finders.new_table({
        results = unique_boards, -- Use the deduplicated table array
        entry_maker = function(entry)
          -- 2. Strictly define distinct values to prevent caching row overlaps
          local board_name = entry.name or entry.id
          return {
            value = entry,
            display = board_name,
            -- Enforcing an explicit unique identifier prevents row duplication bugs!
            ordinal = string.format("%s %s", tostring(board_name), tostring(entry.id)),
            id = entry.id,
          }
        end,
      }),
      -- ... Keep your uncrashable previewer section exactly as it is ...
      previewer = previewers.new_buffer_previewer({
        title = 'Board Details',
        define_preview = function(self, entry)
          -- 1. CRITICAL SAFETY GUARD: Instantly bail out if Telescope's core 
          -- window handles are invalidated mid-resize before doing any allocations
          if not self.state or not self.state.winid or vim.api.nvim_win_is_valid(self.state.winid) == false then
            return
          end

          local b = entry.value
          local lines = { " 📋 " .. (b.name or "Unknown Board"), " ──────────────────────────────────────" }

          -- 2. Structured Layout Mapping Strategy (Fastest Execution Profile)
          local function add(label, val)
            if val and not rawequal(val, vim.empty_dict) and val ~= "" then
              table.insert(lines, string.format("  %-14s │  %s", label, tostring(val)))
            end
          end

          add("Board ID",     b.id)
          add("Platform",     b.platform)
          add("MCU Type",     b.mcu)
          add("Vendor",       b.vendor and b.vendor.name)
          add("Flash Size",   b.vendor and b.vendor.flash)
          add("RAM Size",     b.vendor and b.vendor.ram)
          add("URL Documentation", b.url)

          -- Format big CPU numbers using native string patterns safely
          if b.fcpu then
            local freq = tostring(b.fcpu):gsub("^(-?%d+)(%d%d%d)", "%1 %2") .. " Hz"
            add("Frequency", freq)
          end

          -- Extract Wireless parameters via lightning-fast local scan loop
          local conn_str = tostring(b.connectivity or ""):lower()
          local has_wifi = conn_str:match("wifi") or conn_str:match("wireless")
          local has_ble  = conn_str:match("blue") or conn_str:match("ble")
          add("Wi-Fi",     has_wifi and "Yes" or nil)
          add("Bluetooth", has_ble and "Yes" or nil)

          -- 3. Array List Components Assembly Helper
          local function add_list(title, data)
            if data and not rawequal(data, vim.empty_dict) and (type(data) ~= "table" or not vim.tbl_isempty(data)) then
              table.insert(lines, "")
              table.insert(lines, " " .. title)
              table.insert(lines, " ──────────────────────────────────────")
              for _, item in ipairs(type(data) == "table" and data or { data }) do
                table.insert(lines, "   • " .. tostring(item))
              end
            end
          end

          add_list("🛠️  Supported Frameworks", b.frameworks)
          add_list("🔌  Debug Protocols", b.debug and b.debug.protocols)

          -- 4. FINAL SAFETY LOCK: Double-verify window state handles a final time 
          -- right before executing the core buffer modifications
          if vim.api.nvim_win_is_valid(self.state.winid) and vim.api.nvim_buf_is_valid(self.state.bufnr) then
            vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, lines)
            vim.api.nvim_set_option_value('filetype', 'help', { buf = self.state.bufnr })
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
