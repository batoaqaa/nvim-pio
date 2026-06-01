--- stylua: ignore start
local M = {}

-- Initialize as empty tables right away to prevent nil-indexing crashes on startup
M.blocked_codes = {}
M.removed_flags = {}

local root_markers = { 'platformio.ini', '.git' }

-- Dynamically resolve paths relative to the active file buffer
local function get_db_path(bufnr)
  bufnr = (bufnr and bufnr ~= 0) and bufnr or vim.api.nvim_get_current_buf()
  local buf_file = vim.api.nvim_buf_get_name(bufnr)
  local project_root = (buf_file ~= '') and vim.fs.root(buf_file, root_markers) or vim.uv.cwd()
  return project_root .. '/.filter.json'
end

local function load_filter_database(bufnr)
  M.blocked_codes = {}
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
      for k, v in pairs(data.codes or {}) do
        M.blocked_codes[k] = v
      end
      for k, v in pairs(data.flags or {}) do
        M.removed_flags[k] = v
      end
    end
  end
end

function M.save_from_cli(bufnr)
  local json_database_file = get_db_path(bufnr)
  local f = io.open(json_database_file, 'wb')
  if f then
    local payload = { codes = M.blocked_codes, flags = M.removed_flags }
    local pretty = require('nvimpio.utils.misc').jsonFormat(payload)
    f:write(pretty)
    f:close()
  end
end

load_filter_database(0)

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

  -- PASS 1: AUTOMATED ZERO-HARDCODE DATA OBJECT CAPTURE
  for _, diag in ipairs(result.diagnostics) do
    local code = diag.code
    local msg = diag.message or ''

    if code and type(code) == 'string' and code ~= '' then
      -- Intercept generic driver failure categories via canonical LSP keys
      if code == 'drv_unknown_argument' or code == 'drv_unknown_argument_with_suggestion' or code == 'fatal_too_many_errors' then
        if not M.blocked_codes[code] then
          M.blocked_codes[code] = true
          automated_discoveries = true
        end

        -- Extract the flag name out of the string. By using match instead of gmatch,
        -- we capture only the very first word starting with a dash, completely
        -- avoiding any correction suggestion noise down the line!
        local clean_flag = msg:match('(%-[%w%-]+)')
        if clean_flag and not M.removed_flags[clean_flag] then
          M.removed_flags[clean_flag] = true
          automated_discoveries = true
        end
      end
    end
  end

  -- If new framework barriers were found, save them down to disk on the very first frame
  if automated_discoveries then
    M.save_from_cli(bufnr)
  end

  -- PASS 2: PRESENTATION SCREENING IN RAM
  for _, diag in ipairs(result.diagnostics) do
    local keep = true
    local code = diag.code
    local msg = diag.message or ''

    if code and M.blocked_codes[code] then
      keep = false
    end

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
-- AUTOMATION COMPATIBLE CONTROL PANEL
-- =============================================================================
function M.manage_file_diagnostics_interactive()
  local current_buf = vim.api.nvim_get_current_buf()
  local dashboard_items = {}

  local has_active_filters = next(M.blocked_codes) ~= nil or next(M.removed_flags) ~= nil
  if has_active_filters then
    table.insert(dashboard_items, { action = 'reset', display = '💥 Clear Automated Filter Database' })
  end

  local unblock_options = {}
  for key, value in pairs(M.removed_flags or {}) do
    local flag_str = (type(key) == 'string') and key or value
    if type(flag_str) == 'string' and flag_str ~= '' and not flag_str:match('^table:') then
      table.insert(unblock_options, { action = 'unblock_flag', id = flag_str, display = 'A• 🔓 Remove Flag Filter: [' .. flag_str .. ']' })
    end
  end
  for key, value in pairs(M.blocked_codes or {}) do
    local code_str = (type(key) == 'string') and key or value
    if type(code_str) == 'string' and code_str ~= '' and not code_str:match('^table:') then
      table.insert(unblock_options, { action = 'unblock_code', id = code_str, display = 'B• 🔓 Remove Code Suppress: [' .. code_str .. ']' })
    end
  end
  table.sort(unblock_options, function(a, b)
    return a.display < b.display
  end)
  for _, opt in ipairs(unblock_options) do
    table.insert(dashboard_items, opt)
  end

  if #dashboard_items == 0 then
    vim.notify('✅ Clean Slate: No active framework filters applied.', vim.log.levels.INFO)
    return
  end

  vim.ui.select(dashboard_items, { prompt = 'Filter Control Panel' }, function(choice)
    if not choice then
      return
    end

    if choice.action == 'reset' then
      M.blocked_codes = {}
      M.removed_flags = {}
      M.save_from_cli(current_buf)
      vim.notify('💥 Filters wiped clean.', vim.log.levels.ERROR)
    elseif choice.action == 'unblock_flag' then
      M.removed_flags[choice.id] = nil
      M.save_from_cli(current_buf)
    elseif choice.action == 'unblock_code' then
      M.blocked_codes[choice.id] = nil
      M.save_from_cli(current_buf)
    end

    vim.diagnostic.show(nil, current_buf)
  end)
end

return M
