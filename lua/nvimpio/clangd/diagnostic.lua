-- --- stylua: ignore start
-- local M = {}
--
-- -- Explicit table instantiation at the absolute top prevents race-condition crashes
-- M.manual_blocked_codes = {}
--
-- local root_markers = { 'platformio.ini', '.git' }
--
-- -- 1. GET_DB_PATH: Dynamically resolves project workspace paths in memory space
-- local function get_db_path(bufnr)
--   bufnr = (bufnr and bufnr ~= 0) and bufnr or vim.api.nvim_get_current_buf()
--   local buf_file = vim.api.nvim_buf_get_name(bufnr)
--   local project_root = (buf_file ~= '') and vim.fs.root(buf_file, root_markers) or vim.uv.cwd()
--   return project_root .. '/.filter.json'
-- end
--
-- -- 2. LOAD_FILTER_DATABASE: Safe hash-table hydration from persistent disk parameters
-- local function load_filter_database(bufnr)
--   M.manual_blocked_codes = {}
--
--   local json_database_file = get_db_path(bufnr)
--   local f = io.open(json_database_file, 'rb')
--   if not f then
--     return
--   end
--   local raw_json = f:read('*all')
--   f:close()
--
--   if raw_json and raw_json ~= '' then
--     local success, data = pcall(vim.json.decode, raw_json)
--     if success and data and type(data) == 'table' and type(data.codes) == 'table' then
--       for k, v in pairs(data.codes) do
--         local code_str = (type(k) == 'string') and k or v
--         if type(code_str) == 'string' and code_str ~= '' and not code_str:match('^table:') then
--           M.manual_blocked_codes[code_str] = true
--         end
--       end
--     end
--   end
-- end
--
-- -- 3. SAVE_FILTER_DATABASE: Writes explicit object hash-maps down to disk parameters
-- local function save_filter_database(bufnr)
--   local json_database_file = get_db_path(bufnr)
--   local f = io.open(json_database_file, 'wb')
--   if f then
--     if next(M.manual_blocked_codes) == nil then
--       f:write('{"codes":{}}')
--     else
--       local payload = { codes = M.manual_blocked_codes }
--       local pretty = require('nvimpio.utils.misc').jsonFormat(payload)
--       f:write(pretty)
--     end
--     f:close()
--   end
-- end
--
-- -- Safely trigger an absolute baseline load transaction upon initial module loading
-- load_filter_database(0)
--
-- -- =============================================================================
-- -- 4. THE ROBUST DYNAMIC HANDLER INTERCEPTOR (100% UN-HARDCODED AUTOMATION)
-- -- =============================================================================
-- function M.diagnostic_handler(err, result, ctx, config)
--   if err or not result or not result.diagnostics then
--     return vim.lsp.handlers['textDocument/publishDiagnostics'](err, result, ctx, config)
--   end
--
--   local current_buf = vim.uri_to_bufnr(result.uri)
--   load_filter_database(current_buf)
--
--   local clean_diagnostics = {}
--
--   for _, diag in ipairs(result.diagnostics) do
--     local keep = true
--     local code = diag.code
--
--     -- 🌟 FIXED: Use fallback default values to ensure that if lnum or col are nil,
--     -- they resolve to 0 cleanly and get blocked from your screen viewport layout.
--     local line_num = diag.lnum or 0
--     local col_num = diag.col or 0
--
--     -- Pass A: Structural Environment Filtering
--     if line_num == 0 and col_num == 0 then
--       keep = false
--     end
--
--     -- Pass B: User Selection Manual Suppression (Fully decoupled check)
--     if keep and code and M.manual_blocked_codes[code] then
--       keep = false
--     end
--
--     if keep then
--       table.insert(clean_diagnostics, diag)
--     end
--   end
--
--   result.diagnostics = clean_diagnostics
--   vim.lsp.handlers['textDocument/publishDiagnostics'](err, result, ctx, config)
-- end
--
-- -- =============================================================================
-- -- 5. TYPE-SAFE INTERACTIVE CONTROL PANEL
-- -- =============================================================================
-- function M.manage_file_diagnostics_interactive()
--   local current_buf = vim.api.nvim_get_current_buf()
--   local dashboard_items = {}
--
--   local has_active_filters = next(M.manual_blocked_codes) ~= nil
--   if has_active_filters then
--     table.insert(dashboard_items, { action = 'reset', display = '💥 Unblock all manual filters' })
--   end
--
--   -- Loop and parse current live workspace diagnostics
--   local raw_diagnostics = vim.diagnostic.get(current_buf)
--   local seen = {}
--   for _, diag in ipairs(raw_diagnostics) do
--     local code_name = diag.code or ''
--     local line_num = diag.lnum or 0
--     local col_num = diag.col or 0
--
--     -- Drop top-level driver flag elements already managed by our automated context filter
--     if code_name ~= '' and not (line_num == 0 and col_num == 0) then
--       if not M.manual_blocked_codes[code_name] and not seen[code_name] then
--         seen[code_name] = true
--         table.insert(dashboard_items, { action = 'block_code', id = code_name, display = '🔒 Suppress Code: [' .. code_name .. ']' })
--       end
--     end
--   end
--   table.sort(dashboard_items, function(a, b)
--     return a.display < b.display
--   end)
--
--   -- List active entries safely to enable unblocking actions
--   local unblock_options = {}
--   for key, value in pairs(M.manual_blocked_codes or {}) do
--     local code_str = (type(key) == 'string') and key or value
--     if type(code_str) == 'string' and code_str ~= '' and not code_str:match('^table:') then
--       table.insert(unblock_options, { action = 'unblock_code', id = code_str, display = 'A• 🔓 Remove Manual Filter: [' .. code_str .. ']' })
--     end
--   end
--   table.sort(unblock_options, function(a, b)
--     return a.display < b.display
--   end)
--   for _, opt in ipairs(unblock_options) do
--     table.insert(dashboard_items, opt)
--   end
--
--   if #dashboard_items == 0 then
--     vim.notify('✅ Clean Slate: No active framework exceptions active.', vim.log.levels.INFO, { title = 'Compiler Mangler' })
--     return
--   end
--
--   -- Draw the core choice prompt container panel
--   vim.ui.select(dashboard_items, {
--     prompt = 'Filter Control Panel (Select row item to modify suppression matrix)',
--     format_item = function(item)
--       return (type(item) == 'table' and type(item.display) == 'string') and item.display or tostring(item)
--     end,
--   }, function(choice)
--     if not choice then
--       return
--     end
--
--     if choice.action == 'reset' then
--       M.manual_blocked_codes = {}
--       save_filter_database(current_buf)
--       vim.notify('💥 All custom selections wiped clean.', vim.log.levels.ERROR)
--     elseif choice.action == 'block_code' then
--       M.manual_blocked_codes[choice.id] = true
--       save_filter_database(current_buf)
--     elseif choice.action == 'unblock_code' then
--       M.manual_blocked_codes[choice.id] = nil
--       save_filter_database(current_buf)
--     end
--
--     -- Sync viewport changes immediately inside RAM space bounds
--     vim.diagnostic.show(nil, current_buf)
--   end)
-- end
--
-- -- stylua: ignore end
-- return M
-----------------------------------------------------------------------------------------

-- --- stylua: ignore start
local M = {}

-- Pure hot-memory registers for manual filters (like style lints)
M.manual_blocked_codes = {}

local root_markers = { 'platformio.ini', '.git' }
local initial_file = vim.api.nvim_buf_get_name(vim.api.nvim_get_current_buf())
local project_root = vim.fs.root(initial_file, root_markers) or vim.uv.cwd()
local json_database_file = project_root .. '/.filter.json'

local function load_filter_database()
  M.manual_blocked_codes = {}
  local f = io.open(json_database_file, 'rb')
  if not f then
    return
  end
  local raw_json = f:read('*all')
  f:close()
  if raw_json and raw_json ~= '' then
    local success, data = pcall(vim.json.decode, raw_json)
    if success and data and type(data) == 'table' then
      for k, v in pairs(data.codes or {}) do
        M.manual_blocked_codes[k] = v
      end
    end
  end
end

local function save_filter_database()
  local f = io.open(json_database_file, 'wb')
  if f then
    local payload = { codes = M.manual_blocked_codes }
    local pretty = require('nvimpio.utils.misc').jsonFormat(payload)
    f:write(pretty)
    f:close()
  end
end

load_filter_database()

-- =============================================================================
-- THE ROBUST DYNAMIC HANDLER INTERCEPTOR (100% UN-HARDCODED AUTOMATION)
-- =============================================================================
function M.diagnostic_handler(err, result, ctx, config)
  if err or not result or not result.diagnostics then
    return vim.lsp.handlers['textDocument/publishDiagnostics'](err, result, ctx, config)
  end

  local current_buf = vim.uri_to_bufnr(result.uri)
  local buf_file_name = vim.api.nvim_buf_get_name(current_buf)
  local clean_diagnostics = {}

  for _, diag in ipairs(result.diagnostics) do
    local keep = true
    local code = diag.code
    local range = diag.range or {}
    local start = range.start or {}

    -- 1. UNIVERSAL AUTOMATED STRUCTURAL FILTER:
    -- If the diagnostic reports an error on line 0 column 0, or is explicitly tagged
    -- outside your actual file context, it is a driver flag/environment constraint.
    -- We drop it instantly in memory. No strings matched, no loops needed.
    if start.line == 0 and start.character == 0 then
      keep = false

    -- 2. EXPLICIT MANUAL USER SUPPLIED OVERRIDES:
    -- Drop any secondary codes (like style lints) chosen by the user in the panel
    elseif code and M.manual_blocked_codes[code] then
      keep = false
    end

    if keep then
      table.insert(clean_diagnostics, diag)
    end
  end

  result.diagnostics = clean_diagnostics
  vim.lsp.handlers['textDocument/publishDiagnostics'](err, result, ctx, config)
end

-- =============================================================================
-- LIGHTWEIGHT TOGGLE DASHBOARD PANEL
-- =============================================================================
function M.manage_file_diagnostics_interactive()
  local current_buf = vim.api.nvim_get_current_buf()
  local dashboard_items = {}

  if next(M.manual_blocked_codes) ~= nil then
    table.insert(dashboard_items, { action = 'reset', display = '💥 Unblock all manual filters' })
  end

  local raw_diagnostics = vim.diagnostic.get(current_buf)
  local seen = {}
  for _, diag in ipairs(raw_diagnostics) do
    local code_name = diag.code or ''
    local range = diag.range or {}
    local start = range.start or {}

    -- Do not list driver-level constraints already handled by our automated context filter
    if code_name ~= '' and not (start.line == 0 and start.character == 0) then
      if not M.manual_blocked_codes[code_name] and not seen[code_name] then
        seen[code_name] = true
        table.insert(dashboard_items, { action = 'block_code', id = code_name, display = '🔒 Suppress Code: [' .. code_name .. ']' })
      end
    end
  end
  table.sort(dashboard_items, function(a, b)
    return a.display < b.display
  end)

  local unblock_options = {}
  for key, value in pairs(M.manual_blocked_codes or {}) do
    local code_str = (type(key) == 'string') and key or value
    if type(code_str) == 'string' and code_str ~= '' and not code_str:match('^table:') then
      table.insert(unblock_options, { action = 'unblock_code', id = code_str, display = '🔓 Remove Manual Filter: [' .. code_str .. ']' })
    end
  end
  table.sort(unblock_options, function(a, b)
    return a.display < b.display
  end)
  for _, opt in ipairs(unblock_options) do
    table.insert(dashboard_items, opt)
  end

  if #dashboard_items == 0 then
    vim.notify('✅ Clean Slate: No Customizable Exception Overrides Active.', vim.log.levels.INFO)
    return
  end

  -- Mount the interactive UI selection dashboard picker
  vim.ui.select(dashboard_items, {
    prompt = 'Filter Control Panel (Select warning line to suppress)',
    -- 🌟 THE CRITICAL INTERFACE FIX: Instruct Neovim to extract the display string
    -- from our dictionary object structure instead of printing the raw memory reference!
    format_item = function(item)
      return (type(item) == 'table' and type(item.display) == 'string') and item.display or tostring(item)
    end,
  }, function(choice)
    -- If the user hits Esc or explicitly exits the layout window block, abort safely
    if not choice then
      return
    end

    if choice.action == 'reset' then
      M.manual_blocked_codes = {}
      save_filter_database()
      vim.notify('💥 All custom filters wiped clean.', vim.log.levels.ERROR)
    elseif choice.action == 'block_code' then
      M.manual_blocked_codes[choice.id] = true
      save_filter_database()
    elseif choice.action == 'unblock_code' then
      M.manual_blocked_codes[choice.id] = nil
      save_filter_database()
    end

    -- Instantly push our fresh RAM memory presentation configuration across the view screen
    vim.diagnostic.show(nil, current_buf)
  end)
  -- vim.ui.select(dashboard_items, { prompt = 'Filter Control Panel' }, function(choice)
  --   if not choice then
  --     return
  --   end
  --   if choice.action == 'reset' then
  --     M.manual_blocked_codes = {}
  --   elseif choice.action == 'block_code' then
  --     M.manual_blocked_codes[choice.id] = true
  --   elseif choice.action == 'unblock_code' then
  --     M.manual_blocked_codes[choice.id] = nil
  --   end
  --
  --   save_filter_database()
  --   vim.diagnostic.show(nil, current_buf)
  -- end)
end

return M

-- --- stylua: ignore start
-- local M = {}
--
-- -- Initialize as empty tables right away to prevent nil-indexing crashes on startup
-- M.blocked_codes = {}
-- M.removed_flags = {}
--
-- local root_markers = { 'platformio.ini', '.git' }
--
-- -- Dynamically resolve paths relative to the active file buffer
-- local function get_db_path(bufnr)
--   bufnr = (bufnr and bufnr ~= 0) and bufnr or vim.api.nvim_get_current_buf()
--   local buf_file = vim.api.nvim_buf_get_name(bufnr)
--   local project_root = (buf_file ~= '') and vim.fs.root(buf_file, root_markers) or vim.uv.cwd()
--   return project_root .. '/.filter.json'
-- end
--
-- local function load_filter_database(bufnr)
--   M.blocked_codes = {}
--   M.removed_flags = {}
--
--   local json_database_file = get_db_path(bufnr)
--   local f = io.open(json_database_file, 'rb')
--   if not f then
--     return
--   end
--   local raw_json = f:read('*all')
--   f:close()
--   if raw_json and raw_json ~= '' then
--     local success, data = pcall(vim.json.decode, raw_json)
--     if success and data and type(data) == 'table' then
--       for k, v in pairs(data.codes or {}) do
--         M.blocked_codes[k] = v
--       end
--       for k, v in pairs(data.flags or {}) do
--         M.removed_flags[k] = v
--       end
--     end
--   end
-- end
--
-- function M.save_from_cli(bufnr)
--   local json_database_file = get_db_path(bufnr)
--   local f = io.open(json_database_file, 'wb')
--   if f then
--     local payload = { codes = M.blocked_codes, flags = M.removed_flags }
--     local pretty = require('nvimpio.utils.misc').jsonFormat(payload)
--     f:write(pretty)
--     f:close()
--   end
-- end
--
-- load_filter_database(0)
--
-- -- =============================================================================
-- -- THE ROBUST SELF-LEARNING LSP STREAM INTERCEPTOR (100% AUTOMATED)
-- -- =============================================================================
-- function M.diagnostic_handler(err, result, ctx, config)
--   if err or not result or not result.diagnostics then
--     return vim.lsp.handlers['textDocument/publishDiagnostics'](err, result, ctx, config)
--   end
--
--   local bufnr = vim.uri_to_bufnr(result.uri)
--   load_filter_database(bufnr)
--
--   local clean_diagnostics = {}
--   local automated_discoveries = false
--
--   -- PASS 1: AUTOMATED ZERO-HARDCODE DATA OBJECT CAPTURE
--   for _, diag in ipairs(result.diagnostics) do
--     local code = diag.code
--     local msg = diag.message or ''
--
--     if code and type(code) == 'string' and code ~= '' then
--       -- Intercept generic driver failure categories via canonical LSP keys
--       if code == 'drv_unknown_argument' or code == 'drv_unknown_argument_with_suggestion' or code == 'fatal_too_many_errors' then
--         if not M.blocked_codes[code] then
--           M.blocked_codes[code] = true
--           automated_discoveries = true
--         end
--
--         -- Extract the flag name out of the string. By using match instead of gmatch,
--         -- we capture only the very first word starting with a dash, completely
--         -- avoiding any correction suggestion noise down the line!
--         local clean_flag = msg:match('(%-[%w%-]+)')
--         if clean_flag and not M.removed_flags[clean_flag] then
--           M.removed_flags[clean_flag] = true
--           automated_discoveries = true
--         end
--       end
--     end
--   end
--
--   -- If new framework barriers were found, save them down to disk on the very first frame
--   if automated_discoveries then
--     M.save_from_cli(bufnr)
--   end
--
--   -- PASS 2: PRESENTATION SCREENING IN RAM
--   for _, diag in ipairs(result.diagnostics) do
--     local keep = true
--     local code = diag.code
--     local msg = diag.message or ''
--
--     if code and M.blocked_codes[code] then
--       keep = false
--     end
--
--     if keep then
--       for flag, _ in pairs(M.removed_flags) do
--         if msg:find(flag, 1, true) then
--           keep = false
--           break
--         end
--       end
--     end
--
--     if keep then
--       table.insert(clean_diagnostics, diag)
--     end
--   end
--
--   result.diagnostics = clean_diagnostics
--   vim.lsp.handlers['textDocument/publishDiagnostics'](err, result, ctx, config)
-- end
--
-- -- =============================================================================
-- -- AUTOMATION COMPATIBLE CONTROL PANEL
-- -- =============================================================================
-- function M.manage_file_diagnostics_interactive()
--   local current_buf = vim.api.nvim_get_current_buf()
--   local dashboard_items = {}
--
--   local has_active_filters = next(M.blocked_codes) ~= nil or next(M.removed_flags) ~= nil
--   if has_active_filters then
--     table.insert(dashboard_items, { action = 'reset', display = '💥 Clear Automated Filter Database' })
--   end
--
--   local unblock_options = {}
--   for key, value in pairs(M.removed_flags or {}) do
--     local flag_str = (type(key) == 'string') and key or value
--     if type(flag_str) == 'string' and flag_str ~= '' and not flag_str:match('^table:') then
--       table.insert(unblock_options, { action = 'unblock_flag', id = flag_str, display = 'A• 🔓 Remove Flag Filter: [' .. flag_str .. ']' })
--     end
--   end
--   for key, value in pairs(M.blocked_codes or {}) do
--     local code_str = (type(key) == 'string') and key or value
--     if type(code_str) == 'string' and code_str ~= '' and not code_str:match('^table:') then
--       table.insert(unblock_options, { action = 'unblock_code', id = code_str, display = 'B• 🔓 Remove Code Suppress: [' .. code_str .. ']' })
--     end
--   end
--   table.sort(unblock_options, function(a, b)
--     return a.display < b.display
--   end)
--   for _, opt in ipairs(unblock_options) do
--     table.insert(dashboard_items, opt)
--   end
--
--   if #dashboard_items == 0 then
--     vim.notify('✅ Clean Slate: No active framework filters applied.', vim.log.levels.INFO)
--     return
--   end
--
--   vim.ui.select(dashboard_items, { prompt = 'Filter Control Panel' }, function(choice)
--     if not choice then
--       return
--     end
--
--     if choice.action == 'reset' then
--       M.blocked_codes = {}
--       M.removed_flags = {}
--       M.save_from_cli(current_buf)
--       vim.notify('💥 Filters wiped clean.', vim.log.levels.ERROR)
--     elseif choice.action == 'unblock_flag' then
--       M.removed_flags[choice.id] = nil
--       M.save_from_cli(current_buf)
--     elseif choice.action == 'unblock_code' then
--       M.blocked_codes[choice.id] = nil
--       M.save_from_cli(current_buf)
--     end
--
--     vim.diagnostic.show(nil, current_buf)
--   end)
-- end
--
-- return M
