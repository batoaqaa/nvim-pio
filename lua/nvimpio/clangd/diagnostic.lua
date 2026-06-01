--- stylua: ignore start
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

  -- SECTION A: MASTER RESET OPTION
  local has_active_filters = next(M.blocked_codes) ~= nil or next(M.removed_flags) ~= nil
  if has_active_filters then
    table.insert(dashboard_items, { action = 'reset', display = '💥 Unblock all' })
  end

  -- SECTION B: EXTRACT ACTIVE DIAGNOSTICS FOR MENU SELECTION
  local raw_diagnostics = vim.diagnostic.get(current_buf)
  local unique_active_entries = {}
  local block_options = {}

  for _, diag in ipairs(raw_diagnostics) do
    local code_name = diag.code or ''
    local msg = diag.message or ''
    local unknown_arg = msg:match('argument%s*%p?%s*[\'"]?(%-[%w%-]+)[\'"]?') or msg:match('option%s*%p?%s*[\'"]?(%-[%w%-]+)[\'"]?')

    if unknown_arg then
      local clean_flag = unknown_arg:gsub('[\'"%?]', ''):gsub('%s+$', '')
      if not M.removed_flags[clean_flag] and not unique_active_entries[clean_flag] then
        unique_active_entries[clean_flag] = true
        table.insert(block_options, { action = 'block_flag', id = clean_flag, display = '🔨 Filter flag: ' .. clean_flag })
      end
    elseif code_name ~= '' and not M.blocked_codes[code_name] and not unique_active_entries[code_name] then
      unique_active_entries[code_name] = true
      table.insert(block_options, { action = 'block_code', id = code_name, display = '🔒 Suppress Code: ' .. code_name })
    end
  end
  table.sort(block_options, function(a, b)
    return a.display < b.display
  end)
  for _, opt in ipairs(block_options) do
    table.insert(dashboard_items, opt)
  end

  -- SECTION C: CURRENTLY BLOCKED ITEMS FOR UNBLOCKING (Type-Safe Evaluation)
  local unblock_options = {}

  -- Handle removed_flags loop safely regardless of dictionary or array layout formats
  for key, value in pairs(M.removed_flags or {}) do
    local flag_str = (type(key) == 'string') and key or value
    if type(flag_str) == 'string' and flag_str ~= '' and not flag_str:match('^table:') then
      table.insert(unblock_options, { action = 'unblock_flag', id = flag_str, display = 'A•🔓 RESTORE Flag: [' .. flag_str .. ']' })
    end
  end

  -- Handle blocked_codes loop safely
  for key, value in pairs(M.blocked_codes or {}) do
    local code_str = (type(key) == 'string') and key or value
    if type(code_str) == 'string' and code_str ~= '' and not code_str:match('^table:') then
      table.insert(unblock_options, { action = 'unblock_code', id = code_str, display = 'B•🔓 ACTIVATE Diagnostic Code: [' .. code_str .. ']' })
    end
  end

  table.sort(unblock_options, function(a, b)
    return a.display < b.display
  end)
  for _, opt in ipairs(unblock_options) do
    table.insert(dashboard_items, opt)
  end

  if #dashboard_items == 0 then
    vim.notify('✅ Complete Parity: No outstanding compilation exceptions found.', vim.log.levels.INFO, { title = 'Compiler Mangler' })
    return
  end

  vim.ui.select(dashboard_items, {
    prompt = 'Filter Panel (Select item to toggle suppression state)',
    format_item = function(item)
      return item.display
    end,
  }, function(choice)
    if not choice then
      return
    end

    if choice.action == 'reset' then
      -- 1. STAGE A: Wipe all in-memory registers completely
      M.blocked_codes = {}
      M.removed_flags = {}

      -- 2. STAGE B: Purely truncate the project configuration file back to an empty baseline on disk
      local json_database_file = get_db_path(current_buf)
      local f = io.open(json_database_file, 'wb')
      if f then
        f:write('{"codes":{},"flags":{}}')
        f:close()
      end

      -- 3. STAGE C: Temporarily kill the automated background group listener for this buffer
      --    This blocks the LspAttach autocmd from intercepting errors during the reset phase!
      pcall(vim.api.nvim_del_augroup_by_name, 'NvimPioFirstSweepGroup_' .. current_buf)

      vim.notify('💥 Framework settings wiped clean. original compiler profiles restored.', vim.log.levels.ERROR, { title = 'Compiler Mangler' })
    elseif choice.action == 'block_flag' then
      M.removed_flags[choice.id] = true
    elseif choice.action == 'block_code' then
      M.blocked_codes[choice.id] = true
    elseif choice.action == 'unblock_flag' then
      M.removed_flags[choice.id] = nil
    elseif choice.action == 'unblock_code' then
      M.blocked_codes[choice.id] = nil
    end

    -- Only run standard save transactions for non-reset choice flows
    if choice.action ~= 'reset' then
      M.save_from_cli(current_buf)
    end

    -- Force a silent buffer reload to pull your updated workspace settings visually
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
end
-- stylua: ignore end

return M
