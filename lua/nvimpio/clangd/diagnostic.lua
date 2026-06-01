--- stylua: ignore start
local M = {}

-- Pure hot-memory register for automatically learned framework blocks
M.blocked_codes = {}

local root_markers = { 'platformio.ini', '.git' }
local initial_file = vim.api.nvim_buf_get_name(vim.api.nvim_get_current_buf())
local project_root = vim.fs.root(initial_file, root_markers) or vim.uv.cwd()
local json_database_file = project_root .. '/.filter.json'

local function load_filter_database()
  M.blocked_codes = {}
  local f = io.open(json_database_file, 'rb')
  if not f then
    return
  end
  local raw_json = f:read('*all')
  f:close()
  if raw_json and raw_json ~= '' then
    local success, data = pcall(vim.json.decode, raw_json)
    if success and data and type(data) == 'table' then
      M.blocked_codes = data.codes or {}
    end
  end
end

function M.save_from_cli()
  local f = io.open(json_database_file, 'wb')
  if f then
    local payload = { codes = M.blocked_codes }
    local pretty = require('nvimpio.utils.misc').jsonFormat(payload)
    f:write(pretty)
    f:close()
  end
end

load_filter_database()

-- =============================================================================
-- THE ZERO-HARDCODE LSP INTERCEPTOR (Pure Stream Filtering)
-- =============================================================================
function M.diagnostic_handler(err, result, ctx, config)
  if err or not result or not result.diagnostics then
    return vim.lsp.handlers['textDocument/publishDiagnostics'](err, result, ctx, config)
  end

  local bufnr = vim.uri_to_bufnr(result.uri)
  local clean_diagnostics = {}

  -- Zero-Hardcode Memory Pass: Instantly drop any codes learned by the state machine
  for _, diag in ipairs(result.diagnostics) do
    local code = diag.code
    if not (code and M.blocked_codes[code]) then
      table.insert(clean_diagnostics, diag)
    end
  end

  result.diagnostics = clean_diagnostics
  vim.lsp.handlers['textDocument/publishDiagnostics'](err, result, ctx, config)
end

-- =============================================================================
-- UNBLOCK CONTROL CENTER PANEL
-- =============================================================================
function M.manage_file_diagnostics_interactive()
  local current_buf = vim.api.nvim_get_current_buf()
  local dashboard_items = {}

  if next(M.blocked_codes) ~= nil then
    table.insert(dashboard_items, { action = 'reset', display = '💥 Clear Automated Filter Database' })
    for code, _ in pairs(M.blocked_codes) do
      table.insert(dashboard_items, { action = 'unblock', id = code, display = 'A•🔓 Remove automated filter: [' .. code .. ']' })
    end
  end

  if #dashboard_items == 0 then
    vim.notify('Ref Filter Slate: No active compiler overrides found.', vim.log.levels.INFO)
    return
  end

  table.sort(dashboard_items, function(a, b)
    return a.display < b.display
  end)

  vim.ui.select(dashboard_items, { prompt = 'Automation Control Center' }, function(choice)
    if not choice then
      return
    end
    if choice.action == 'reset' then
      M.blocked_codes = {}
      M.save_from_cli()
      vim.notify('💥 Settings cleared. Editor returned to original static behaviors.', vim.log.levels.ERROR)
    elseif choice.action == 'unblock' then
      M.blocked_codes[choice.id] = nil
      M.save_from_cli()
    end

    -- Sync viewport instantly
    vim.diagnostic.show(nil, current_buf)
  end)
end

return M
