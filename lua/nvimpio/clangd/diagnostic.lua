-- stylua: ignore start
local M = {}

M.blocked_codes = {}
M.removed_flags = {}

local root_markers = { 'platformio.ini', '.git' }

-- FIXED: Convert path resolution into a dynamic function helper
local function get_db_path(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
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
      M.blocked_codes = data.codes or {}
      M.removed_flags = data.flags or {}
    end
  end
end

-- FIXED: Expose database saving with a dynamic buffer path injection argument
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

-- Initialize on default workspace path layout
load_filter_database()

-- THE AUTOMATED STREAM INTERCEPTOR
function M.diagnostic_handler(err, result, ctx, config)
  if err or not result or not result.diagnostics then
    return vim.lsp.handlers['textDocument/publishDiagnostics'](err, result, ctx, config)
  end

  -- Ensure we dynamically read the database relative to this file stream before filtering
  local bufnr = vim.uri_to_bufnr(result.uri)
  load_filter_database(bufnr)

  local clean_diagnostics = {}
  for _, diag in ipairs(result.diagnostics) do
    local keep = true
    local msg = diag.message or ''
    local code = diag.code

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

-- SIMPLE TOGGLE DASHBOARD PANEL
function M.manage_file_diagnostics_interactive()
  local current_buf = vim.api.nvim_get_current_buf()
  local dashboard_items = {}

  if next(M.blocked_codes) ~= nil or next(M.removed_flags) ~= nil then
    table.insert(dashboard_items, { action = 'reset', display = '💥 Unblock all' })
  end

  local raw_diagnostics = vim.diagnostic.get(current_buf)
  for _, diag in ipairs(raw_diagnostics) do
    local code_name = diag.code or ''
    local msg = diag.message or ''
    local unknown_arg = msg:match('argument%s*%p?%s*[\'"]?(%-[%w%-]+)[\'"]?') or msg:match('option%s*%p?%s*[\'"]?(%-[%w%-]+)[\'"]?')

    if unknown_arg then
      local clean_flag = unknown_arg:gsub('[\'"%?]', ''):gsub('%s+$', '')
      if not M.removed_flags[clean_flag] then
        table.insert(dashboard_items, { action = 'block_flag', id = clean_flag, display = '🔨 Filter flag: ' .. clean_flag })
      end
    elseif code_name ~= '' and not M.blocked_codes[code_name] then
      table.insert(dashboard_items, { action = 'block_code', id = code_name, display = '🔒 Suppress Code: ' .. code_name })
    end
  end

  if #dashboard_items == 0 then
    return
  end

  vim.ui.select(dashboard_items, { prompt = 'Filter Panel' }, function(choice)
    if not choice then
      return
    end
    if choice.action == 'reset' then
      M.blocked_codes, M.removed_flags = {}, {}
    elseif choice.action == 'block_flag' then
      M.removed_flags[choice.id] = true
    elseif choice.action == 'block_code' then
      M.blocked_codes[choice.id] = true
    end
    M.save_from_cli(current_buf)
    vim.cmd('edit!')
  end)
end

return M
