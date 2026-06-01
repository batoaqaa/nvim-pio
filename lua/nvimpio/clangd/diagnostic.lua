--- stylua: ignore start
local M = {}

M.manual_blocked_codes = {}
M.removed_flags = {}

local root_markers = { 'platformio.ini', '.git' }
local ui_bufnr = nil
local ui_winnr = nil
local original_bufnr = nil

-- 🌟 UI Refresh Callback Trigger Registry
M.on_diagnostics_updated = nil

local function get_db_path(bufnr)
  bufnr = (bufnr and bufnr ~= 0) and bufnr or vim.api.nvim_get_current_buf()
  local buf_file = vim.api.nvim_buf_get_name(bufnr)
  local project_root = (buf_file ~= '') and vim.fs.root(buf_file, root_markers) or vim.uv.cwd()
  return project_root .. '/.filter.json'
end

local function load_filter_database(bufnr)
  M.manual_blocked_codes = {}
  local json_database_file = get_db_path(bufnr)
  local f = io.open(json_database_file, 'rb')
  if not f then
    return
  end
  local raw_json = f:read('*all')
  f:close()
  if raw_json and raw_json ~= '' then
    local success, data = pcall(vim.json.decode, raw_json)
    if success and data and type(data) == 'table' and type(data.codes) == 'table' then
      for k, v in pairs(data.codes) do
        local code_str = (type(k) == 'string') and k or v
        if type(code_str) == 'string' and code_str ~= '' and not code_str:match('^table:') then
          M.manual_blocked_codes[code_str] = true
        end
      end
    end
  end
end

local function save_filter_database(bufnr)
  local json_database_file = get_db_path(bufnr)
  local f = io.open(json_database_file, 'wb')
  if f then
    if next(M.manual_blocked_codes) == nil then
      f:write('{"codes":null}')
    else
      local payload = { codes = M.manual_blocked_codes }
      local pretty = require('nvimpio.utils.misc').jsonFormat(payload)
      f:write(pretty)
    end
    f:close()
  end
end

load_filter_database(0)

-- =============================================================================
-- 1. THE ROBUST DYNAMIC HANDLER INTERCEPTOR (VOLATILE IN-MEMORY EXTRACTION)
-- =============================================================================
function M.diagnostic_handler(err, result, ctx, config)
  if err or not result or not result.diagnostics then
    return vim.lsp.handlers['textDocument/publishDiagnostics'](err, result, ctx, config)
  end

  local current_buf = vim.uri_to_bufnr(result.uri)
  load_filter_database(current_buf)

  local clean_diagnostics = {}

  -- PASS 1: AUTOMATED IN-MEMORY CAPTURING ONLY (NO DISK POLLUTION)
  for _, diag in ipairs(result.diagnostics) do
    local code = diag.code
    local msg = diag.message or ''

    if code and type(code) == 'string' and code ~= '' then
      if code == 'drv_unknown_argument' or code == 'drv_unknown_argument_with_suggestion' or code == 'fatal_too_many_errors' then
        local clean_flag = msg:match('(%-[%w%-]+)')
        if clean_flag and not M.removed_flags[clean_flag] then
          M.removed_flags[clean_flag] = true
        end
      end
    end
  end

  -- PASS 2: PRESENTATION SCREENING IN RAM
  for _, diag in ipairs(result.diagnostics) do
    local keep = true
    local code = diag.code
    local msg = diag.message or ''

    if code == 'drv_unknown_argument' or code == 'drv_unknown_argument_with_suggestion' or code == 'fatal_too_many_errors' then
      keep = false
    elseif code and M.manual_blocked_codes[code] then
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

  -- 🌟 THE STREAM INTERCEPTOR HANDSHAKE:
  -- The exact microsecond the filtered diagnostic payload completes compilation
  -- and passes through this gateway, execute our UI redraw notification safely!
  if type(M.on_diagnostics_updated) == 'function' then
    M.on_diagnostics_updated()
  end
end

-- =============================================================================
-- 2. PERSISTENT INTERACTIVE SCRATCHPAD UI LAYER (NEVER CLOSES ON SELECTION)
-- =============================================================================
local menu_mappings = {}

local function close_filter_window()
  M.on_diagnostics_updated = nil -- Dissolve callback lifecycle safely
  if ui_winnr and vim.api.nvim_win_is_valid(ui_winnr) then
    vim.api.nvim_win_close(ui_winnr, true)
  end
  ui_winnr = nil
  ui_bufnr = nil
end

local function draw_filter_menu_contents()
  local target_orig_buf = original_bufnr or 0
  if not ui_bufnr or not vim.api.nvim_buf_is_valid(ui_bufnr) or target_orig_buf == 0 then
    return
  end
  load_filter_database(target_orig_buf)

  local lines = { ' 💥 Compiler Mangler Dashboard (Press [q] or [Esc] to Exit) ', string.rep('─', 65), '' }
  menu_mappings = {}

  local has_active_filters = next(M.manual_blocked_codes) ~= nil
  if has_active_filters then
    table.insert(lines, '  [x] 💥 Clear All Active User Filters')
    table.insert(menu_mappings, { action = 'reset' })
  end

  -- Scan live diagnostics directly out of the active compiler namespaces
  local raw_diagnostics = {}
  for _, client in pairs(vim.lsp.get_clients({ bufnr = target_orig_buf })) do
    local namespace = vim.lsp.diagnostic.get_namespace(client.id)
    local client_diags = vim.diagnostic.get(target_orig_buf, { namespace = namespace })
    for _, d in ipairs(client_diags) do
      table.insert(raw_diagnostics, d)
    end
  end
  if #raw_diagnostics == 0 then
    raw_diagnostics = vim.diagnostic.get(target_orig_buf)
  end

  local seen = {}
  local header_added = false
  for _, diag in ipairs(raw_diagnostics) do
    local code_name = diag.code or ''
    if
      code_name ~= ''
      and code_name ~= 'drv_unknown_argument'
      and code_name ~= 'drv_unknown_argument_with_suggestion'
      and code_name ~= 'fatal_too_many_errors'
    then
      if not M.manual_blocked_codes[code_name] and not seen[code_name] then
        if not header_added then
          table.insert(lines, ' Outstanding Errors/Warnings (Select to Block):')
          header_added = true
        end
        seen[code_name] = true
        table.insert(lines, '  [ ] 🔒 Suppress Code: [' .. code_name .. ']')
        table.insert(menu_mappings, { action = 'block_code', id = code_name })
      end
    end
  end

  local unblock_header_added = false
  for key, _ in pairs(M.manual_blocked_codes or {}) do
    if type(key) == 'string' and key ~= '' and not key:match('^table:') then
      if not unblock_header_added then
        table.insert(lines, '')
        table.insert(lines, ' Currently Suppressed Codes (Select to Restore):')
        unblock_header_added = true
      end
      table.insert(lines, '  [*] 🔓 Remove Manual Filter: [' .. key .. ']')
      table.insert(menu_mappings, { action = 'unblock_code', id = key })
    end
  end

  local flag_header_added = false
  for flag, _ in pairs(M.removed_flags or {}) do
    if type(flag) == 'string' and flag ~= '' then
      if not flag_header_added then
        table.insert(lines, '')
        table.insert(lines, ' ⚙️ Automated Driver Flag Protections (Read-Only Logs):')
        flag_header_added = true
      end
      table.insert(lines, '  [-] 📋 [RECORDED FLAG]: ' .. flag)
      table.insert(menu_mappings, { action = 'none' })
    end
  end

  local target_ui_buf = ui_bufnr or 0
  if target_ui_buf ~= 0 and vim.api.nvim_buf_is_valid(target_ui_buf) then
    vim.bo[target_ui_buf].modifiable = true
    vim.api.nvim_buf_set_lines(target_ui_buf, 0, -1, false, lines)
    vim.bo[target_ui_buf].modifiable = false
  end
end

local function handle_menu_selection()
  local current_line = vim.api.nvim_get_current_line() or ''
  local target_buf = original_bufnr or 0

  local action = nil
  local target_id = nil

  if current_line:find('💥 Clear All Active User Filters') then
    action = 'reset'
  elseif current_line:find('🔒 Suppress Code:') then
    action = 'block_code'
    target_id = current_line:match('🔒 Suppress Code:%s*%[([%w%-_]+)%]')
  elseif current_line:find('🔓 Remove Manual Filter:') then
    action = 'unblock_code'
    target_id = current_line:match('🔓 Remove Manual Filter:%s*%[([%w%-_]+)%]')
  end

  if not action or action == 'none' or target_buf == 0 then
    return
  end

  if action == 'reset' then
    M.manual_blocked_codes = {}
    save_filter_database(target_buf)
    vim.notify('💥 User selections wiped clean.', vim.log.levels.ERROR)
  elseif action == 'block_code' and target_id then
    M.manual_blocked_codes[target_id] = true
    save_filter_database(target_buf)
  elseif action == 'unblock_code' and target_id then
    M.manual_blocked_codes[target_id] = nil
    save_filter_database(target_buf)
  end

  -- Mount our explicit synchronous stream listener callback BEFORE refreshing the file context
  M.on_diagnostics_updated = function()
    vim.schedule(function()
      draw_filter_menu_contents()
    end)
  end

  -- Trigger the whisper-quiet asynchronous buffer reload pass
  vim.api.nvim_buf_call(target_buf, function()
    local old_shortmess = vim.o.shortmess
    vim.o.shortmess = old_shortmess .. 'F'
    vim.cmd('silent! checktime')
    vim.cmd('silent! edit!')
    vim.o.shortmess = old_shortmess
  end)
end

function M.manage_file_diagnostics_interactive()
  original_bufnr = vim.api.nvim_get_current_buf()
  local target_orig_buf = original_bufnr or 0
  if target_orig_buf == 0 then
    return
  end

  close_filter_window()

  local width = 70
  local height = 18
  local row = math.ceil((vim.o.lines - height) / 2) - 1
  local col = math.ceil((vim.o.columns - width) / 2) - 1

  ui_bufnr = vim.api.nvim_create_buf(false, true)
  ui_winnr = vim.api.nvim_open_win(ui_bufnr, true, {
    relative = 'editor',
    width = width,
    height = height,
    row = row,
    col = col,
    style = 'minimal',
    border = 'rounded',
    title = ' PlatformIO Exception Manager ',
    title_pos = 'center',
  })

  local target_ui_buf = ui_bufnr or 0
  if target_ui_buf ~= 0 then
    vim.bo[target_ui_buf].bufhidden = 'wipe'
    vim.bo[target_ui_buf].filetype = 'nvimpiomangler'
  end

  local opts = { silent = true, buffer = target_ui_buf }
  vim.keymap.set('n', '', function()
    handle_menu_selection()
  end, opts)
  vim.keymap.set('n', 'q', function()
    close_filter_window()
  end, opts)
  vim.keymap.set('n', '', function()
    close_filter_window()
  end, opts)
  draw_filter_menu_contents()
end
return M

-- --- stylua: ignore start
-- local M = {}
--
-- -- Explicit table instantiation at the absolute top prevents race-condition crashes
-- M.manual_blocked_codes = {}
-- M.removed_flags = {}
--
-- local root_markers = { 'platformio.ini', '.git' }
--
-- -- 1. GET_DB_PATH: Dynamically resolves project workspace paths in memory space safely
-- local function get_db_path(bufnr)
--   bufnr = (bufnr and bufnr ~= 0) and bufnr or vim.api.nvim_get_current_buf()
--   local buf_file = vim.api.nvim_buf_get_name(bufnr)
--   local project_root = (buf_file ~= '') and vim.fs.root(buf_file, root_markers) or vim.uv.cwd()
--   return project_root .. '/.filter.json'
-- end
--
-- -- 2. LOAD_FILTER_DATABASE: Safe hash-table hydration evaluated dynamically per buffer
-- local function load_filter_database(bufnr)
--   M.manual_blocked_codes = {}
--   M.removed_flags = {}
--
--   local json_database_file = get_db_path(bufnr)
--   local f = io.open(json_database_file, 'rb')
--   if not f then
--     return
--   end
--   local raw_json = f:read('*all')
--   f:close()
--
--   if raw_json and raw_json ~= '' then
--     local success, data = pcall(vim.json.decode, raw_json)
--     if success and data and type(data) == 'table' then
--       -- Safely re-hydrate code structures
--       if type(data.codes) == 'table' then
--         for k, v in pairs(data.codes) do
--           local code_str = (type(k) == 'string') and k or v
--           if type(code_str) == 'string' and code_str ~= '' and not code_str:match('^table:') then
--             M.manual_blocked_codes[code_str] = true
--           end
--         end
--       end
--       -- Safely re-hydrate compiler flag structures
--       if type(data.flags) == 'table' then
--         for k, v in pairs(data.flags) do
--           local flag_str = (type(k) == 'string') and k or v
--           if type(flag_str) == 'string' and flag_str ~= '' and not flag_str:match('^table:') then
--             M.removed_flags[flag_str] = true
--           end
--         end
--       end
--     end
--   end
-- end
--
-- -- 3. SAVE_FILTER_DATABASE: Writes explicit object hash-maps down to disk parameters
-- local function save_filter_database(bufnr)
--   local json_database_file = get_db_path(bufnr)
--   local f = io.open(json_database_file, 'wb')
--   if f then
--     local payload = { codes = M.manual_blocked_codes, flags = M.removed_flags }
--     local pretty = require('nvimpio.utils.misc').jsonFormat(payload)
--     f:write(pretty)
--     f:close()
--   end
-- end
--
-- -- Safely trigger an absolute baseline load transaction upon initial module loading
-- load_filter_database(0)
--
-- -- =============================================================================
-- -- 4. THE ROBUST DYNAMIC HANDLER INTERCEPTOR (100% AUTOMATED DRIVER FLAG LOGGING)
-- -- =============================================================================
-- function M.diagnostic_handler(err, result, ctx, config)
--   if err or not result or not result.diagnostics then
--     return vim.lsp.handlers['textDocument/publishDiagnostics'](err, result, ctx, config)
--   end
--
--   local current_buf = vim.uri_to_bufnr(result.uri)
--   load_filter_database(current_buf)
--
--   local clean_diagnostics = {}
--   local automated_discoveries = false
--
--   -- PASS 1: AUTOMATED ZERO-HARDCODE COMPILER DRIVER FLAG CAPTURING
--   for _, diag in ipairs(result.diagnostics) do
--     local code = diag.code
--     local msg = diag.message or ''
--
--     if code and type(code) == 'string' and code ~= '' then
--       if code == 'drv_unknown_argument' or code == 'drv_unknown_argument_with_suggestion' or code == 'fatal_too_many_errors' then
--         local clean_flag = msg:match('(%-[%w%-]+)')
--         if clean_flag and not M.removed_flags[clean_flag] then
--           M.removed_flags[clean_flag] = true
--           automated_discoveries = true
--         end
--       end
--     end
--   end
--
--   if automated_discoveries then
--     save_filter_database(current_buf)
--   end
--
--   -- PASS 2: PRESENTATION SCREENING IN RAM
--   for _, diag in ipairs(result.diagnostics) do
--     local keep = true
--     local code = diag.code
--     local msg = diag.message or ''
--
--     if code == 'drv_unknown_argument' or code == 'drv_unknown_argument_with_suggestion' or code == 'fatal_too_many_errors' then
--       keep = false
--     elseif code and M.manual_blocked_codes[code] then
--       keep = false
--     end
--
--     if keep then
--       for flag, _ in pairs(M.removed_flags) do
--         if msg:find(flag, 1, true) then
--           keep = false
--           break
--         end
--       end
--     end
--
--     if keep then
--       table.insert(clean_diagnostics, diag)
--     end
--   end
--
--   result.diagnostics = clean_diagnostics
--   vim.lsp.handlers['textDocument/publishDiagnostics'](err, result, ctx, config)
-- end
--
-- -- =============================================================================
-- -- 5. PERSISTENT RECURSIVE CONTROL PANEL (STAYS OPEN UNTIL ESC)
-- -- =============================================================================
-- function M.manage_file_diagnostics_interactive()
--   local current_buf = vim.api.nvim_get_current_buf()
--   local dashboard_items = {}
--
--   local has_active_filters = next(M.manual_blocked_codes) ~= nil or next(M.removed_flags) ~= nil
--   if has_active_filters then
--     table.insert(dashboard_items, { action = 'reset', display = '💥 Clear All Active Filters & Records' })
--   end
--
--   -- SECTION B: LIST OUTSTANDING CODES SO YOU CAN CHOOSE WHAT TO BLOCK (e.g. pp_file_not_found)
--   local raw_diagnostics = vim.diagnostic.get(current_buf)
--   local seen = {}
--   for _, diag in ipairs(raw_diagnostics) do
--     local code_name = diag.code or ''
--     if
--       code_name ~= ''
--       and code_name ~= 'drv_unknown_argument'
--       and code_name ~= 'drv_unknown_argument_with_suggestion'
--       and code_name ~= 'fatal_too_many_errors'
--     then
--       if not M.manual_blocked_codes[code_name] and not seen[code_name] then
--         seen[code_name] = true
--         table.insert(dashboard_items, { action = 'block_code', id = code_name, display = '🔒 Suppress Code: [' .. code_name .. ']' })
--       end
--     end
--   end
--   table.sort(dashboard_items, function(a, b)
--     return a.display < b.display
--   end)
--
--   -- SECTION C: LIST ACTIVE BLOCKS FOR REVIEW AND UNBLOCKING
--   local unblock_options = {}
--   for key, value in pairs(M.manual_blocked_codes or {}) do
--     local code_str = (type(key) == 'string') and key or value
--     if type(code_str) == 'string' and code_str ~= '' and not code_str:match('^table:') then
--       table.insert(unblock_options, { action = 'unblock_code', id = code_str, display = '🔓 Remove Manual Filter: [' .. code_str .. ']' })
--     end
--   end
--   for key, value in pairs(M.removed_flags or {}) do
--     local flag_str = (type(key) == 'string') and key or value
--     if type(flag_str) == 'string' and flag_str ~= '' and not flag_str:match('^table:') then
--       table.insert(unblock_options, { action = 'unblock_flag', id = flag_str, display = '📋 [RECORDED FLAG]: ' .. flag_str })
--     end
--   end
--   table.sort(unblock_options, function(a, b)
--     return a.display < b.display
--   end)
--   for _, opt in ipairs(unblock_options) do
--     table.insert(dashboard_items, opt)
--   end
--
--   if #dashboard_items == 0 then
--     vim.notify('✅ Clean Slate: No customizable warnings active.', vim.log.levels.INFO, { title = 'Compiler Mangler' })
--     return
--   end
--
--   -- Draw the core choice prompt container panel
--   vim.ui.select(dashboard_items, {
--     prompt = 'Filter Panel (Press Esc when finished clearing layers)',
--     format_item = function(item)
--       return (type(item) == 'table' and type(item.display) == 'string') and item.display or tostring(item)
--     end,
--   }, function(choice)
--     -- 🌟 User explicitly cancels or hits Esc: clean workspace break exit out of loop
--     if not choice then
--       return
--     end
--
--     if choice.action == 'reset' then
--       M.manual_blocked_codes = {}
--       M.removed_flags = {}
--       save_filter_database(current_buf)
--       vim.notify('💥 Filters wiped clean.', vim.log.levels.ERROR)
--     elseif choice.action == 'block_code' then
--       M.manual_blocked_codes[choice.id] = true
--       save_filter_database(current_buf)
--     elseif choice.action == 'unblock_code' then
--       M.manual_blocked_codes[choice.id] = nil
--       save_filter_database(current_buf)
--     elseif choice.action == 'unblock_flag' then
--       M.removed_flags[choice.id] = nil
--       save_filter_database(current_buf)
--     end
--
--     -- 🌟 THE RECURSIVE VEHICLE:
--     -- We schedule a buffer update and immediately call the menu function right back!
--     -- This recalculates outstanding diagnostics on the next frame and holds the window open.
--     vim.schedule(function()
--       if vim.api.nvim_buf_is_valid(current_buf) then
--         vim.api.nvim_buf_call(current_buf, function()
--           local old_shortmess = vim.o.shortmess
--           vim.o.shortmess = old_shortmess .. 'F'
--           vim.cmd('silent! checktime')
--           vim.cmd('silent! edit!')
--           vim.o.shortmess = old_shortmess
--         end)
--       end
--
--       -- Loop back and re-open the updated menu panel seamlessly!
--       M.manage_file_diagnostics_interactive()
--     end)
--   end)
-- end
--
-- return M
