--- stylua: ignore start
local M = {}

-- Explicit table instantiation at the absolute top prevents race-condition crashes
M.manual_blocked_codes = {}

local root_markers = { 'platformio.ini', '.git' }

-- 1. GET_DB_PATH: Dynamically resolves project workspace paths in memory space
local function get_db_path(bufnr)
  bufnr = (bufnr and bufnr ~= 0) and bufnr or vim.api.nvim_get_current_buf()
  local buf_file = vim.api.nvim_buf_get_name(bufnr)
  local project_root = (buf_file ~= '') and vim.fs.root(buf_file, root_markers) or vim.uv.cwd()
  return project_root .. '/.filter.json'
end

-- 2. LOAD_FILTER_DATABASE: Safe hash-table hydration from persistent disk parameters
local function load_filter_database(bufnr)
  M.manual_blocked_codes = {}

  local json_database_file = get_db_path(bufnr)
  local f = io.open(json_database_file, 'rb')
  if not f then
    return
  end
  local raw_json = f:read('*all')
  f:close()

  if raw_json and raw_json ~= '' then
    local success, data = pcall(vim.json.decode, raw_json)
    if success and data and type(data) == 'table' and type(data.codes) == 'table' then
      for k, v in pairs(data.codes) do
        local code_str = (type(k) == 'string') and k or v
        if type(code_str) == 'string' and code_str ~= '' and not code_str:match('^table:') then
          M.manual_blocked_codes[code_str] = true
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
    if next(M.manual_blocked_codes) == nil then
      f:write('{"codes":{}}')
    else
      local payload = { codes = M.manual_blocked_codes }
      local pretty = require('nvimpio.utils.misc').jsonFormat(payload)
      f:write(pretty)
    end
    f:close()
  end
end

-- Safely trigger an absolute baseline load transaction upon initial module loading
load_filter_database(0)

-- =============================================================================
-- 4. THE ROBUST DYNAMIC HANDLER INTERCEPTOR (SMART POSITION FILTERING)
-- =============================================================================
function M.diagnostic_handler(err, result, ctx, config)
  if err or not result or not result.diagnostics then
    return vim.lsp.handlers['textDocument/publishDiagnostics'](err, result, ctx, config)
  end

  local current_buf = vim.uri_to_bufnr(result.uri)
  load_filter_database(current_buf)

  local clean_diagnostics = {}

  for _, diag in ipairs(result.diagnostics) do
    local keep = true
    local code = diag.code

    -- Enforce absolute type protection variables against missing data tokens
    local line_num = diag.lnum or 0
    local col_num = diag.col or 0

    -- 🌟 THE UNIVERSAL AUTOMATION GATEWAY (ZERO STRINGS/NO HARDCODING):
    -- If an item sits precisely at Line 1, Col 1 (0,0) AND it contains no valid,
    -- standard error code tag, it is a driver-level architecture argument fault.
    -- We drop it instantly in memory before Neovim can draw it on the viewport!
    if line_num == 0 and col_num == 0 and (not code or code == '') then
      keep = false
    end

    -- Pass B: User Selection Manual Suppression (Fully decoupled check)
    if keep and code and M.manual_blocked_codes[code] then
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
-- 5. TYPE-SAFE INTERACTIVE CONTROL PANEL
-- =============================================================================
function M.manage_file_diagnostics_interactive()
  local current_buf = vim.api.nvim_get_current_buf()
  local dashboard_items = {}

  local has_active_filters = next(M.manual_blocked_codes) ~= nil
  if has_active_filters then
    table.insert(dashboard_items, { action = 'reset', display = '💥 Unblock all manual filters' })
  end

  -- Loop and parse current live workspace diagnostics
  local raw_diagnostics = vim.diagnostic.get(current_buf)
  local seen = {}
  for _, diag in ipairs(raw_diagnostics) do
    local code_name = diag.code or ''
    local line_num = diag.lnum or 0
    local col_num = diag.col or 0

    -- Drop top-level driver flag elements already managed by our automated context filter
    if code_name ~= '' and not (line_num == 0 and col_num == 0) then
      if not M.manual_blocked_codes[code_name] and not seen[code_name] then
        seen[code_name] = true
        table.insert(dashboard_items, { action = 'block_code', id = code_name, display = '🔒 Suppress Code: [' .. code_name .. ']' })
      end
    end
  end
  table.sort(dashboard_items, function(a, b)
    return a.display < b.display
  end)

  -- List active entries safely to enable unblocking actions
  local unblock_options = {}
  for key, value in pairs(M.manual_blocked_codes or {}) do
    local code_str = (type(key) == 'string') and key or value
    if type(code_str) == 'string' and code_str ~= '' and not code_str:match('^table:') then
      table.insert(unblock_options, { action = 'unblock_code', id = code_str, display = 'A• 🔓 Remove Manual Filter: [' .. code_str .. ']' })
    end
  end
  table.sort(unblock_options, function(a, b)
    return a.display < b.display
  end)
  for _, opt in ipairs(unblock_options) do
    table.insert(dashboard_items, opt)
  end

  if #dashboard_items == 0 then
    vim.notify('✅ Clean Slate: No active framework exceptions active.', vim.log.levels.INFO, { title = 'Compiler Mangler' })
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
      save_filter_database(current_buf)
      vim.notify('💥 All custom selections wiped clean.', vim.log.levels.ERROR)
    elseif choice.action == 'block_code' then
      M.manual_blocked_codes[choice.id] = true
      save_filter_database(current_buf)
    elseif choice.action == 'unblock_code' then
      M.manual_blocked_codes[choice.id] = nil
      save_filter_database(current_buf)
    end

    -- Sync viewport changes immediately inside RAM space bounds
    vim.diagnostic.show(nil, current_buf)
  end)
end

-- stylua: ignore end
return M
