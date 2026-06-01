--- stylua: ignore start
local M = {}

-- Force permanent instantiation as empty tables right at the top
M.manual_blocked_codes = {}
M.removed_flags = {}

local root_markers = { 'platformio.ini', '.git' }

local function get_db_path(bufnr)
  bufnr = (bufnr and bufnr ~= 0) and bufnr or vim.api.nvim_get_current_buf()
  local buf_file = vim.api.nvim_buf_get_name(bufnr)
  local project_root = (buf_file ~= '') and vim.fs.root(buf_file, root_markers) or vim.uv.cwd()
  return project_root .. '/.filter.json'
end

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
      for k, v in pairs(data.codes or {}) do
        M.manual_blocked_codes[k] = v
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
    local payload = { codes = M.manual_blocked_codes, flags = M.removed_flags }
    local pretty = require('nvimpio.utils.misc').jsonFormat(payload)
    f:write(pretty)
    f:close()
  end
end

-- Initialize the database snapshot layout on core plugin load safely
load_filter_database(0)

-- =============================================================================
-- THE ROBUST DYNAMIC HANDLER INTERCEPTOR (100% AUTOMATED FLAGS)
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
      -- Automatically target unknown compiler arguments instantly when the server flags them
      if code == 'drv_unknown_argument' or code == 'drv_unknown_argument_with_suggestion' or code == 'fatal_too_many_errors' then
        -- Use an anchor match pattern to capture ONLY the very first word starting
        -- with a dash (-), ignoring any subsequent suggestions or text blocks cleanly.
        local clean_flag = msg:match('(%-[%w%-]+)')

        if clean_flag then
          if not M.removed_flags[clean_flag] then
            M.removed_flags[clean_flag] = true
            automated_discoveries = true
          end
        end
      end
    end
  end

  if automated_discoveries then
    M.save_from_cli(bufnr)
  end

  -- PASS 2: PRESENTATION SCREENING IN RAM
  for _, diag in ipairs(result.diagnostics) do
    local keep = true
    local code = diag.code
    local msg = diag.message or ''

    -- Strip out generic driver flags categories automatically
    if code == 'drv_unknown_argument' or code == 'drv_unknown_argument_with_suggestion' or code == 'fatal_too_many_errors' then
      keep = false
    -- Strip out any secondary codes manually chosen by the user in the panel
    elseif code and M.manual_blocked_codes[code] then
      keep = false
    end

    -- Strip the item if the message text references any learned invalid flag strings
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
-- STABLE MANUAL TOGGLE CONTROL PANEL
-- =============================================================================
function M.manage_file_diagnostics_interactive()
  local current_buf = vim.api.nvim_get_current_buf()
  local dashboard_items = {}

  local has_active_filters = next(M.manual_blocked_codes) ~= nil or next(M.removed_flags) ~= nil
  if has_active_filters then
    table.insert(dashboard_items, { action = 'reset', display = '💥 Clear Filter Database' })
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

  -- SECTION C: LIST ACTIVE BLOCKS FOR UNBLOCKING (Type-Safe string validation)
  local unblock_options = {}
  for key, value in pairs(M.manual_blocked_codes or {}) do
    local code_str = (type(key) == 'string') and key or value
    if type(code_str) == 'string' and code_str ~= '' and not code_str:match('^table:') then
      table.insert(unblock_options, { action = 'unblock_code', id = code_str, display = 'A• 🔓 Remove Manual Filter: [' .. code_str .. ']' })
    end
  end
  for key, value in pairs(M.removed_flags or {}) do
    local flag_str = (type(key) == 'string') and key or value
    if type(flag_str) == 'string' and flag_str ~= '' and not flag_str:match('^table:') then
      table.insert(unblock_options, { action = 'unblock_flag', id = flag_str, display = 'B• 🔓 Remove Flag Filter: [' .. flag_str .. ']' })
    end
  end
  table.sort(unblock_options, function(a, b)
    return a.display < b.display
  end)
  for _, opt in ipairs(unblock_options) do
    table.insert(dashboard_items, opt)
  end

  if #dashboard_items == 0 then
    vim.notify('✅ Clean Slate: No active framework filters found.', vim.log.levels.INFO)
    return
  end

  vim.ui.select(dashboard_items, { prompt = 'Filter Control Panel' }, function(choice)
    if not choice then
      return
    end

    if choice.action == 'reset' then
      M.manual_blocked_codes = {}
      M.removed_flags = {}
      M.save_from_cli(current_buf)
      vim.notify('💥 Filters wiped clean.', vim.log.levels.ERROR)
    elseif choice.action == 'block_code' then
      M.manual_blocked_codes[choice.id] = true
      M.save_from_cli(current_buf)
    elseif choice.action == 'unblock_code' then
      M.manual_blocked_codes[choice.id] = nil
      M.save_from_cli(current_buf)
    elseif choice.action == 'unblock_flag' then
      M.removed_flags[choice.id] = nil
      M.save_from_cli(current_buf)
    end

    vim.diagnostic.show(nil, current_buf)
  end)
end

return M
