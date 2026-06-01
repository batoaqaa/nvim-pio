--- stylua: ignore start
local M = {}

M.manual_blocked_codes = {}
M.removed_flags = {}

local markers = { 'platformio.ini', '.git' }

-- 1. Get absolute filter file path safely
local function get_db_path(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local f = vim.api.nvim_buf_get_name(bufnr)
  local root = (f ~= '') and vim.fs.root(f, markers) or vim.uv.cwd()
  return root .. '/.filter.json'
end

-- 2. Load persistent json suppression arrays
local function load_filter_database(bufnr)
  M.manual_blocked_codes = {}
  local path = get_db_path(bufnr)
  local f = io.open(path, 'rb')
  if not f then
    return
  end
  local raw = f:read('*all')
  f:close()
  if raw and raw ~= '' then
    local ok, data = pcall(vim.json.decode, raw)
    if ok and data and type(data.codes) == 'table' then
      for k, v in pairs(data.codes) do
        local s = (type(k) == 'string') and k or v
        if type(s) == 'string' and s ~= '' then
          M.manual_blocked_codes[s] = true
        end
      end
    end
  end
end

-- 3. Write active selections straight down to disk
local function save_filter_database(bufnr)
  local path = get_db_path(bufnr)
  local f = io.open(path, 'wb')
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

-- =====================================================
-- 4. DYNAMIC STREAM INTERCEPTOR (VOLATILE RAM-ONLY)
-- =====================================================
function M.diagnostic_handler(err, result, ctx, config)
  if err or not result or not result.diagnostics then
    return vim.lsp.handlers['textDocument/publishDiagnostics'](err, result, ctx, config)
  end

  local current_buf = vim.uri_to_bufnr(result.uri)
  load_filter_database(current_buf)

  local clean_diagnostics = {}

  for _, diag in ipairs(result.diagnostics) do
    local keep = true
    local code = diag.code
    local msg = diag.message or ''

    local is_drv = code == 'drv_unknown_argument' or code == 'drv_unknown_argument_with_suggestion' or code == 'fatal_too_many_errors'

    if is_drv then
      keep = false
      local f = msg:match('(%-[%w%-]+)')
      if f then
        M.removed_flags[f] = true
      end
    elseif code and M.manual_blocked_codes[code] then
      keep = false
    end

    if keep then
      table.insert(clean_diagnostics, diag)
    end
  end

  result.diagnostics = clean_diagnostics
  vim.lsp.handlers['textDocument/publishDiagnostics'](err, result, ctx, config)
end

-- =====================================================
-- 5. PERSISTENT RECURSIVE DROPDOWN FILTER CONTROL PANEL
-- =====================================================
function M.manage_file_diagnostics_interactive()
  local bufnr = vim.api.nvim_get_current_buf()
  local items = {}

  if next(M.manual_blocked_codes) then
    table.insert(items, { action = 'reset', text = '💥 Clear All Active User Filters' })
  end

  -- Scan active warnings out of current buffer namespaces
  local raw_diagnostics = {}
  for _, client in pairs(vim.lsp.get_clients({ bufnr = bufnr })) do
    local namespace = vim.lsp.diagnostic.get_namespace(client.id)
    local client_diags = vim.diagnostic.get(bufnr, { namespace = namespace })
    for _, d in ipairs(client_diags) do
      table.insert(raw_diagnostics, d)
    end
  end
  if #raw_diagnostics == 0 then
    raw_diagnostics = vim.diagnostic.get(bufnr)
  end

  local seen = {}
  for _, d in ipairs(raw_diagnostics) do
    local c = d.code or ''
    if c ~= '' and c ~= 'drv_unknown_argument' and c ~= 'drv_unknown_argument_with_suggestion' and c ~= 'fatal_too_many_errors' then
      if not M.manual_blocked_codes[c] and not seen[c] then
        seen[c] = true
        table.insert(items, { action = 'block', id = c, text = '🔒 Suppress Code: [' .. c .. ']' })
      end
    end
  end

  -- Show active suppressed options for toggling back
  for k, _ in pairs(M.manual_blocked_codes) do
    table.insert(items, { action = 'unblock', id = k, text = '🔓 Remove Manual Filter: [' .. k .. ']' })
  end

  -- Print read-only logs at the bottom
  for f, _ in pairs(M.removed_flags) do
    table.insert(items, { action = 'none', text = '⚙️ [AUTOMATED BLOCK]: ' .. f })
  end

  -- 🌟 FIXED EARLY EXIT BOUNDARY:
  -- We only terminate if the complete option array is fully empty.
  -- If you have historical blocks active, the menu stays open!
  if #items == 0 then
    vim.notify('✅ Clean Slate: No active filters.', vim.log.levels.INFO)
    return
  end

  -- Render via native modern Neovim picker loop
  vim.ui.select(items, {
    prompt = 'Filter Panel (Press Esc to finish)',
    format_item = function(item)
      return item.text
    end,
  }, function(choice)
    if not choice or choice.action == 'none' then
      return
    end

    if choice.action == 'reset' then
      M.manual_blocked_codes = {}
    elseif choice.action == 'block' then
      M.manual_blocked_codes[choice.id] = true
    elseif choice.action == 'unblock' then
      M.manual_blocked_codes[choice.id] = nil
    end

    save_filter_database(bufnr)

    -- Force reactive synchronization via the native event pipeline
    vim.schedule(function()
      if vim.api.nvim_buf_is_valid(bufnr) then
        local refresh_group = vim.api.nvim_create_augroup('NvimPioMenuRefreshGroup', { clear = true })
        vim.api.nvim_create_autocmd('DiagnosticChanged', {
          group = refresh_group,
          buffer = bufnr,
          callback = function()
            vim.api.nvim_del_augroup_by_id(refresh_group)
            M.manage_file_diagnostics_interactive()
          end,
        })

        -- Execute the whisper-quiet asynchronous buffer reload pass
        vim.api.nvim_buf_call(bufnr, function()
          local old_shortmess = vim.o.shortmess
          vim.o.shortmess = old_shortmess .. 'F'
          vim.cmd('silent! checktime')
          vim.cmd('silent! edit!')
          vim.o.shortmess = old_shortmess
        end)
      end
    end)
  end)
end

-- stylua: ignore end
return M

-- -- long
-- --- stylua: ignore start
-- local M = {}
--
-- -- Private state encapsulation maps
-- local state = {
--   manual_blocked_codes = {},
--   removed_flags = {},
--   ui_bufnr = nil,
--   ui_winnr = nil,
--   original_bufnr = nil,
--   metadata = {},
-- }
--
-- M.on_diagnostics_updated = nil
--
-- local root_markers = { 'platformio.ini', '.git' }
-- local ns_id = vim.api.nvim_create_namespace('NvimPioMangler')
--
-- -- 1. GET_DB_PATH: Tracks root files safely
-- local function get_db_path(bufnr)
--   bufnr = (bufnr and bufnr ~= 0) and bufnr or vim.api.nvim_get_current_buf()
--   local buf_file = vim.api.nvim_buf_get_name(bufnr)
--   local project_root = (buf_file ~= '') and vim.fs.root(buf_file, root_markers) or vim.uv.cwd()
--   return project_root .. '/.filter.json'
-- end
--
-- -- 2. LOAD_FILTER_DATABASE: Safe memory hydration
-- local function load_filter_database(bufnr)
--   state.manual_blocked_codes = {}
--   local json_database_file = get_db_path(bufnr)
--   local f = io.open(json_database_file, 'rb')
--   if not f then
--     return
--   end
--   local raw_json = f:read('*all')
--   f:close()
--   if raw_json and raw_json ~= '' then
--     local success, data = pcall(vim.json.decode, raw_json)
--     local has_data = success and data and type(data) == 'table' and type(data.codes) == 'table'
--     if has_data then
--       for k, v in pairs(data.codes) do
--         local code_str = (type(k) == 'string') and k or v
--         local is_valid = type(code_str) == 'string' and code_str ~= '' and not code_str:match('^table:')
--         if is_valid then
--           state.manual_blocked_codes[code_str] = true
--         end
--       end
--     end
--   end
-- end
--
-- -- 3. SAVE_FILTER_DATABASE: Persists hash tables
-- local function save_filter_database(bufnr)
--   local json_database_file = get_db_path(bufnr)
--   local f = io.open(json_database_file, 'wb')
--   if f then
--     if next(state.manual_blocked_codes) == nil then
--       f:write('{"codes":null}')
--     else
--       local payload = {
--         codes = state.manual_blocked_codes,
--       }
--       local pretty = require('nvimpio.utils.misc').jsonFormat(payload)
--       f:write(pretty)
--     end
--     f:close()
--   end
-- end
--
-- load_filter_database(0)
--
-- -- =====================================================
-- -- 4. THE ROBUST DYNAMIC HANDLER INTERCEPTOR (RAM-ONLY)
-- -- =====================================================
-- function M.diagnostic_handler(err, result, ctx, config)
--   if err or not result or not result.diagnostics then
--     return vim.lsp.handlers['textDocument/publishDiagnostics'](err, result, ctx, config)
--   end
--
--   local current_buf = vim.uri_to_bufnr(result.uri)
--   load_filter_database(current_buf)
--
--   local clean_diagnostics = {}
--
--   -- PASS 1: AUTOMATED VOLATILE IN-MEMORY CAPTURING
--   for _, diag in ipairs(result.diagnostics) do
--     local code = diag.code
--     local msg = diag.message or ''
--
--     if code and type(code) == 'string' and code ~= '' then
--       local is_drv_fail = code == 'drv_unknown_argument' or code == 'drv_unknown_argument_with_suggestion' or code == 'fatal_too_many_errors'
--       if is_drv_fail then
--         local clean_flag = msg:match('(%-[%w%-]+)')
--         if clean_flag and not state.removed_flags[clean_flag] then
--           state.removed_flags[clean_flag] = true
--         end
--       end
--     end
--   end
--
--   -- PASS 2: PRESENTATION SCREENING IN RAM
--   for _, diag in ipairs(result.diagnostics) do
--     local keep = true
--     local code = diag.code
--     local msg = diag.message or ''
--
--     local is_drv_fail = code == 'drv_unknown_argument' or code == 'drv_unknown_argument_with_suggestion' or code == 'fatal_too_many_errors'
--
--     if is_drv_fail then
--       keep = false
--     elseif code and state.manual_blocked_codes[code] then
--       keep = false
--     end
--
--     if keep then
--       for flag, _ in pairs(state.removed_flags) do
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
--
--   if type(M.on_diagnostics_updated) == 'function' then
--     M.on_diagnostics_updated()
--   end
-- end
--
-- -- =====================================================
-- -- 5. INTERACTIVE SCRATCHPAD UI AND CANVASES LAYER
-- -- =====================================================
-- local menu_mappings = {}
--
-- local function close_filter_window()
--   M.on_diagnostics_updated = nil
--   pcall(vim.api.nvim_del_augroup_by_name, 'NvimPioModalLock')
--   if state.ui_winnr and vim.api.nvim_win_is_valid(state.ui_winnr) then
--     vim.api.nvim_win_close(state.ui_winnr, true)
--   end
--   state.ui_winnr = nil
--   state.ui_bufnr = nil
-- end
--
-- local function draw_filter_menu_contents()
--   local target_orig_buf = state.original_bufnr or 0
--   local invalid_ui = not state.ui_bufnr or not vim.api.nvim_buf_is_valid(state.ui_bufnr) or target_orig_buf == 0
--   if invalid_ui then
--     return
--   end
--   load_filter_database(target_orig_buf)
--
--   local border_ln = string.rep('─', 65)
--   local lines = {
--     ' 💥 PlatformIO Exception Dashboard ([q] / [Esc] to Exit) ',
--     border_ln,
--     '',
--   }
--
--   vim.api.nvim_buf_clear_namespace(state.ui_bufnr, ns_id, 0, -1)
--   menu_mappings = {}
--
--   local has_active_filters = next(state.manual_blocked_codes) ~= nil
--   if has_active_filters then
--     table.insert(lines, '  [x] 💥 Clear All Active User Filters')
--     table.insert(menu_mappings, { action = 'reset' })
--   end
--
--   local raw_diagnostics = {}
--   local active_clients = vim.lsp.get_clients({ bufnr = target_orig_buf })
--   for _, client in pairs(active_clients) do
--     local namespace = vim.lsp.diagnostic.get_namespace(client.id)
--     local client_diags = vim.diagnostic.get(target_orig_buf, { namespace = namespace })
--     for _, d in ipairs(client_diags) do
--       table.insert(raw_diagnostics, d)
--     end
--   end
--   if #raw_diagnostics == 0 then
--     raw_diagnostics = vim.diagnostic.get(target_orig_buf)
--   end
--
--   local seen = {}
--   local header_added = false
--   for _, diag in ipairs(raw_diagnostics) do
--     local code_name = diag.code or ''
--     local is_drv_fail = code_name == 'drv_unknown_argument' or code_name == 'drv_unknown_argument_with_suggestion' or code_name == 'fatal_too_many_errors'
--
--     if code_name ~= '' and not is_drv_fail then
--       if not state.manual_blocked_codes[code_name] and not seen[code_name] then
--         if not header_added then
--           table.insert(lines, ' Outstanding Warnings (Select to Block):')
--           header_added = true
--         end
--         seen[code_name] = true
--         table.insert(lines, '  [ ] 🔒 Suppress Code: [' .. code_name .. ']')
--         table.insert(menu_mappings, {
--           action = 'block_code',
--           id = code_name,
--         })
--       end
--     end
--   end
--
--   local unblock_header_added = false
--   for key, _ in pairs(state.manual_blocked_codes or {}) do
--     local is_valid_str = type(key) == 'string' and key ~= '' and not key:match('^table:')
--     if is_valid_str then
--       if not unblock_header_added then
--         table.insert(lines, '')
--         table.insert(lines, ' Suppressed Codes (Select to Restore):')
--         unblock_header_added = true
--       end
--       table.insert(lines, '  [*] 🔓 Remove Manual Filter: [' .. key .. ']')
--       table.insert(menu_mappings, {
--         action = 'unblock_code',
--         id = key,
--       })
--     end
--   end
--
--   local flag_header_added = false
--   for flag, _ in pairs(state.removed_flags or {}) do
--     if type(flag) == 'string' and flag ~= '' then
--       if not flag_header_added then
--         table.insert(lines, '')
--         table.insert(lines, ' ⚙️ Automated Flag Records (Read-Only):')
--         flag_header_added = true
--       end
--       table.insert(lines, '  [-] 📋 [RECORDED FLAG]: ' .. flag)
--       table.insert(menu_mappings, { action = 'none' })
--     end
--   end
--
--   local target_ui_buf = state.ui_bufnr or 0
--   if target_ui_buf ~= 0 and vim.api.nvim_buf_is_valid(target_ui_buf) then
--     vim.bo[target_ui_buf].modifiable = true
--     vim.api.nvim_buf_set_lines(target_ui_buf, 0, -1, false, lines)
--     vim.bo[target_ui_buf].modifiable = false
--
--     vim.api.nvim_buf_set_extmark(target_ui_buf, ns_id, 0, 0, { end_line = 1, hl_group = 'Title' })
--     vim.api.nvim_buf_set_extmark(target_ui_buf, ns_id, 1, 0, { end_line = 2, hl_group = 'Comment' })
--
--     for idx, text in ipairs(lines) do
--       local line_pos = idx - 1
--       local ext_opts = { end_line = idx }
--       if text:find('^ Outstanding') then
--         ext_opts.hl_group = 'DiagnosticWarn'
--         vim.api.nvim_buf_set_extmark(target_ui_buf, ns_id, line_pos, 0, ext_opts)
--       elseif text:find('^ Suppressed') then
--         ext_opts.hl_group = 'DiagnosticOk'
--         vim.api.nvim_buf_set_extmark(target_ui_buf, ns_id, line_pos, 0, ext_opts)
--       elseif text:find('^ ⚙️') or text:find('^  %[%-%]') then
--         ext_opts.hl_group = 'Comment'
--         vim.api.nvim_buf_set_extmark(target_ui_buf, ns_id, line_pos, 0, ext_opts)
--       end
--     end
--   end
-- end
--
-- local function handle_menu_selection()
--   local current_line = vim.api.nvim_get_current_line() or ''
--   local target_buf = state.original_bufnr or 0
--
--   local action = nil
--   local target_id = nil
--
--   if current_line:find('💥 Clear All Active User Filters') then
--     action = 'reset'
--   elseif current_line:find('🔒 Suppress Code:') then
--     action = 'block_code'
--     target_id = current_line:match('🔒 Suppress Code:%s*%[([%w%-_]+)%]')
--   elseif current_line:find('🔓 Remove Manual Filter:') then
--     action = 'unblock_code'
--     target_id = current_line:match('🔓 Remove Manual Filter:%s*%[([%w%-_]+)%]')
--   end
--
--   if not action or action == 'none' or target_buf == 0 then
--     return
--   end
--
--   if action == 'reset' then
--     state.manual_blocked_codes = {}
--     save_filter_database(target_buf)
--     vim.notify('💥 User selections wiped clean.', vim.log.levels.ERROR)
--   elseif action == 'block_code' and target_id then
--     state.manual_blocked_codes[target_id] = true
--     save_filter_database(target_buf)
--   elseif action == 'unblock_code' and target_id then
--     state.manual_blocked_codes[target_id] = nil
--     save_filter_database(target_buf)
--   end
--
--   M.on_diagnostics_updated = function()
--     vim.schedule(function()
--       draw_filter_menu_contents()
--     end)
--   end
--
--   vim.api.nvim_buf_call(target_buf, function()
--     local old_shortmess = vim.o.shortmess
--     vim.o.shortmess = old_shortmess .. 'F'
--     vim.cmd('silent! checktime')
--     vim.cmd('silent! edit!')
--     vim.o.shortmess = old_shortmess
--   end)
-- end
--
-- function M.manage_file_diagnostics_interactive()
--   state.original_bufnr = vim.api.nvim_get_current_buf()
--   local target_orig_buf = state.original_bufnr or 0
--   if target_orig_buf == 0 then
--     return
--   end
--
--   close_filter_window()
--
--   local width = 70
--   local height = 18
--   local row = math.ceil((vim.o.lines - height) / 2) - 1
--   local col = math.ceil((vim.o.columns - width) / 2) - 1
--
--   state.ui_bufnr = vim.api.nvim_create_buf(false, true)
--   state.ui_winnr = vim.api.nvim_open_win(state.ui_bufnr, true, {
--     relative = 'editor',
--     width = width,
--     height = height,
--     row = row,
--     col = col,
--     style = 'minimal',
--     border = 'rounded',
--     title = ' Exception Manager ',
--     title_pos = 'center',
--   })
--
--   local target_ui_buf = state.ui_bufnr or 0
--   local target_ui_win = state.ui_winnr or 0
--   if target_ui_buf ~= 0 then
--     vim.bo[target_ui_buf].bufhidden = 'wipe'
--     vim.bo[target_ui_buf].filetype = 'nvimpiomangler'
--   end
--
--   local lock_grp = vim.api.nvim_create_augroup('NvimPioModalLock', { clear = true })
--
--   vim.api.nvim_create_autocmd('WinLeave', {
--     group = lock_grp,
--     callback = function()
--       vim.schedule(function()
--         local win_valid = target_ui_win ~= 0 and vim.api.nvim_win_is_valid(target_ui_win)
--         if win_valid then
--           vim.api.nvim_set_current_win(target_ui_win)
--         end
--       end)
--     end,
--   })
--
--   vim.api.nvim_create_autocmd('BufWipeout', {
--     group = lock_grp,
--     buffer = target_ui_buf,
--     callback = function()
--       M.on_diagnostics_updated = nil
--       pcall(vim.api.nvim_del_augroup_by_name, 'NvimPioModalLock')
--       state.ui_winnr = nil
--       state.ui_bufnr = nil
--     end,
--   })
--
--   local opts = {
--     silent = true,
--     buffer = target_ui_buf,
--   }
--   vim.keymap.set('n', '<CR>', function()
--     handle_menu_selection()
--   end, opts)
--   vim.keymap.set('n', 'q', function()
--     close_filter_window()
--   end, opts)
--   vim.keymap.set('n', '<Esc>', function()
--     close_filter_window()
--   end, opts)
--
--   draw_filter_menu_contents()
-- end
--
-- return M
