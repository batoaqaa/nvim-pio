--- stylua: ignore start
local M = {}

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
      M.manual_blocked_codes = data.codes or {}
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
-- THE CORE INTERCEPTOR: Filters only what you explicitly choose
-- =============================================================================
function M.diagnostic_handler(err, result, ctx, config)
  if err or not result or not result.diagnostics then
    return vim.lsp.handlers['textDocument/publishDiagnostics'](err, result, ctx, config)
  end

  local clean_diagnostics = {}

  for _, diag in ipairs(result.diagnostics) do
    local keep = true
    local code = diag.code

    -- Filter out secondary warnings (like pp_file_not_found) selected by the user
    if code and M.manual_blocked_codes[code] then
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
-- LIGHTWEIGHT CONTROL PANEL
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
    if code_name ~= '' and not M.manual_blocked_codes[code_name] and not seen[code_name] then
      seen[code_name] = true
      table.insert(dashboard_items, { action = 'block_code', id = code_name, display = '🔒 Suppress Code: [' .. code_name .. ']' })
    end
  end

  if #dashboard_items == 0 then
    vim.notify('✅ Complete Parity: No active exceptions found.', vim.log.levels.INFO)
    return
  end

  vim.ui.select(dashboard_items, { prompt = 'Manual Filter Control Panel' }, function(choice)
    if not choice then
      return
    end
    if choice.action == 'reset' then
      M.manual_blocked_codes = {}
    elseif choice.action == 'block_code' then
      M.manual_blocked_codes[choice.id] = true
    end

    save_filter_database()
    vim.diagnostic.show(nil, current_buf)
  end)
end

return M
