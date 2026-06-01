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

-- 1. THE LSP HANDLER INTERCEPTOR
-- This intercepts the native textDocument/publishDiagnostics payload from clangd
function M.diagnostic_handler(err, result, ctx, config)
  if err or not result or not result.diagnostics then
    return vim.lsp.handlers['textDocument/publishDiagnostics'](err, result, ctx, config)
  end

  local clean_diagnostics = {}

  for _, diag in ipairs(result.diagnostics) do
    local keep = true
    local msg = diag.message or ''
    local code = diag.code

    -- Rule A: Filter out short alphanumeric compiler codes
    if code and M.blocked_codes[code] then
      keep = false
    end

    -- Rule B: Filter out specific compiler flags in messages
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

  -- Replace the raw clangd payload with our clean, filtered data package
  result.diagnostics = clean_diagnostics

  -- Forward the clean package to Neovim's default LSP handler to render
  vim.lsp.handlers['textDocument/publishDiagnostics'](err, result, ctx, config)
end

-- 2. THE INTERACTIVE SELECTION DASHBOARD
function M.manage_file_diagnostics_interactive()
  local current_buf = vim.api.nvim_get_current_buf()
  local dashboard_items = {}

  local has_active_filters = next(M.blocked_codes) ~= nil or next(M.removed_flags) ~= nil
  if has_active_filters then
    table.insert(dashboard_items, { action = 'reset', display = '💥 Unblock all' })
  end

  -- Note: We read the raw unescaped errors via a background check or active memory pull
  local raw_diagnostics = vim.diagnostic.get(current_buf)
  local unique_active_entries = {}
  local block_options = {}

  for _, diag in ipairs(raw_diagnostics) do
    local code_name = diag.code or ''
    local msg = diag.message or ''

    local unknown_arg = msg:match('argument%s*%p?%s*[\'"]?(%-[%w%-]+)[\'"]?')
      or msg:match('option%s*%p?%s*[\'"]?(%-[%w%-]+)[\'"]?')
      or msg:match('mean%s*%p?%s*[\'"]?(%-[%w%-]+)[\'"]?')

    if unknown_arg then
      local clean_flag = unknown_arg:gsub('[\'"%?]', ''):gsub('%s+$', '')
      if not M.removed_flags[clean_flag] and not unique_active_entries[clean_flag] then
        unique_active_entries[clean_flag] = true
        table.insert(block_options, { action = 'block_flag', id = clean_flag, display = string.format('🔨 Filter compiler flag: [%s]', clean_flag) })
      end
    elseif code_name ~= '' then
      if not M.blocked_codes[code_name] and not unique_active_entries[code_name] then
        unique_active_entries[code_name] = true
        table.insert(block_options, { action = 'block_code', id = code_name, display = string.format('🔒 Suppress Code: [%s]', code_name) })
      end
    end
  end

  table.sort(block_options, function(a, b)
    return a.display < b.display
  end)
  for _, opt in ipairs(block_options) do
    table.insert(dashboard_items, opt)
  end

  vim.ui.select(dashboard_items, {
    prompt = 'LSP Interceptor Dashboard (Press Esc when finished clearing layers)',
    format_item = function(item)
      return item.display
    end,
  }, function(choice)
    -- THE ESCAPE ROUTE: The menu only exits when the user explicitly hits Esc
    if not choice then
      OS.notify('Clangd Automation ✅ Interception matrix updated successfully.')
      return
    end

    -- Process the current item selection
    if choice.action == 'reset' then
      M.blocked_codes = {}
      M.removed_flags = {}
    elseif choice.action == 'block_flag' then
      M.removed_flags[choice.id] = true
    elseif choice.action == 'block_code' then
      M.blocked_codes[choice.id] = true
    elseif choice.action == 'unblock_flag' then
      M.removed_flags[choice.id] = nil
    elseif choice.action == 'unblock_code' then
      M.blocked_codes[choice.id] = nil
    end

    -- Sync to the persistent local project storage database map
    save_filter_database()

    -- 🌟 FIXED: Run the background reload in absolute silence to prevent "Press ENTER" traps
    if vim.api.nvim_buf_is_valid(current_buf) then
      vim.api.nvim_buf_call(current_buf, function()
        -- 1. Backup the user's current messaging configuration flags
        local old_shortmess = vim.o.shortmess

        -- 2. Force Neovim to compress and swallow all command line logging output completely
        vim.o.shortmess = old_shortmess .. 'F'

        -- 3. Execute filesystem synchronization and reloads with absolute silent constraints
        vim.cmd('silent! checktime')
        vim.cmd('silent! edit!')

        -- 4. Restore the user's original message settings right after execution
        vim.o.shortmess = old_shortmess
      end)
    end

    -- Stagger the recursive menu loop slightly (100ms) to allow the new
    -- incoming clean diagnostic payload to land inside Neovim's cache.
    vim.defer_fn(function()
      M.manage_file_diagnostics_interactive()
    end, 100)
  end)
end

-- stylua: ignore end
return M
