--- stylua: ignore start
local M = {}

M.manual_blocked_codes = {}
M.removed_flags = {}
-- 🌟 Session registry tracks codes across flips
M.session_discovered_codes = {}

local markers = { 'platformio.ini', '.git' }

-- 1. Get filter file path safely
local function get_db_path(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local f = vim.api.nvim_buf_get_name(bufnr)
  local r = (f ~= '') and vim.fs.root(f, markers) or vim.uv.cwd()
  return r .. '/.filter.json'
end

-- 2. Load persistent json arrays
local function load_db(bufnr)
  M.manual_blocked_codes = {}
  local f = io.open(get_db_path(bufnr), 'rb')
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
          -- Seed persistent blocks to the register
          M.session_discovered_codes[s] = true
        end
      end
    end
  end
end

-- 3. Save selections straight down to disk
local function save_db(bufnr)
  local f = io.open(get_db_path(bufnr), 'wb')
  if f then
    local payload = { codes = M.manual_blocked_codes, flags = M.removed_flags }
    local pretty = require('nvimpio.utils.misc').jsonFormat(payload)
    f:write(pretty)
    f:close()
  end
end

load_db(0)

-- ===================================================================
-- 🆕 ISOLATED PIPELINE FILTER (SAFE FOR INLINE MEMORY WRAPPERS)
-- ===================================================================
function M.clean_diagnostics_pipeline(diagnostics, bufnr)
  if not diagnostics then
    return {}
  end

  load_db(bufnr)

  local boiler = require('nvimpio.boilerplate')
  boiler.remove = {}

  local clean_diagnostics = {}
  for _, diag in ipairs(diagnostics) do
    local keep = true
    local code = diag.code
    local msg = diag.message or ''

    local is_drv = false
    if type(code) == 'string' then
      local lower_code = code:lower()
      local lower_msg = msg:lower()

      -- Rule A: Matches standard language server driver prefixes (e.g., drv_unknown_argument, fatal_too_many_errors)
      local has_driver_prefix = lower_code:match('^drv_') or lower_code:match('^fatal_')

      -- Rule B: Matches fallback messages dealing explicitly with terminal command options
      local has_flag_keywords = lower_msg:match('argument') or lower_msg:match('unknown flag') or lower_msg:match('command line option')

      if has_driver_prefix or has_flag_keywords then
        is_drv = true
      end
    end

    if is_drv then
      keep = false
      -- Safely extract the raw compiler flag from the message (e.g., "-mlongcalls")
      local f = msg:match('(%-[%w%-%.%*]+)')
      if f then
        table.insert(boiler.remove, f)
        M.removed_flags[f] = true
      end
    elseif code and M.manual_blocked_codes[code] then
      keep = false
    end

    if code and type(code) == 'string' and code ~= '' and not is_drv then
      -- Register every true code discovered to the tracker
      M.session_discovered_codes[code] = true
    end

    if keep then
      table.insert(clean_diagnostics, diag)
    end
  end
  -- for _, diag in ipairs(diagnostics) do
  --   local keep = true
  --   local code = diag.code
  --   local msg = diag.message or ''
  --
  --   local is_drv = code == 'drv_unknown_argument' or code == 'drv_unknown_argument_with_suggestion' or code == 'fatal_too_many_errors'
  --
  --   if is_drv then
  --     keep = false
  --     local f = msg:match('(%-[%w%-]+)')
  --     if f then
  --       table.insert(boiler.remove, f)
  --       M.removed_flags[f] = true
  --     end
  --   elseif code and M.manual_blocked_codes[code] then
  --     keep = false
  --   end
  --
  --   if code and type(code) == 'string' and code ~= '' and not is_drv then
  --     -- Register every code discovered to the tracker
  --     M.session_discovered_codes[code] = true
  --   end
  --
  --   if keep then
  --     table.insert(clean_diagnostics, diag)
  --   end
  -- end

  print(vim.inspect(boiler.remove))
  local boilerplate_gen = boiler.boilerplate_gen
  if boilerplate_gen then
    pcall(boilerplate_gen, '.clangd', vim.uv.cwd())
  end

  return clean_diagnostics
end

-- =====================================================
-- 4. DYNAMIC STREAM INTERCEPTOR (VOLATILE RAM-ONLY)
-- =====================================================
function M.diagnostic_handler(err, result, ctx, config)
  if err or not result or not result.diagnostics then
    return vim.lsp.handlers['textDocument/publishDiagnostics'](err, result, ctx, config)
  end

  local bufnr = vim.uri_to_bufnr(result.uri)

  -- Feed raw data array straight through our isolated filter pipeline
  result.diagnostics = M.clean_diagnostics_pipeline(result.diagnostics, bufnr)

  vim.lsp.handlers['textDocument/publishDiagnostics'](err, result, ctx, config)
end

-- =====================================================
-- 5. THE UNBREAKABLE VOLATILE MULTI-SELECT PICKER
-- =====================================================
function M.manage_file_diagnostics_interactive()
  local bufnr = vim.api.nvim_get_current_buf()

  -- FIX 1: Force sync the RAM arrays with disk state before drawing
  load_db(bufnr)

  local items = {}

  if next(M.manual_blocked_codes) then
    table.insert(items, { action = 'reset', text = '💥 Reset All Filters' })
  end

  -- Hydrate active codes into session register
  local raw_diagnostics = vim.diagnostic.get(bufnr)
  for _, d in ipairs(raw_diagnostics) do
    local c = d.code or ''
    local msg = d.message or ''

    -- GENERIC RULE 1: Skip if the code name matches a known dynamic compiler-argument layout
    local is_automated_arg = c:match('^drv_') or c:match('^fatal_')

    -- GENERIC RULE 2: Skip if the diagnostic message relates straight to command-line flag errors
    local is_flag_err = msg:match('command line argument') or msg:match('unknown argument')

    if c ~= '' and not is_automated_arg and not is_flag_err then
      M.session_discovered_codes[c] = true
    end
  end
  -- local raw_diagnostics = vim.diagnostic.get(bufnr)
  -- for _, d in ipairs(raw_diagnostics) do
  --   local c = d.code or ''
  --   if c ~= '' and c ~= 'drv_unknown_argument' and c ~= 'fatal_too_many_errors' then
  --     M.session_discovered_codes[c] = true
  --   end
  -- end

  -- Sort registered keys alphabetically
  local registered_keys = {}
  for k, _ in pairs(M.session_discovered_codes) do
    table.insert(registered_keys, k)
  end
  table.sort(registered_keys)

  -- Loop over the session registry to keep menu layout stable on refresh toggles
  for _, c in ipairs(registered_keys) do
    local is_blocked = M.manual_blocked_codes[c]
    local mark = is_blocked and '[*]' or '[ ]'
    local status = is_blocked and 'Restore' or 'Suppress'
    table.insert(items, {
      action = is_blocked and 'unblock' or 'block',
      id = c,
      text = string.format('  %s %s Code: [%s]', mark, status, c),
    })
  end

  -- Print read-only automated flag logs at the bottom
  for f, _ in pairs(M.removed_flags) do
    table.insert(items, { action = 'none', text = '  [-] ⚙️ [AUTOMATED]: ' .. f })
  end

  if #items == 0 then
    vim.notify('✅ Clean Slate: No active lints.', vim.log.levels.INFO)
    return
  end

  -- Render via native modern Neovim picker loop
  vim.ui.select(items, {
    prompt = 'Filter Panel (Toggle items, press Esc to Save & Apply)',
    format_item = function(item)
      return item.text
    end,
  }, function(choice)
    if not choice then
      -- User pressed Esc: Save everything cleanly to disk
      save_db(bufnr)
      vim.schedule(function()
        if vim.api.nvim_buf_is_valid(bufnr) then
          vim.api.nvim_buf_call(bufnr, function()
            local old = vim.o.shortmess
            vim.o.shortmess = old .. 'F'
            vim.cmd('silent! checktime')
            vim.cmd('silent! edit!')
            vim.o.shortmess = old
          end)
        end
      end)
      return
    end

    if choice.action == 'none' then
      M.manage_file_diagnostics_interactive()
      return
    end

    -- Toggle memory state instantly in RAM
    if choice.action == 'reset' then
      M.manual_blocked_codes = {}
    elseif choice.action == 'block' then
      M.manual_blocked_codes[choice.id] = true
    elseif choice.action == 'unblock' then
      M.manual_blocked_codes[choice.id] = nil
    end

    -- FIX 2: Write temporary updates to disk state right away so
    -- subsequent recursive menu loops pull a unified array profile
    save_db(bufnr)

    -- Recurse instantly. Stays open continuously inside RAM!
    M.manage_file_diagnostics_interactive()
  end)
end
-- =====================================================
-- 5. THE UNBREAKABLE VOLATILE MULTI-SELECT PICKER
-- =====================================================
-- function M.manage_file_diagnostics_interactive()
--   local bufnr = vim.api.nvim_get_current_buf()
--   local items = {}
--
--   if next(M.manual_blocked_codes) then
--     table.insert(items, { action = 'reset', text = '💥 Reset All Filters' })
--   end
--
--   -- Hydrate active codes into session register
--   local raw_diagnostics = vim.diagnostic.get(bufnr)
--   for _, d in ipairs(raw_diagnostics) do
--     local c = d.code or ''
--     if c ~= '' and c ~= 'drv_unknown_argument' and c ~= 'fatal_too_many_errors' then
--       M.session_discovered_codes[c] = true
--     end
--   end
--
--   -- Sort registered keys alphabetically
--   local registered_keys = {}
--   for k, _ in pairs(M.session_discovered_codes) do
--     table.insert(registered_keys, k)
--   end
--   table.sort(registered_keys)
--
--   -- Loop over the session registry to keep menu layout stable on refresh toggles
--   for _, c in ipairs(registered_keys) do
--     local is_blocked = M.manual_blocked_codes[c]
--     local mark = is_blocked and '[*]' or '[ ]'
--     local status = is_blocked and 'Restore' or 'Suppress'
--     table.insert(items, {
--       action = is_blocked and 'unblock' or 'block',
--       id = c,
--       text = string.format('  %s %s Code: [%s]', mark, status, c),
--     })
--   end
--
--   -- Print read-only automated flag logs at the bottom
--   for f, _ in pairs(M.removed_flags) do
--     table.insert(items, { action = 'none', text = '  [-] ⚙️ [AUTOMATED]: ' .. f })
--   end
--
--   if #items == 0 then
--     vim.notify('✅ Clean Slate: No active lints.', vim.log.levels.INFO)
--     return
--   end
--
--   -- Render via native modern Neovim picker loop
--   vim.ui.select(items, {
--     prompt = 'Filter Panel (Toggle items, press Esc to Save & Apply)',
--     format_item = function(item)
--       return item.text
--     end,
--   }, function(choice)
--     if not choice then
--       save_db(bufnr)
--       vim.schedule(function()
--         if vim.api.nvim_buf_is_valid(bufnr) then
--           vim.api.nvim_buf_call(bufnr, function()
--             local old = vim.o.shortmess
--             vim.o.shortmess = old .. 'F'
--             vim.cmd('silent! checktime')
--             vim.cmd('silent! edit!')
--             vim.o.shortmess = old
--           end)
--         end
--       end)
--       return
--     end
--
--     if choice.action == 'none' then
--       M.manage_file_diagnostics_interactive()
--       return
--     end
--
--     -- Toggle memory state instantly in RAM
--     if choice.action == 'reset' then
--       M.manual_blocked_codes = {}
--     elseif choice.action == 'block' then
--       M.manual_blocked_codes[choice.id] = true
--     elseif choice.action == 'unblock' then
--       M.manual_blocked_codes[choice.id] = nil
--     end
--
--     -- Recurse instantly. Stays open continuously inside RAM!
--     M.manage_file_diagnostics_interactive()
--   end)
-- end

-- stylua: ignore end
return M

-- --- stylua: ignore start
-- local M = {}
--
-- M.manual_blocked_codes = {}
-- M.removed_flags = {}
-- -- 🌟 Session registry tracks codes across flips
-- M.session_discovered_codes = {}
--
-- local markers = { 'platformio.ini', '.git' }
--
-- -- 1. Get filter file path safely
-- local function get_db_path(bufnr)
--   bufnr = bufnr or vim.api.nvim_get_current_buf()
--   local f = vim.api.nvim_buf_get_name(bufnr)
--   local r = (f ~= '') and vim.fs.root(f, markers) or vim.uv.cwd()
--   return r .. '/.filter.json'
-- end
--
-- -- 2. Load persistent json arrays
-- local function load_db(bufnr)
--   M.manual_blocked_codes = {}
--   local f = io.open(get_db_path(bufnr), 'rb')
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
--           M.manual_blocked_codes[s] = true
--           -- Seed persistent blocks to the register
--           M.session_discovered_codes[s] = true
--         end
--       end
--     end
--   end
-- end
--
-- -- 3. Save selections straight down to disk
-- local function save_db(bufnr)
--   local f = io.open(get_db_path(bufnr), 'wb')
--   if f then
--     -- local payload = { codes = M.manual_blocked_codes }
--     local payload = { codes = M.manual_blocked_codes, flags = M.removed_flags }
--     -- f:write(vim.json.encode(payload))
--     -- f:close()
--
--     local pretty = require('nvimpio.utils.misc').jsonFormat(payload)
--     f:write(pretty)
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
--   local bufnr = vim.uri_to_bufnr(result.uri)
--   load_db(bufnr)
--
--   local boiler = require('nvimpio.boilerplate')
--   boiler.remove = {}
--
--   local clean_diagnostics = {}
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
--         table.insert(boiler.remove, f)
--         M.removed_flags[f] = true
--       end
--     elseif code and M.manual_blocked_codes[code] then
--       keep = false
--     end
--
--     if code and type(code) == 'string' and code ~= '' and not is_drv then
--       -- Register every code discovered to the tracker
--       M.session_discovered_codes[code] = true
--     end
--
--     if keep then
--       table.insert(clean_diagnostics, diag)
--     end
--   end
--
--   local boilerplate_gen = boiler.boilerplate_gen
--   if boilerplate_gen then
--     pcall(boilerplate_gen, '.clangd', vim.uv.cwd())
--   end
--
--   result.diagnostics = clean_diagnostics
--   vim.lsp.handlers['textDocument/publishDiagnostics'](err, result, ctx, config)
-- end
--
-- -- =====================================================
-- -- 5. THE UNBREAKABLE VOLATILE MULTI-SELECT PICKER
-- -- =====================================================
-- function M.manage_file_diagnostics_interactive()
--   local bufnr = vim.api.nvim_get_current_buf()
--   local items = {}
--
--   if next(M.manual_blocked_codes) then
--     table.insert(items, { action = 'reset', text = '💥 Reset All Filters' })
--   end
--
--   -- Hydrate active codes into session register
--   local raw_diagnostics = vim.diagnostic.get(bufnr)
--   for _, d in ipairs(raw_diagnostics) do
--     local c = d.code or ''
--     if c ~= '' and c ~= 'drv_unknown_argument' and c ~= 'fatal_too_many_errors' then
--       M.session_discovered_codes[c] = true
--     end
--   end
--
--   -- Sort registered keys alphabetically
--   local registered_keys = {}
--   for k, _ in pairs(M.session_discovered_codes) do
--     table.insert(registered_keys, k)
--   end
--   table.sort(registered_keys)
--
--   -- 🌟 THE ARCHITECTURE FIX (PERMANENT RENDER STABILITY):
--   -- Loop over the session registry. The menu line is fixed on screen!
--   -- We read the true data map state, switching the indicators cleanly.
--   -- This makes lines structurally incapable of vanishing from your picker!
--   for _, c in ipairs(registered_keys) do
--     local is_blocked = M.manual_blocked_codes[c]
--     local mark = is_blocked and '[*]' or '[ ]'
--     local status = is_blocked and 'Restore' or 'Suppress'
--     table.insert(items, {
--       action = is_blocked and 'unblock' or 'block',
--       id = c,
--       text = string.format('  %s %s Code: [%s]', mark, status, c),
--     })
--   end
--
--   -- Print read-only automated flag logs at the bottom
--   for f, _ in pairs(M.removed_flags) do
--     table.insert(items, { action = 'none', text = '  [-] ⚙️ [AUTOMATED]: ' .. f })
--   end
--
--   if #items == 0 then
--     vim.notify('✅ Clean Slate: No active lints.', vim.log.levels.INFO)
--     return
--   end
--
--   -- Render via native modern Neovim picker loop
--   vim.ui.select(items, {
--     prompt = 'Filter Panel (Toggle items, press Esc to Save & Apply)',
--     format_item = function(item)
--       return item.text
--     end,
--   }, function(choice)
--     if not choice then
--       save_db(bufnr)
--       vim.schedule(function()
--         if vim.api.nvim_buf_is_valid(bufnr) then
--           vim.api.nvim_buf_call(bufnr, function()
--             local old = vim.o.shortmess
--             vim.o.shortmess = old .. 'F'
--             vim.cmd('silent! checktime')
--             vim.cmd('silent! edit!')
--             vim.o.shortmess = old
--           end)
--         end
--       end)
--       return
--     end
--
--     if choice.action == 'none' then
--       M.manage_file_diagnostics_interactive()
--       return
--     end
--
--     -- Toggle memory state instantly in RAM
--     if choice.action == 'reset' then
--       M.manual_blocked_codes = {}
--     elseif choice.action == 'block' then
--       M.manual_blocked_codes[choice.id] = true
--     elseif choice.action == 'unblock' then
--       M.manual_blocked_codes[choice.id] = nil
--     end
--
--     -- Recurse instantly. Stays open continuously inside RAM!
--     M.manage_file_diagnostics_interactive()
--   end)
-- end
--
-- -- stylua: ignore end
-- return M
