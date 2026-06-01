--- stylua: ignore start
local M = {}

M.manual_blocked_codes = {}
M.removed_flags = {}

local markers = { 'platformio.ini', '.git' }

-- 1. Get filter file path safely
local function get_db_path(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local f = vim.api.nvim_buf_get_name(bufnr)
  local r = (f ~= '') and vim.fs.root(f, markers) or vim.uv.cwd()
  return r .. '/.filter.json'
end

-- 2. Load persistent suppression codes
local function load_db(bufnr)
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
    local check = ok and data and type(data.codes) == 'table'
    if check then
      for k, v in pairs(data.codes) do
        local s = (type(k) == 'string') and k or v
        if type(s) == 'string' and s ~= '' then
          M.manual_blocked_codes[s] = true
        end
      end
    end
  end
end

-- 3. Write user parameters to disk
local function save_db(bufnr)
  local path = get_db_path(bufnr)
  local f = io.open(path, 'wb')
  if f then
    local payload = { codes = M.manual_blocked_codes }
    f:write(vim.json.encode(payload))
    f:close()
  end
end

load_db(0)

-- =====================================================
-- 4. DYNAMIC HANDLER INTERCEPTOR (STABLE NATIVE LAYER)
-- =====================================================
function M.diagnostic_handler(err, result, ctx, config)
  if err or not result or not result.diagnostics then
    return vim.lsp.handlers['textDocument/publishDiagnostics'](err, result, ctx, config)
  end

  local bufnr = vim.uri_to_bufnr(result.uri)
  load_db(bufnr)

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

  -- 🌟 FIXED LIVE PRESENTATION MASK:
  -- Dynamically look up the clangd client namespace and force an update pass!
  vim.schedule(function()
    if vim.api.nvim_buf_is_valid(bufnr) then
      for _, client in pairs(vim.lsp.get_clients({ bufnr = bufnr })) do
        if client.name == 'clangd' then
          local ns = vim.lsp.diagnostic.get_namespace(client.id)
          vim.diagnostic.show(ns, bufnr, nil, {
            filter = function(d)
              return not (d.code and M.manual_blocked_codes[d.code])
            end,
          })
        end
      end
    end
  end)
end

-- =====================================================
-- 5. PERSISTENT RECURSIVE CONTROL PANEL ENGINE
-- =====================================================
function M.manage_file_diagnostics_interactive()
  local bufnr = vim.api.nvim_get_current_buf()
  local items = {}

  if next(M.manual_blocked_codes) then
    table.insert(items, { action = 'reset', text = '💥 Clear All Active User Filters' })
  end

  local raw_diagnostics = vim.diagnostic.get(bufnr)
  local seen = {}
  for _, d in ipairs(raw_diagnostics) do
    local c = d.code or ''
    if c ~= '' and c ~= 'drv_unknown_argument' and c ~= 'fatal_too_many_errors' then
      if not M.manual_blocked_codes[c] and not seen[c] then
        seen[c] = true
        table.insert(items, { action = 'block', id = c, text = '🔒 Suppress Code: [' .. c .. ']' })
      end
    end
  end

  for k, _ in pairs(M.manual_blocked_codes) do
    table.insert(items, { action = 'unblock', id = k, text = '🔓 Remove Manual Filter: [' .. k .. ']' })
  end

  for f, _ in pairs(M.removed_flags) do
    table.insert(items, { action = 'none', text = '⚙️ [AUTOMATED BLOCK]: ' .. f })
  end

  if #items == 0 then
    vim.notify('✅ Clean Slate: No active filters.', vim.log.levels.INFO)
    return
  end

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

    save_db(bufnr)

    -- 🌟 FIXED TIMING RE-SYNC:
    -- Force-apply the presentation filters straight into the active clangd namespace.
    -- This provides instantaneous 0ms frame updates on your screen layout!
    vim.schedule(function()
      if vim.api.nvim_buf_is_valid(bufnr) then
        for _, client in pairs(vim.lsp.get_clients({ bufnr = bufnr })) do
          if client.name == 'clangd' then
            local ns = vim.lsp.diagnostic.get_namespace(client.id)
            vim.diagnostic.show(ns, bufnr, nil, {
              filter = function(d)
                return not (d.code and M.manual_blocked_codes[d.code])
              end,
            })
          end
        end
      end

      M.manage_file_diagnostics_interactive()
    end)
  end)
end

-- stylua: ignore end
return M

-- -- long
-- --- stylua: ignore start
-- local M = {}
--
-- local state = {
--   codes = {},
--   flags = {},
--   uibuf = nil,
--   uiwin = nil,
--   origbuf = nil,
-- }
-- M.on_updated = nil
--
-- local markers = { 'platformio.ini', '.git' }
-- local ns = vim.api.nvim_create_namespace('Pio')
--
-- -- 1. Path resolver helper
-- local function get_db_path(bufnr)
--   bufnr = bufnr or vim.api.nvim_get_current_buf()
--   local f = vim.api.nvim_buf_get_name(bufnr)
--   local root = (f ~= '') and vim.fs.root(f, markers) or vim.uv.cwd()
--   return root .. '/.filter.json'
-- end
--
-- -- 2. Database loading engine
-- local function load_db(bufnr)
--   state.codes = {}
--   local path = get_db_path(bufnr)
--   local f = io.open(path, 'rb')
--   if not f then
--     return
--   end
--   local raw = f:read('*all')
--   f:close()
--   if raw and raw ~= '' then
--     local ok, data = pcall(vim.json.decode, raw)
--     if ok and data and type(data.codes) == 'table' then
--       for k, v in pairs(data.codes) do
--         local s = (type(k) == 'string') and k or v
--         if type(s) == 'string' and s ~= '' then
--           state.codes[s] = true
--         end
--       end
--     end
--   end
-- end
--
-- -- 3. Database saving engine
-- local function save_db(bufnr)
--   local path = get_db_path(bufnr)
--   local f = io.open(path, 'wb')
--   if f then
--     if next(state.codes) == nil then
--       f:write('{"codes":null}')
--     else
--       local payload = { codes = state.codes }
--       local pretty = require('nvimpio.utils.misc').jsonFormat(payload)
--       f:write(pretty)
--     end
--     f:close()
--   end
-- end
--
-- load_db(0)
--
-- -- =====================================================
-- -- 4. DYNAMIC STREAM INTERCEPTOR (VOLATILE RAM-ONLY)
-- -- =====================================================
-- function M.diagnostic_handler(err, result, ctx, config)
--   if err or not result or not result.diagnostics then
--     return vim.lsp.handlers['textDocument/publishDiagnostics'](err, result, ctx, config)
--   end
--
--   local current_buf = vim.uri_to_bufnr(result.uri)
--   load_db(current_buf)
--
--   local clean_diagnostics = {}
--
--   for _, diag in ipairs(result.diagnostics) do
--     local keep = true
--     local code = diag.code
--     local msg = diag.message or ''
--
--     local is_drv = code == 'drv_unknown_argument' or code == 'drv_unknown_argument_with_suggestion' or code == 'fatal_too_many_errors'
--
--     if is_drv then
--       keep = false
--       local f = msg:match('(%-[%w%-]+)')
--       if f then
--         state.flags[f] = true
--       end
--     elseif code and state.codes[code] then
--       keep = false
--     end
--
--     if keep then
--       for flag, _ in pairs(state.flags) do
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
--   if type(M.on_updated) == 'function' then
--     M.on_updated()
--   end
-- end
--
-- -- =====================================================
-- -- 5. PERSISTENT FLOATING CANVAS CONTROL PANEL ENGINE
-- -- =====================================================
-- local function close_win()
--   M.on_updated = nil
--   pcall(vim.api.nvim_del_augroup_by_name, 'PioLock')
--   if state.uiwin and vim.api.nvim_win_is_valid(state.uiwin) then
--     vim.api.nvim_win_close(state.uiwin, true)
--   end
--   state.uiwin = nil
--   state.uibuf = nil
-- end
--
-- local function draw_menu()
--   local orig = state.original_bufnr or 0
--   if not state.uibuf or not vim.api.nvim_buf_is_valid(state.uibuf) or orig == 0 then
--     return
--   end
--   load_db(orig)
--
--   local lines = { ' 💥 PlatformIO Filter Dashboard (Press [q] / [Esc] to Exit) ', string.rep('─', 65), '' }
--   vim.api.nvim_buf_clear_namespace(state.uibuf, ns, 0, -1)
--
--   if next(state.codes) then
--     table.insert(lines, '  [x] 💥 Clear All Active User Filters')
--   end
--
--   local diags = vim.diagnostic.get(orig)
--   local seen = {}
--   local head1 = false
--   for _, d in ipairs(diags) do
--     local c = d.code or ''
--     if c ~= '' and c ~= 'drv_unknown_argument' and c ~= 'fatal_too_many_errors' then
--       if not state.codes[c] and not seen[c] then
--         if not head1 then
--           table.insert(lines, ' Outstanding Warnings (Select to Block):')
--           head1 = true
--         end
--         seen[c] = true
--         table.insert(lines, '  [ ] 🔒 Suppress Code: [' .. c .. ']')
--       end
--     end
--   end
--
--   local head2 = false
--   for k, _ in pairs(state.codes) do
--     if type(k) == 'string' and k ~= '' then
--       if not head2 then
--         table.insert(lines, '')
--         table.insert(lines, ' Suppressed Codes (Select to Restore):')
--         head2 = true
--       end
--       table.insert(lines, '  [*] 🔓 Remove Manual Filter: [' .. k .. ']')
--     end
--   end
--
--   local head3 = false
--   for f, _ in pairs(state.flags) do
--     if not head3 then
--       table.insert(lines, '')
--       table.insert(lines, ' ⚙️ Automated Flag Protections (Read-Only):')
--       head3 = true
--     end
--     table.insert(lines, '  [-] 📋 [RECORDED FLAG]: ' .. f)
--   end
--
--   vim.bo[state.uibuf].modifiable = true
--   vim.api.nvim_buf_set_lines(state.uibuf, 0, -1, false, lines)
--   vim.bo[state.uibuf].modifiable = false
--
--   -- Apply 0.11+ modern highlights smoothly
--   vim.api.nvim_buf_set_extmark(state.uibuf, ns, 0, 0, { end_line = 1, hl_group = 'Title' })
--   vim.api.nvim_buf_set_extmark(state.uibuf, ns, 1, 0, { end_line = 2, hl_group = 'Comment' })
--   for idx, txt in ipairs(lines) do
--     local line_pos = idx - 1
--     local opts = { end_line = idx }
--     if txt:find('^ Outstanding') then
--       opts.hl_group = 'DiagnosticWarn'
--       vim.api.nvim_buf_set_extmark(state.uibuf, ns, line_pos, 0, opts)
--     elseif txt:find('^ Suppressed') then
--       opts.hl_group = 'DiagnosticOk'
--       vim.api.nvim_buf_set_extmark(state.uibuf, ns, line_pos, 0, opts)
--     elseif txt:find('^ ⚙️') or txt:find('^  %[%-%]') then
--       opts.hl_group = 'Comment'
--       vim.api.nvim_buf_set_extmark(state.uibuf, ns, line_pos, 0, opts)
--     end
--   end
-- end
--
-- local function handle_select()
--   local line = vim.api.nvim_get_current_line() or ''
--   local orig = state.original_bufnr or 0
--   if orig == 0 then
--     return
--   end
--
--   if line:find('💥 Clear All Active User Filters') then
--     state.codes = {}
--     save_db(orig)
--   elseif line:find('🔒 Suppress Code:') then
--     local id = line:match('🔒 Suppress Code:%s*%[([%w%-_]+)%]')
--     if id then
--       state.codes[id] = true
--       save_db(orig)
--     end
--   elseif line:find('🔓 Remove Manual Filter:') then
--     local id = line:match('🔓 Remove Manual Filter:%s*%[([%w%-_]+)%]')
--     if id then
--       state.codes[id] = nil
--       save_db(orig)
--     end
--   else
--     return
--   end
--
--   M.on_updated = function()
--     vim.schedule(function()
--       draw_menu()
--     end)
--   end
--
--   vim.api.nvim_buf_call(orig, function()
--     local old = vim.o.shortmess
--     vim.o.shortmess = old .. 'F'
--     vim.cmd('silent! checktime')
--     vim.cmd('silent! edit!')
--     vim.o.shortmess = old
--   end)
-- end
--
-- function M.manage_file_diagnostics_interactive()
--   state.original_bufnr = vim.api.nvim_get_current_buf()
--   local orig = state.original_bufnr or 0
--   if orig == 0 then
--     return
--   end
--
--   close_win()
--
--   local width = 70
--   local height = 18
--   local row = math.ceil((vim.o.lines - height) / 2) - 1
--   local col = math.ceil((vim.o.columns - width) / 2) - 1
--
--   state.uibuf = vim.api.nvim_create_buf(false, true)
--   state.uiwin = vim.api.nvim_open_win(state.uibuf, true, {
--     relative = 'editor',
--     width = width,
--     height = height,
--     row = row,
--     col = col,
--     style = 'minimal',
--     border = 'rounded',
--     title = ' PlatformIO Exception Manager ',
--     title_pos = 'center',
--   })
--
--   if state.uibuf ~= 0 then
--     vim.bo[state.uibuf].bufhidden = 'wipe'
--     vim.bo[state.uibuf].filetype = 'nvimpiomangler'
--   end
--
--   local lock = vim.api.nvim_create_augroup('PioLock', { clear = true })
--   vim.api.nvim_create_autocmd('WinLeave', {
--     group = lock,
--     callback = function()
--       vim.schedule(function()
--         if state.uiwin and vim.api.nvim_win_is_valid(state.uiwin) then
--           vim.api.nvim_set_current_win(state.uiwin)
--         end
--       end)
--     end,
--   })
--
--   vim.api.nvim_create_autocmd('BufWipeout', {
--     group = lock,
--     buffer = state.uibuf,
--     callback = function()
--       M.on_updated = nil
--       pcall(vim.api.nvim_del_augroup_by_name, 'PioLock')
--       state.uiwin = nil
--       state.uibuf = nil
--     end,
--   })
--
--   local opts = { silent = true, buffer = state.uibuf }
--   vim.keymap.set('n', '<CR>', function()
--     handle_select()
--   end, opts)
--   vim.keymap.set('n', 'q', function()
--     close_win()
--   end, opts)
--   vim.keymap.set('n', '<Esc>', function()
--     close_win()
--   end, opts)
--
--   draw_menu()
-- end
--
-- -- stylua: ignore end
-- return M
