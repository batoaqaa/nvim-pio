--- stylua: ignore start
local M = {}

-- Explicit table instantiation at the top prevents race-condition crashes
M.manual_blocked_codes = {}
M.removed_flags = {}

local root_markers = { 'platformio.ini', '.git' }

-- 1. GET_DB_PATH: Dynamically resolves project workspace paths in memory space safely
local function get_db_path(bufnr)
  bufnr = (bufnr and bufnr ~= 0) and bufnr or vim.api.nvim_get_current_buf()
  local buf_file = vim.api.nvim_buf_get_name(bufnr)
  local project_root = (buf_file ~= '') and vim.fs.root(buf_file, root_markers) or vim.uv.cwd()
  return project_root .. '/.filter.json'
end

-- 2. LOAD_FILTER_DATABASE: Safe hash-table hydration evaluated dynamically per buffer
local function load_filter_database(bufnr)
  M.manual_blocked_codes = {}
  M.removed_flags = {}

  local json_database_file = get_db_path(bufnr)
  local f = io.open(json_database_file, 'rb')
  if not f then
    return
  end
  local raw_json = f:read('*all')
  f:close()

  if raw_json and raw_json ~= '' then
    local success, data = pcall(vim.json.decode, raw_json)
    if success and data and type(data) == 'table' then
      -- Safely re-hydrate code structures
      if type(data.codes) == 'table' then
        for k, v in pairs(data.codes) do
          local code_str = (type(k) == 'string') and k or v
          if type(code_str) == 'string' and code_str ~= '' and not code_str:match('^table:') then
            M.manual_blocked_codes[code_str] = true
          end
        end
      end
      -- Safely re-hydrate compiler flag structures
      if type(data.flags) == 'table' then
        for k, v in pairs(data.flags) do
          local flag_str = (type(k) == 'string') and k or v
          if type(flag_str) == 'string' and flag_str ~= '' and not flag_str:match('^table:') then
            M.removed_flags[flag_str] = true
          end
        end
      end
    end
  end
end

-- 3. SAVE_FILTER_DATABASE: Writes explicit object hash-maps down to disk parameters
local function save_filter_database(bufnr)
  local json_database_file = get_db_path(bufnr)
  local f = io.open(json_database_file, 'wb')
  if f then
    local payload = { codes = M.manual_blocked_codes, flags = M.removed_flags }
    local pretty = require('nvimpio.utils.misc').jsonFormat(payload)
    f:write(pretty)
    f:close()
  end
end

-- Safely trigger an absolute baseline load transaction upon initial module loading
load_filter_database(0)

-- =============================================================================
-- 4. THE ROBUST DYNAMIC HANDLER INTERCEPTOR (100% AUTOMATED DRIVER FLAG LOGGING)
-- =============================================================================
function M.diagnostic_handler(err, result, ctx, config)
  if err or not result or not result.diagnostics then
    return vim.lsp.handlers['textDocument/publishDiagnostics'](err, result, ctx, config)
  end

  local current_buf = vim.uri_to_bufnr(result.uri)
  load_filter_database(current_buf)

  local clean_diagnostics = {}
  local automated_discoveries = false

  -- PASS 1: AUTOMATED ZERO-HARDCODE COMPILER DRIVER FLAG CAPTURING
  for _, diag in ipairs(result.diagnostics) do
    local code = diag.code
    local msg = diag.message or ''

    if code and type(code) == 'string' and code ~= '' then
      -- If the diagnostic maps to a structural platform argument failure
      if code == 'drv_unknown_argument' or code == 'drv_unknown_argument_with_suggestion' or code == 'fatal_too_many_errors' then
        -- Extract only the very first hyphenated flag keyword to dodge correction duplicates
        local clean_flag = msg:match('(%-[%w%-]+)')
        if clean_flag and not M.removed_flags[clean_flag] then
          M.removed_flags[clean_flag] = true
          automated_discoveries = true
        end
      end
    end
  end

  -- Record keeping: If new driver boundaries were unmasked, silently write them to disk!
  if automated_discoveries then
    save_filter_database(current_buf)
  end

  -- PASS 2: PRESENTATION SCREENING IN RAM
  for _, diag in ipairs(result.diagnostics) do
    local keep = true
    local code = diag.code
    local msg = diag.message or ''

    -- Strip out generic driver error categories automatically
    if code == 'drv_unknown_argument' or code == 'drv_unknown_argument_with_suggestion' or code == 'fatal_too_many_errors' then
      keep = false
    -- Strip out secondary custom warnings manually chosen by the user in the panel
    elseif code and M.manual_blocked_codes[code] then
      keep = false
    end

    -- Strip out items matching our learned record-keeping hardware flag strings
    if keep then
      for flag, _ in pairs(M.removed_flags) do
        if msg:find(flag, 1, true) then
          keep = false
          break
        end
      end
    end

    if keep then
      table.insert(clean_diagnostics, diag)
    end
  end

  result.diagnostics = clean_diagnostics
  vim.lsp.handlers['textDocument/publishDiagnostics'](err, result, ctx, config)
end

-- =============================================================================
-- 5. TYPE-SAFE INTERACTIVE CONTROL PANEL
-- =============================================================================
function M.manage_file_diagnostics_interactive()
  local current_buf = vim.api.nvim_get_current_buf()
  local dashboard_items = {}

  local has_active_filters = next(M.manual_blocked_codes) ~= nil or next(M.removed_flags) ~= nil
  if has_active_filters then
    table.insert(dashboard_items, { action = 'reset', display = '💥 Clear All Active Filters & Records' })
  end

  -- SECTION B: LIST OUTSTANDING CODES SO YOU CAN CHOOSE WHAT TO BLOCK (e.g. pp_file_not_found)
  local raw_diagnostics = vim.diagnostic.get(current_buf)
  local seen = {}
  for _, diag in ipairs(raw_diagnostics) do
    local code_name = diag.code or ''
    if
      code_name ~= ''
      and code_name ~= 'drv_unknown_argument'
      and code_name ~= 'drv_unknown_argument_with_suggestion'
      and code_name ~= 'fatal_too_many_errors'
    then
      if not M.manual_blocked_codes[code_name] and not seen[code_name] then
        seen[code_name] = true
        table.insert(dashboard_items, { action = 'block_code', id = code_name, display = '🔒 Suppress Code: [' .. code_name .. ']' })
      end
    end
  end
  table.sort(dashboard_items, function(a, b)
    return a.display < b.display
  end)

  -- SECTION C: LIST ACTIVE BLOCKS FOR REVIEW AND UNBLOCKING (Strict Type String Validation)
  local unblock_options = {}
  for key, value in pairs(M.manual_blocked_codes or {}) do
    local code_str = (type(key) == 'string') and key or value
    if type(code_str) == 'string' and code_str ~= '' and not code_str:match('^table:') then
      table.insert(unblock_options, { action = 'unblock_code', id = code_str, display = '🔓 Remove Manual Filter: [' .. code_str .. ']' })
    end
  end

  -- Display your recorded hardware flags right inside the panel for complete visibility!
  for key, value in pairs(M.removed_flags or {}) do
    local flag_str = (type(key) == 'string') and key or value
    if type(flag_str) == 'string' and flag_str ~= '' and not flag_str:match('^table:') then
      table.insert(unblock_options, { action = 'unblock_flag', id = flag_str, display = '📋 [RECORDED FLAG]: ' .. flag_str })
    end
  end

  table.sort(unblock_options, function(a, b)
    return a.display < b.display
  end)
  for _, opt in ipairs(unblock_options) do
    table.insert(dashboard_items, opt)
  end

  if #dashboard_items == 0 then
    vim.notify('✅ Clean Slate: No active framework filters found.', vim.log.levels.INFO, { title = 'Compiler Mangler' })
    return
  end

  -- Draw the core choice prompt container panel
  vim.ui.select(dashboard_items, {
    prompt = 'Filter Control Panel (Select row item to modify suppression matrix)',
    format_item = function(item)
      return (type(item) == 'table' and type(item.display) == 'string') and item.display or tostring(item)
    end,
  }, function(choice)
    if not choice then
      return
    end

    if choice.action == 'reset' then
      M.manual_blocked_codes = {}
      M.removed_flags = {}
      save_filter_database(current_buf)
      vim.notify('💥 Filters wiped clean and log history reset.', vim.log.levels.ERROR)
    elseif choice.action == 'block_code' then
      M.manual_blocked_codes[choice.id] = true
      save_filter_database(current_buf)
    elseif choice.action == 'unblock_code' then
      M.manual_blocked_codes[choice.id] = nil
      save_filter_database(current_buf)
    elseif choice.action == 'unblock_flag' then
      M.removed_flags[choice.id] = nil
      save_filter_database(current_buf)
    end

    -- Defer the refresh pass until the floating UI thread has completely closed down
    vim.schedule(function()
      if vim.api.nvim_buf_is_valid(current_buf) then
        vim.api.nvim_buf_call(current_buf, function()
          local old_shortmess = vim.o.shortmess
          vim.o.shortmess = old_shortmess .. 'F'

          vim.cmd('silent! checktime')
          vim.cmd('silent! edit!')

          vim.o.shortmess = old_shortmess
        end)
      end
    end)
  end)
end

return M

-- --- stylua: ignore start
-- local M = {}
--
-- -- Explicit table instantiation at the absolute top prevents race-condition crashes
-- M.manual_blocked_codes = {}
--
-- local root_markers = { 'platformio.ini', '.git' }
--
-- -- 1. GET_DB_PATH: Dynamically resolves project workspace paths in memory space safely
-- local function get_db_path(bufnr)
--   bufnr = (bufnr and bufnr ~= 0) and bufnr or vim.api.nvim_get_current_buf()
--   local buf_file = vim.api.nvim_buf_get_name(bufnr)
--   local project_root = (buf_file ~= '') and vim.fs.root(buf_file, root_markers) or vim.uv.cwd()
--   return project_root .. '/.filter.json'
-- end
--
-- -- 2. LOAD_FILTER_DATABASE: Safe hash-table hydration evaluated dynamically per buffer
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
--     -- 🌟 THE UNIVERSAL AUTOMATED FILTER (ZERO STRINGS/NO HARDCODING):
--     -- Catch and discard any standard driver-level error categories instantly in RAM.
--     -- This strips out -mlongcalls, etc., completely dynamically without hardcoding them.
--     if code == 'drv_unknown_argument' or code == 'drv_unknown_argument_with_suggestion' or code == 'fatal_too_many_errors' then
--       keep = false
--
--     -- 2. EXPLICIT MANUAL USER OVERRIDES:
--     -- Drop secondary custom warnings (like style lints) selected by the user in the panel
--     elseif code and M.manual_blocked_codes[code] then
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
--
--     -- Drop driver flag elements already managed by our automated context filter
--     if
--       code_name ~= ''
--       and code_name ~= 'drv_unknown_argument'
--       and code_name ~= 'drv_unknown_argument_with_suggestion'
--       and code_name ~= 'fatal_too_many_errors'
--     then
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
--     vim.notify('✅ Clean Slate: No active customizable exception overrides active.', vim.log.levels.INFO, { title = 'Compiler Mangler' })
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
--       vim.notify('💥 Filters wiped clean.', vim.log.levels.ERROR)
--     elseif choice.action == 'block_code' then
--       M.manual_blocked_codes[choice.id] = true
--       save_filter_database(current_buf)
--     elseif choice.action == 'unblock_code' then
--       M.manual_blocked_codes[choice.id] = nil
--       save_filter_database(current_buf)
--     end
--
--     -- Sync viewport changes immediately inside RAM space bounds
--     -- vim.diagnostic.show(nil, current_buf)
--     vim.schedule(function()
--       if vim.api.nvim_buf_is_valid(current_buf) then
--         vim.api.nvim_buf_call(current_buf, function()
--           local old_shortmess = vim.o.shortmess
--           vim.o.shortmess = old_shortmess .. 'F'
--
--           vim.cmd('silent! checktime')
--           vim.cmd('silent! edit!')
--
--           vim.o.shortmess = old_shortmess
--         end)
--       end
--     end)
--   end)
-- end
--
-- -- stylua: ignore end
-- return M
