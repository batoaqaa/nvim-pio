--- stylua: ignore start
local M = {}

-- Pure hot-memory registers for automated blocks
M.blocked_codes = {}
M.removed_flags = {}

local root_markers = { 'platformio.ini', '.git' }
local initial_file = vim.api.nvim_buf_get_name(vim.api.nvim_get_current_buf())
local project_root = vim.fs.root(initial_file, root_markers) or vim.uv.cwd()
local json_database_file = project_root .. '/.filter.json'

local function load_filter_database()
  M.blocked_codes = {}
  M.removed_flags = {}
  local f = io.open(json_database_file, 'rb')
  if not f then
    return
  end
  local raw_json = f:read('*all')
  f:close()
  if raw_json and raw_json ~= '' then
    local success, data = pcall(vim.json.decode, raw_json)
    if success and data and type(data) == 'table' then
      -- Re-hydrate dictionary tracking loops safely
      for k, v in pairs(data.codes or {}) do
        M.blocked_codes[k] = v
      end
      for k, v in pairs(data.flags or {}) do
        M.removed_flags[k] = v
      end
    end
  end
end

function M.save_from_cli()
  local f = io.open(json_database_file, 'wb')
  if f then
    local payload = { codes = M.blocked_codes, flags = M.removed_flags }
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

  local clean_diagnostics = {}

  for _, diag in ipairs(result.diagnostics) do
    local keep = true
    local code = diag.code
    local msg = diag.message or ''

    -- 1. Check if the error code itself is blocked
    if code and M.blocked_codes[code] then
      keep = false
    end

    -- 2. Check if the error message references a blocked compiler driver flag
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
-- UNBLOCK CONTROL CENTER PANEL (Type-Safe Node Matching)
-- =============================================================================
function M.manage_file_diagnostics_interactive()
  local current_buf = vim.api.nvim_get_current_buf()
  local dashboard_items = {}

  local has_active_filters = next(M.blocked_codes) ~= nil or next(M.removed_flags) ~= nil
  if has_active_filters then
    table.insert(dashboard_items, { action = 'reset', display = '💥 Clear Automated Filter Database' })
  end

  -- Loop and parse out current filters safely
  local unblock_options = {}

  -- Type-Safe Loop Extractors to filter out any "table:" artifact pointers
  for key, value in pairs(M.removed_flags or {}) do
    local flag_str = (type(key) == 'string') and key or value
    if type(flag_str) == 'string' and flag_str ~= '' and not flag_str:match('^table:') then
      table.insert(unblock_options, { action = 'unblock_flag', id = flag_str, display = 'A•🔓 Remove Flag Filter: [' .. flag_str .. ']' })
    end
  end

  for key, value in pairs(M.blocked_codes or {}) do
    local code_str = (type(key) == 'string') and key or value
    if type(code_str) == 'string' and code_str ~= '' and not code_str:match('^table:') then
      table.insert(unblock_options, { action = 'unblock_code', id = code_str, display = 'B•🔓 Remove Code Suppress: [' .. code_str .. ']' })
    end
  end

  table.sort(unblock_options, function(a, b)
    return a.display < b.display
  end)
  for _, opt in ipairs(unblock_options) do
    table.insert(dashboard_items, opt)
  end

  if #dashboard_items == 0 then
    vim.notify('Clean Slate: No active overrides applied.', vim.log.levels.INFO)
    return
  end

  vim.ui.select(dashboard_items, {
    prompt = 'Automation Control Center (Select filter element to remove)',
    format_item = function(item)
      return item.display
    end,
  }, function(choice)
    if not choice then
      return
    end

    if choice.action == 'reset' then
      M.blocked_codes = {}
      M.removed_flags = {}
      M.save_from_cli()
      vim.notify('💥 Settings cleared. Editor parameters returned to true defaults.', vim.log.levels.ERROR)
    elseif choice.action == 'unblock_flag' then
      M.removed_flags[choice.id] = nil
      M.save_from_cli()
    elseif choice.action == 'unblock_code' then
      M.blocked_codes[choice.id] = nil
      M.save_from_cli()
    end

    -- Sync viewport instantly
    vim.diagnostic.show(nil, current_buf)
  end)
end

return M
