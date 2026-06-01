-- stylua: ignore start
local M = {}

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
  if not f then return end
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

local function save_filter_database()
  local f = io.open(json_database_file, 'wb')
  if f then
    local payload = { codes = M.blocked_codes, flags = M.removed_flags }
    local pretty = require('nvimpio.utils.misc').jsonFormat(payload)
    f:write(pretty)
    f:close()
  end
end

load_filter_database()

-- 1. THE AUTOMATED INTERCEPTOR: Runs silently inside the LSP stream on every pass
function M.diagnostic_handler(err, result, ctx, config)
  if err or not result or not result.diagnostics then
    return vim.lsp.handlers["textDocument/publishDiagnostics"](err, result, ctx, config)
  end

  local clean_diagnostics = {}

  for _, diag in ipairs(result.diagnostics) do
    local keep = true
    local msg = diag.message or ""
    local code = diag.code

    -- Automatically drop if short alphanumeric compiler code matches
    if code and M.blocked_codes[code] then
      keep = false
    end

    -- Automatically drop if message string contains blocked arguments
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
  vim.lsp.handlers["textDocument/publishDiagnostics"](err, result, ctx, config)
end

-- 2. SIMPLE TOGGLE MENU (No reloads, no loops, just updates the database)
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

  if #dashboard_items == 0 then return end

  vim.ui.select(dashboard_items, { prompt = 'Filter Panel' }, function(choice)
    if not choice then return end
    if choice.action == 'reset' then
      M.blocked_codes, M.removed_flags = {}, {}
    elseif choice.action == 'block_flag' then M.removed_flags[choice.id] = true
    elseif choice.action == 'block_code' then M.blocked_codes[choice.id] = true end
    save_filter_database()
    vim.cmd('edit!') -- Simple, standard reload to sync the file once
  end)
end

-- stylua: ignore end
return M
