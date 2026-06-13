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
        width = 0.7,
        preview_width = 0.60,
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

      previewer = previewers.new_buffer_previewer({
        title = 'Board Details',
        define_preview = function(self, entry)
          -- 1. Atomic Window Guard (Blocks late async resize race condition crashes)
          if not self.state or not self.state.winid or not vim.api.nvim_win_is_valid(self.state.winid) then return end

          -- 2. Clean out empty internal dict proxies from the data object
          local function clean(t)
            if type(t) ~= "table" then return t end
            if rawequal(t, vim.empty_dict) then return nil end
            local res = {}
            for k, v in pairs(t) do res[k] = clean(v) end
            return res
          end

          -- 3. Industry Trick: Encode to clean JSON text and split it into an array of lines
          local board_data = clean(entry.value)
          local content = vim.split(vim.json.encode(board_data), "\n")

          -- Beautify and pretty-print the JSON using a quick internal indentation formatter
          content = vim.split(vim.inspect(board_data), "\n")

          -- 4. Direct Safe Injection to Telescope Viewport
          if vim.api.nvim_buf_is_valid(self.state.bufnr) then
            vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, content)

            -- Setting the filetype to 'lua' or 'json' lets Neovim color the brackets,
            -- strings, and numbers perfectly using the user's active theme.
            vim.api.nvim_set_option_value('filetype', 'lua', { buf = self.state.bufnr })
          end
        end,
      }),
      -- previewer = previewers.new_buffer_previewer({
      --   title = 'Board Details',
      --   define_preview = function(self, entry)
      --     -- 1. WINDOW HANDLE VALVE: Guard against late async callbacks during active resizes
      --     if not self.state or not self.state.winid or not vim.api.nvim_win_is_valid(self.state.winid) then
      --       return
      --     end
      --
      --     local b = entry.value
      --     local lines = { " 📋 " .. (b.name or "Unknown Board"), " ──────────────────────────────────────" }
      --     local specs = {}
      --
      --     -- 2. DYNAMIC FLAT PARSER: Automatically extract every property key in the JSON root
      --     for k, v in pairs(b) do
      --       -- Skip complex arrays because they display below in lists
      --       if k ~= "frameworks" and k ~= "connectivity" and k ~= "debug" and k ~= "name" then
      --         if type(v) ~= "table" and v ~= nil and v ~= "" and not rawequal(v, vim.empty_dict) then
      --           -- Format and capitalize the key dynamically (e.g., "mcu" -> "Mcu")
      --           local label = k:sub(1,1):upper() .. k:sub(2)
      --
      --           -- Format big clock numbers nicely
      --           if label == "Fcpu" and tonumber(v) then
      --             local num = tostring(v)
      --             while true do
      --               local new_num, k_sub = string.gsub(num, "^(-?%d+)(%d%d%d)", '%1 %2')
      --               if k_sub == 0 then break end
      --               num = new_num
      --             end
      --             v = num .. " Hz"
      --           end
      --           table.insert(specs, { label = label, val = tostring(v) })
      --
      --         -- Flatten second-level vendor metadata objects (Flash, RAM, etc.)
      --         elseif k == "vendor" and type(v) == "table" then
      --           for vk, vv in pairs(v) do
      --             if type(vv) ~= "table" and vv ~= "" and not rawequal(vv, vim.empty_dict) then
      --               local label = "Vendor " .. vk:sub(1,1):upper() .. vk:sub(2)
      --               table.insert(specs, { label = label, val = tostring(vv) })
      --             end
      --           end
      --         end
      --       end
      --     end
      --
      --     -- 3. DYNAMIC WIRELESS EXTRACTION: Read connectivity lists for flags on the fly
      --     local conn_str = type(b.connectivity) == "table" and table.concat(b.connectivity, " "):lower() or tostring(b.connectivity or ""):lower()
      --     if conn_str ~= "" then
      --       table.insert(specs, { label = "Wi-Fi",     val = (conn_str:match("wifi") or conn_str:match("wireless")) and "Yes" or "-" })
      --       table.insert(specs, { label = "Bluetooth", val = (conn_str:match("blue") or conn_str:match("ble")) and "Yes" or "-" })
      --     end
      --
      --     -- Sort alphabetically so fields don't jump around randomly when navigating boards
      --     table.sort(specs, function(a, b_item) return a.label < b_item.label end)
      --
      --     -- 4. COLUMN WIDTH TRACKER: Calculate alignment dynamically based on discovered keys
      --     local max_len = 0
      --     for _, s in ipairs(specs) do max_len = math.max(max_len, string.len(s.label)) end
      --     local format_str = string.format("  %%-%ds │  %%s", max_len)
      --
      --     for _, s in ipairs(specs) do
      --       table.insert(lines, string.format(format_str, s.label, s.val))
      --     end
      --
      --     -- 5. Safe Multi-line List Appender Helper
      --     local function add_list(title, data)
      --       if data and not rawequal(data, vim.empty_dict) and (type(data) ~= "table" or not vim.tbl_isempty(data)) then
      --         table.insert(lines, "")
      --         table.insert(lines, " " .. title)
      --         table.insert(lines, " ──────────────────────────────────────")
      --         for _, item in ipairs(type(data) == "table" and data or { data }) do
      --           table.insert(lines, "   • " .. tostring(item))
      --         end
      --       end
      --     end
      --
      --     add_list("🛠️  Supported Frameworks", b.frameworks)
      --     add_list("🔌  Debug Protocols", b.debug and b.debug.protocols)
      --     add_list("📡  Connectivity Variants", b.connectivity)
      --
      --     -- 6. ATOMIC WRITE GATEWAY: Direct render to Telescope buffer
      --     if vim.api.nvim_win_is_valid(self.state.winid) and vim.api.nvim_buf_is_valid(self.state.bufnr) then
      --       vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, lines)
      --       vim.api.nvim_set_option_value('filetype', 'help', { buf = self.state.bufnr })
      --     end
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
