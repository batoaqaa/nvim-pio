--- stylua: ignore start
local M = {}

local state = {
  codes = {},
  flags = {},
  uibuf = nil,
  uiwin = nil,
  origbuf = nil,
}
M.on_updated = nil

local markers = { 'platformio.ini', '.git' }
local ns = vim.api.nvim_create_namespace('Pio')
local menu_mappings = {} -- 🌟 FIXED: Data registry map

-- 1. Path resolver helper
local function get_db_path(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local f = vim.api.nvim_buf_get_name(bufnr)
  local root = (f ~= '') and vim.fs.root(f, markers) or vim.uv.cwd()
  return root .. '/.filter.json'
end

-- 2. Database loading engine
local function load_db(bufnr)
  state.codes = {}
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
          state.codes[s] = true
        end
      end
    end
  end
end

-- 3. Database saving engine
local function save_db(bufnr)
  local path = get_db_path(bufnr)
  local f = io.open(path, 'wb')
  if f then
    if next(state.codes) == nil then
      f:write('{"codes":null}')
    else
      local payload = { codes = state.codes }
      local pretty = require('nvimpio.utils.misc').jsonFormat(payload)
      f:write(pretty)
    end
    f:close()
  end
end

load_db(0)

-- =====================================================
-- 4. THE ROBUST DYNAMIC HANDLER INTERCEPTOR (RAM-ONLY)
-- =====================================================
function M.diagnostic_handler(err, result, ctx, config)
  if err or not result or not result.diagnostics then
    return vim.lsp.handlers['textDocument/publishDiagnostics'](err, result, ctx, config)
  end

  local current_buf = vim.uri_to_bufnr(result.uri)
  load_db(current_buf)

  local clean_diagnostics = {}

  for _, diag in ipairs(result.diagnostics) do
    local code = diag.code
    local msg = diag.message or ''

    if code and type(code) == 'string' and code ~= '' then
      local is_drv = code == 'drv_unknown_argument' or code == 'drv_unknown_argument_with_suggestion' or code == 'fatal_too_many_errors'
      if is_drv then
        local f = msg:match('(%-[%w%-]+)')
        if f then
          state.flags[f] = true
        end
      end
    end
  end

  for _, diag in ipairs(result.diagnostics) do
    local keep = true
    local code = diag.code
    local msg = diag.message or ''

    local is_drv = code == 'drv_unknown_argument' or code == 'drv_unknown_argument_with_suggestion' or code == 'fatal_too_many_errors'

    if is_drv then
      keep = false
    elseif code and state.codes[code] then
      keep = false
    end

    if keep then
      for flag, _ in pairs(state.flags) do
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

  if type(M.on_updated) == 'function' then
    M.on_updated()
  end
end

-- =====================================================
-- 5. PERSISTENT FLOATING CANVAS CONTROL PANEL ENGINE
-- =====================================================
local function close_win()
  M.on_updated = nil
  pcall(vim.api.nvim_del_augroup_by_name, 'PioLock')
  if state.uiwin and vim.api.nvim_win_is_valid(state.uiwin) then
    vim.api.nvim_win_close(state.uiwin, true)
  end
  state.uiwin = nil
  state.uibuf = nil
end

local function draw_menu()
  local orig = state.original_bufnr or 0
  if not state.uibuf or not vim.api.nvim_buf_is_valid(state.uibuf) or orig == 0 then
    return
  end
  load_db(orig)

  local border_ln = string.rep('─', 65)
  local lines = {
    ' 💥 PlatformIO Exception Dashboard ([q] / [Esc] to Exit) ',
    border_ln,
    '',
  }
  vim.api.nvim_buf_clear_namespace(state.uibuf, ns, 0, -1)

  -- Reset our context map registry on each redraw pass
  menu_mappings = {}

  if next(state.codes) then
    table.insert(lines, '  [x] 💥 Clear All Active User Filters')
    menu_mappings[#lines] = { action = 'reset' }
  end

  local diags = vim.diagnostic.get(orig)
  local seen = {}
  local head1 = false
  for _, d in ipairs(diags) do
    local c = d.code or ''
    if c ~= '' and c ~= 'drv_unknown_argument' and c ~= 'fatal_too_many_errors' then
      if not seen[c] then
        if not head1 then
          table.insert(lines, ' Outstanding Warnings (Select to Block):')
          head1 = true
        end
        seen[c] = true

        local is_blocked = state.codes[c]
        local mark = is_blocked and '[*]' or '[ ]'
        local status = is_blocked and '🔓 Restore' or '🔒 Suppress'
        table.insert(lines, string.format('  %s %s Code: [%s]', mark, status, c))

        -- 🌟 MAP TARGET ACTION STRUCT DIRECTLY TO LINE ROW NUMBER
        menu_mappings[#lines] = {
          action = is_blocked and 'unblock' or 'block',
          id = c,
        }
      end
    end
  end

  local head3 = false
  for f, _ in pairs(state.flags) do
    if not head3 then
      table.insert(lines, '')
      table.insert(lines, ' ⚙️ Automated Flag Protections (Read-Only):')
      head3 = true
    end
    table.insert(lines, '  [-] 📋 [RECORDED FLAG]: ' .. f)
  end

  local target_uibuf = state.uibuf or 0
  if target_uibuf ~= 0 then
    vim.bo[target_uibuf].modifiable = true
    vim.api.nvim_buf_set_lines(target_uibuf, 0, -1, false, lines)
    vim.bo[target_uibuf].modifiable = false

    -- Apply highlights cleanly
    vim.api.nvim_buf_set_extmark(target_uibuf, ns, 0, 0, { end_line = 1, hl_group = 'Title' })
    vim.api.nvim_buf_set_extmark(target_uibuf, ns, 1, 0, { end_line = 2, hl_group = 'Comment' })
    for idx, txt in ipairs(lines) do
      local line_pos = idx - 1
      local opts = { end_line = idx }
      if txt:find('^ Outstanding') then
        opts.hl_group = 'DiagnosticWarn'
        vim.api.nvim_buf_set_extmark(target_uibuf, ns, line_pos, 0, opts)
      elseif txt:find('%*') then
        opts.hl_group = 'DiagnosticOk'
        vim.api.nvim_buf_set_extmark(target_uibuf, ns, line_pos, 0, opts)
      elseif txt:find('^ ⚙️') or txt:find('^  %[%-%]') then
        opts.hl_group = 'Comment'
        vim.api.nvim_buf_set_extmark(target_uibuf, ns, line_pos, 0, opts)
      end
    end
  end
end

local function handle_select()
  local orig = state.original_bufnr or 0

  -- We extract and explicitly verify that the persistent window tracker exists.
  -- This guarantees a valid handle is passed into nvim_win_get_cursor natively!
  local win_handle = state.uiwin or 0
  if orig == 0 or win_handle == 0 or not vim.api.nvim_win_is_valid(win_handle) then
    return
  end

  -- Programmatically extract the current row line number matching your cursor
  local cursor = vim.api.nvim_win_get_cursor(win_handle)
  local row_idx = cursor[1]
  local target = menu_mappings[row_idx]

  if not target then
    return
  end

  if target.action == 'reset' then
    state.codes = {}
    save_db(orig)
  elseif target.action == 'block' then
    state.codes[target.id] = true
    save_db(orig)
  elseif target.action == 'unblock' then
    state.codes[target.id] = nil
    save_db(orig)
  end

  -- Stream trigger callback hook
  M.on_updated = function()
    vim.schedule(function()
      draw_menu()
    end)
  end

  -- Force high-speed visibility repaint natively inside RAM
  if vim.api.nvim_buf_is_valid(orig) then
    for _, client in pairs(vim.lsp.get_clients({ bufnr = orig })) do
      if client.name == 'clangd' then
        local l_ns = vim.lsp.diagnostic.get_namespace(client.id)
        vim.diagnostic.show(l_ns, orig, nil, {
          filter = function(d)
            return not (d.code and state.codes[d.code])
          end,
        })
      end
    end
  end

  -- Redraw list elements instantly on the exact same frame!
  draw_menu()
end

function M.manage_file_diagnostics_interactive()
  state.original_bufnr = vim.api.nvim_get_current_buf()
  local orig = state.original_bufnr or 0
  if orig == 0 then
    return
  end

  close_win()

  local w = 70
  local h = 18
  local row = math.ceil((vim.o.lines - h) / 2) - 1
  local col = math.ceil((vim.o.columns - w) / 2) - 1

  state.uibuf = vim.api.nvim_create_buf(false, true)
  state.uiwin = vim.api.nvim_open_win(state.uibuf, true, {
    relative = 'editor',
    width = w,
    height = h,
    row = row,
    col = col,
    style = 'minimal',
    border = 'rounded',
    title = ' PlatformIO Exception Manager ',
    title_pos = 'center',
  })

  local target_uibuf = state.uibuf or 0
  if target_uibuf ~= 0 then
    vim.bo[target_uibuf].bufhidden = 'wipe'
    vim.bo[target_uibuf].filetype = 'nvimpiomangler'
  end

  local lock = vim.api.nvim_create_augroup('PioLock', { clear = true })
  vim.api.nvim_create_autocmd('WinLeave', {
    group = lock,
    callback = function()
      vim.schedule(function()
        if state.uiwin and vim.api.nvim_win_is_valid(state.uiwin) then
          vim.api.nvim_set_current_win(state.uiwin)
        end
      end)
    end,
  })

  vim.api.nvim_create_autocmd('BufWipeout', {
    group = lock,
    buffer = target_uibuf,
    callback = function()
      M.on_updated = nil
      pcall(vim.api.nvim_del_augroup_by_name, 'PioLock')
      state.uiwin = nil
      state.uibuf = nil
    end,
  })

  local opts = { silent = true, buffer = target_uibuf }
  vim.keymap.set('n', '<CR>', function()
    handle_select()
  end, opts)
  vim.keymap.set('n', 'q', function()
    close_win()
  end, opts)
  vim.keymap.set('n', '<Esc>', function()
    close_win()
  end, opts)

  draw_menu()
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
