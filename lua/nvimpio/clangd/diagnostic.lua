--- stylua: ignore start
local M = {}

M.blocked_codes = {}

local root_markers = { 'platformio.ini', '.git' }

-- Dynamically resolve the path to ensure .filter.json saves in the true project folder
local function get_db_path(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local buf_file = vim.api.nvim_buf_get_name(bufnr)
  local project_root = (buf_file ~= '') and vim.fs.root(buf_file, root_markers) or vim.uv.cwd()
  return project_root .. '/.filter.json'
end

local function load_filter_database(bufnr)
  M.blocked_codes = {}
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
      M.blocked_codes = data.codes or {}
    end
  end
end

function M.save_from_cli(bufnr)
  local json_database_file = get_db_path(bufnr)
  local f = io.open(json_database_file, 'wb')
  if f then
    local payload = { codes = M.blocked_codes }
    local pretty = require('nvimpio.utils.misc').jsonFormat(payload)
    f:write(pretty)
    f:close()
  end
end

-- Initialize database tables on load
load_filter_database()

-- =============================================================================
-- THE ROBUST SELF-LEARNING LSP STREAM INTERCEPTOR (100% AUTOMATED)
-- =============================================================================
function M.diagnostic_handler(err, result, ctx, config)
  if err or not result or not result.diagnostics then
    return vim.lsp.handlers['textDocument/publishDiagnostics'](err, result, ctx, config)
  end

  local bufnr = vim.uri_to_bufnr(result.uri)
  load_filter_database(bufnr)

  local clean_diagnostics = {}
  local automated_discoveries = false

  -- PASS 1: AUTOMATED ZERO-HARDCODE COMPILER ARGUMENT CAPTURING
  for _, diag in ipairs(result.diagnostics) do
    local code = diag.code
    local msg = diag.message or ''

    if code and type(code) == 'string' and code ~= '' then
      -- If the diagnostic category represents ANY variation of an unknown compiler flag
      if code == 'drv_unknown_argument' or code == 'drv_unknown_argument_with_suggestion' or code == 'fatal_too_many_errors' then
        -- 🌟 FIXED: Simple, robust capture that grabs any word starting with a dash (-)
        -- It perfectly extracts '-mlongcalls', '-fstrict-volatile-bitfields', etc.
        for clean_flag in string.gmatch(msg, '(%-[%w%-]+)') do
          if not M.removed_flags[clean_flag] then
            M.removed_flags[clean_flag] = true
            automated_discoveries = true
          end
        end
      end
    end
  end
  -- If a new driver barrier was encountered, save it quietly to .filter.json
  if automated_discoveries then
    M.save_from_cli(bufnr)
  end

  -- PASS 2: PRESENTATION SCREENING
  for _, diag in ipairs(result.diagnostics) do
    local code = diag.code
    -- If the code is registered inside our automated block table, drop it instantly
    if not (code and M.blocked_codes[code]) then
      table.insert(clean_diagnostics, diag)
    end
  end

  result.diagnostics = clean_diagnostics
  vim.lsp.handlers['textDocument/publishDiagnostics'](err, result, ctx, config)
end

-- =============================================================================
-- AUTOMATION COMPATIBLE CONTROL PANEL
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
    vim.notify('✅ Clean Slate: No active framework filters applied.', vim.log.levels.INFO, { title = 'Compiler Mangler' })
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
      M.save_from_cli(current_buf)
      vim.notify('💥 Filters wiped clean. File will re-parse on next edit.', vim.log.levels.ERROR)
    elseif choice.action == 'unblock' then
      M.blocked_codes[choice.id] = nil
      M.save_from_cli(current_buf)
    end

    -- Sync viewport instantly
    vim.diagnostic.show(nil, current_buf)
  end)
end

-- stylua: ignore end
return M
