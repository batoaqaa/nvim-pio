--- stylua: ignore start
local M = {}

-- Module scopes track cross-file automated session states safely
M.removed_flags = {}
M.session_discovered_codes = {}

local markers = { 'platformio.ini', '.git' }

-- 1. Get filter database path safely using absolute project roots
local function get_db_path(source)
  local f = ''
  if type(source) == 'string' then
    f = source
  elseif type(source) == 'number' or source == nil then
    local bufnr = source or vim.api.nvim_get_current_buf()
    f = vim.api.nvim_buf_get_name(bufnr)
  end

  -- Search upwards for your local project markers ('platformio.ini' or '.git')
  local root_dir = (f ~= '') and vim.fs.root(f, markers) or nil

  -- 🟢 THE BULLETPROOF WORKSPACE ANCHOR WITH ABSOLUTE TYPE SAFETY:
  if not root_dir or root_dir:match('%.platformio') then
    local cwd_path = vim.uv.cwd()
    -- Explicitly verify that cwd_path is a valid, non-empty string type before using it
    if type(cwd_path) == 'string' and cwd_path ~= '' then
      root_dir = vim.fs.root(cwd_path, markers) or cwd_path
    else
      root_dir = '.'
    end
  end

  return vim.fs.joinpath(root_dir, '.filter.json')
end

-- 2. Pure local JSON reading loop (Strictly separates codes from compiler flags)
local function parse_db_file_pure(db_path)
  local blocked_codes = {}
  local f = io.open(db_path, 'rb')
  if not f then
    return blocked_codes
  end
  local raw = f:read('*all')
  f:close()

  if raw and raw ~= '' then
    local ok, data = pcall(vim.json.decode, raw)
    if ok and data and type(data.codes) == 'table' then
      for k, v in pairs(data.codes) do
        local code_str = nil
        if type(k) == 'string' and k ~= '' then
          code_str = k
        elseif type(v) == 'string' and v ~= '' then
          code_str = v
        end

        -- Ensure we only load it if it was explicitly marked as true inside the codes sub-section
        if code_str and data.codes[k] == true then
          blocked_codes[code_str] = true
        end
      end
    end
  end
  return blocked_codes
end

-- ===================================================================
-- 🛠️ ENGINE PATH A: Clean Project-Wide Toolchain Flags (The Extractor)
-- ===================================================================
function M.clean_project_wide_flags(project_root, diagnostics)
  if not diagnostics or #diagnostics == 0 then
    return
  end
  local boiler = require('nvimpio.boilerplate')
  boiler.remove = boiler.remove or {}
  local flags_updated = false

  for _, diag in ipairs(diagnostics) do
    local code = diag.code
    local msg = diag.message or ''
    local is_drv = type(code) == 'string' and (code:match('^drv_') or code:match('^fatal_') or msg:lower():match('argument'))

    if is_drv then
      local flag = msg:match('(%-[fmWOdsx][%w%-%.%*]+)')
      if flag and not M.removed_flags[flag] then
        table.insert(boiler.remove, flag)
        M.removed_flags[flag] = true
        flags_updated = true
      end
    end
  end

  if flags_updated then
    local filter_db_path = get_db_path(project_root)
    -- Load what is explicitly written to file right now, ignoring dirty RAM states
    local current_blocked = parse_db_file_pure(filter_db_path)

    local f = io.open(filter_db_path, 'wb')
    if f then
      local payload = { codes = current_blocked, flags = M.removed_flags }
      f:write(require('nvimpio.utils.misc').jsonFormat(payload))
      f:close()
    end
    if boiler.boilerplate_gen then
      pcall(boiler.boilerplate_gen, '.clangd', project_root)
    end
  end
end

-- ===================================================================
-- 🛠️ ENGINE PATH B: Clean Source Code File Diagnostics (Pure Files)
-- ===================================================================
function M.clean_file_path_pipeline(absolute_file_path, diagnostics)
  if not diagnostics or #diagnostics == 0 then
    return diagnostics
  end
  local filter_db_path = get_db_path(absolute_file_path)
  local project_root = vim.fs.dirname(filter_db_path)

  -- Pure localized read ensures we only check blocks configured for THIS project folder
  local manual_blocked = parse_db_file_pure(filter_db_path)

  local clean_diagnostics = {}
  for _, diag in ipairs(diagnostics) do
    local keep = true
    local code = diag.code
    local msg = diag.message or ''
    local is_drv = type(code) == 'string' and (code:match('^drv_') or code:match('^fatal_') or msg:lower():match('argument'))

    if is_drv then
      keep = false
      -- [fmWOdsx] represents the universal language categories used by the entire GCC and Clang compiler family globally
      -- f: Compiler Features / Optimizations (e.g., -fexceptions, -fno-rtti)
      -- m: Machine / Architecture Directives (e.g., -mlongcalls, -mthumb)
      -- W: Warning parameters (e.g., -Wno-deprecated, -Wsign-compare)
      -- O: Optimization Levels (e.g., -Os, -O2)
      -- d / s / x: Internal Debugging, Standards, and Language flags (e.g., -ggdb, -std=c++17, -xc++)
      -- Starts strictly with a hyphen followed by a valid single-letter flag category indicator (f, m, W, O, d, s, x)
      -- Generic character class limits flags to true compiler options (-m, -f, -W, etc.), dropping English text words
      local flag = msg:match('(%-[fmWOdsx][%w%-%.%*]+)')
      if flag and not M.removed_flags[flag] then
        local boiler = require('nvimpio.boilerplate')
        boiler.remove = boiler.remove or {}
        table.insert(boiler.remove, flag)
        M.removed_flags[flag] = true

        local f = io.open(filter_db_path, 'wb')
        if f then
          local payload = { codes = manual_blocked, flags = M.removed_flags }
          f:write(require('nvimpio.utils.misc').jsonFormat(payload))
          f:close()
        end
        if boiler.boilerplate_gen then
          pcall(boiler.boilerplate_gen, '.clangd', project_root)
        end
      end
    elseif code and manual_blocked[code] then
      keep = false
    end

    if keep then
      table.insert(clean_diagnostics, diag)
    end
  end
  return clean_diagnostics
end

-- ===================================================================
-- 💻 THE INTERACTIVE DYNAMIC CHECKBOX PICKER PANEL (STATE MACHINE)
-- ===================================================================
function M.manage_file_diagnostics_interactive(state_override)
  local bufnr = vim.api.nvim_get_current_buf()
  local filter_db_path = get_db_path(bufnr)

  -- Initialize memory state tracking layer from disk or incoming RAM state
  local active_file_blocked = state_override or parse_db_file_pure(filter_db_path)

  M.session_discovered_codes = M.session_discovered_codes or {}

  -- Seed tracking lists with keys currently active in memory
  for code_key, is_true in pairs(active_file_blocked) do
    if is_true then
      M.session_discovered_codes[code_key] = true
    end
  end

  -- Seed tracking lists with active on-screen errors
  local raw_diagnostics = vim.diagnostic.get(bufnr)
  for _, d in ipairs(raw_diagnostics) do
    local c = d.code or ''
    local msg = d.message or ''
    local is_automated_arg = c:match('^drv_') or c:match('^fatal_')
    local is_flag_err = msg:lower():match('argument') or msg:lower():match('unknown flag')

    if c ~= '' and not is_automated_arg and not is_flag_err then
      M.session_discovered_codes[c] = true
    end
  end

  -- Sort keys alphabetically
  local registered_keys = {}
  for k, _ in pairs(M.session_discovered_codes) do
    table.insert(registered_keys, k)
  end
  table.sort(registered_keys)

  local items = {}
  if next(active_file_blocked) then
    table.insert(items, { action = 'reset', text = '💥 Reset All Filters' })
  end

  -- Build the checkbox items layout
  for _, c in ipairs(registered_keys) do
    local is_blocked = active_file_blocked[c] == true
    local mark = is_blocked and '[*]' or '[ ]'
    local status = is_blocked and 'Restore' or 'Suppress'

    table.insert(items, {
      action = is_blocked and 'unblock' or 'block',
      id = c,
      text = string.format('  %s %s Code: [%s]', mark, status, c),
    })
  end

  for f, _ in pairs(M.removed_flags) do
    table.insert(items, { action = 'none', text = '  [-] ⚙️ [AUTOMATED]: ' .. f })
  end

  if #items == 0 then
    vim.notify('✅ Clean Slate: No active lints.', vim.log.levels.INFO)
    return
  end

  local block_count = 0
  for _ in pairs(active_file_blocked) do
    block_count = block_count + 1
  end

  vim.ui.select(items, {
    prompt = string.format('📁 %s | Blocked: %d', vim.fs.basename(filter_db_path), block_count),
    format_item = function(item)
      return item.text
    end,
  }, function(choice)
    -- 🟢 GATE 1: User pressed Escape to close the panel menu
    if not choice then
      -- Open file descriptors and perform the single-point disk write operation
      local f = io.open(filter_db_path, 'wb')
      if f then
        local payload = { codes = active_file_blocked, flags = M.removed_flags }
        f:write(require('nvimpio.utils.misc').jsonFormat(payload))
        f:close()
      end

      -- Flush session cache arrays entirely out of RAM memory on exit
      M.session_discovered_codes = nil

      -- Refresh buffer lints viewport tracking maps
      vim.schedule(function()
        if vim.api.nvim_buf_is_valid(bufnr) then
          vim.api.nvim_buf_call(bufnr, function()
            local old = vim.o.shortmess
            vim.o.shortmess = old .. 'F'
            vim.cmd('silent! checktime | silent! edit!')
            vim.o.shortmess = old
          end)
        end
      end)

      return -- Halts execution completely. No loop recursion triggers!
    end

    -- 🟢 GATE 2: User clicked an automated read-only logger flag row item
    if choice.action == 'none' then
      -- Loop back into memory view state without changing pointer assignments
      M.manage_file_diagnostics_interactive(active_file_blocked)
      return
    end

    -- 🟢 GATE 3: User selected a valid row checkbox item to toggle
    if choice.action == 'reset' then
      active_file_blocked = {}
    elseif choice.action == 'block' then
      active_file_blocked[choice.id] = true
    elseif choice.action == 'unblock' then
      active_file_blocked[choice.id] = nil
    end

    -- 🟢 RECURSION LINE MOVED INSIDE THE ACTIVE SELECTION FLOW LAYER:
    -- This guarantees that changes toggle smoothly in RAM while typing/clicking around,
    -- and stops the loops from breaking or escaping when hitting Esc.
    M.manage_file_diagnostics_interactive(active_file_blocked)
  end)
end

-- function M.manage_file_diagnostics_interactive(state_override)
--   local bufnr = vim.api.nvim_get_current_buf()
--   local filter_db_path = get_db_path(bufnr)
--
--   -- Initialize memory state: Use the provided state override or fall back to a fresh disk read
--   local active_file_blocked = state_override or parse_db_file_pure(filter_db_path)
--
--   -- Rebuild the volatile workspace menu tracker fresh from empty allocations
--   local local_discovered_codes = {}
--
--   -- Seed the menu tracking list with keys currently tracked in memory
--   for code_key, is_true in pairs(active_file_blocked) do
--     if is_true then
--       local_discovered_codes[code_key] = true
--     end
--   end
--
--   -- Seed the menu tracking list with active on-screen compiler errors
--   local raw_diagnostics = vim.diagnostic.get(bufnr)
--   for _, d in ipairs(raw_diagnostics) do
--     local c = d.code or ''
--     local msg = d.message or ''
--     local is_automated_arg = c:match('^drv_') or c:match('^fatal_')
--     local is_flag_err = msg:lower():match('argument') or msg:lower():match('unknown flag')
--
--     if c ~= '' and not is_automated_arg and not is_flag_err then
--       local_discovered_codes[c] = true
--     end
--   end
--
--   -- Sort keys alphabetically
--   local registered_keys = {}
--   for k, _ in pairs(local_discovered_codes) do
--     table.insert(registered_keys, k)
--   end
--   table.sort(registered_keys)
--
--   local items = {}
--   if next(active_file_blocked) then
--     table.insert(items, { action = 'reset', text = '💥 Reset All Filters' })
--   end
--
--   -- Build the checkbox items layout
--   for _, c in ipairs(registered_keys) do
--     local is_blocked = active_file_blocked[c] == true
--     local mark = is_blocked and '[*]' or '[ ]'
--     local status = is_blocked and 'Restore' or 'Suppress'
--
--     table.insert(items, {
--       action = is_blocked and 'unblock' or 'block',
--       id = c,
--       text = string.format('  %s %s Code: [%s]', mark, status, c),
--     })
--   end
--
--   for f, _ in pairs(M.removed_flags) do
--     table.insert(items, { action = 'none', text = '  [-] ⚙️ [AUTOMATED]: ' .. f })
--   end
--
--   if #items == 0 then
--     vim.notify('✅ Clean Slate: No active lints.', vim.log.levels.INFO)
--     return
--   end
--
--   local block_count = 0
--   for _ in pairs(active_file_blocked) do
--     block_count = block_count + 1
--   end
--
--   vim.ui.select(items, {
--     prompt = string.format('📁 %s | Blocked: %d', vim.fs.basename(filter_db_path), block_count),
--     format_item = function(item)
--       return item.text
--     end,
--   }, function(choice)
--     if not choice then
--       -- 🟢 EXPLICIT SAVE POINT: User exits via Esc. Commit the final memory data down to disk!
--       local f = io.open(filter_db_path, 'wb')
--       if f then
--         local payload = { codes = active_file_blocked, flags = M.removed_flags }
--         f:write(require('nvimpio.utils.misc').jsonFormat(payload))
--         f:close()
--       end
--
--       -- Instantly re-trigger a buffer lint update on your viewport screen
--       vim.schedule(function()
--         if vim.api.nvim_buf_is_valid(bufnr) then
--           vim.api.nvim_buf_call(bufnr, function()
--             local old = vim.o.shortmess
--             vim.o.shortmess = old .. 'F'
--             vim.cmd('silent! checktime | silent! edit!')
--             vim.o.shortmess = old
--           end)
--         end
--       end)
--       return
--     end
--
--     if choice.action ~= 'none' then
--       -- Modify the memory state pointers array
--       if choice.action == 'reset' then
--         active_file_blocked = {}
--       elseif choice.action == 'block' then
--         active_file_blocked[choice.id] = true
--       elseif choice.action == 'unblock' then
--         active_file_blocked[choice.id] = nil
--       end
--     end
--
--     -- 🟢 RECURSION FIX: Pass the modified memory tracking table directly into
--     -- the next window state block loop, preventing the hard drive re-reads from wiping changes!
--     M.manage_file_diagnostics_interactive(active_file_blocked)
--   end)
-- end
-- function M.manage_file_diagnostics_interactive()
--   local bufnr = vim.api.nvim_get_current_buf()
--   local filter_db_path = get_db_path(bufnr)
--
--   -- 🟢 RIGID MEMORY ISOLATION: Read active configuration state strictly from disk file
--   local active_file_blocked = parse_db_file_pure(filter_db_path)
--
--   -- Rebuild the session mapping tracking database fresh from empty allocations
--   M.session_discovered_codes = {}
--
--   -- Populate menu indexing fields only with items currently active on disk
--   for code_key, is_true in pairs(active_file_blocked) do
--     if is_true then
--       M.session_discovered_codes[code_key] = true
--     end
--   end
--
--   -- Harvest and populate current screen error diagnostics text codes
--   local raw_diagnostics = vim.diagnostic.get(bufnr)
--   for _, d in ipairs(raw_diagnostics) do
--     local c = d.code or ''
--     local msg = d.message or ''
--     local is_automated_arg = c:match('^drv_') or c:match('^fatal_')
--     local is_flag_err = msg:lower():match('argument') or msg:lower():match('unknown flag')
--
--     if c ~= '' and not is_automated_arg and not is_flag_err then
--       M.session_discovered_codes[c] = true
--     end
--   end
--
--   local registered_keys = {}
--   for k, _ in pairs(M.session_discovered_codes) do
--     table.insert(registered_keys, k)
--   end
--   table.sort(registered_keys)
--
--   local items = {}
--   if next(active_file_blocked) then
--     table.insert(items, { action = 'reset', text = '💥 Reset All Filters' })
--   end
--
--   -- Re-build selection interface arrays cleanly
--   for _, c in ipairs(registered_keys) do
--     -- 🟢 INDUSTRY-STANDARD STABILITY VERIFICATION:
--     -- An item is rendering as a checked box [*] and "Restore" ONLY if it passes
--     -- verification inside your active_file_blocked database file state.
--     local is_blocked = active_file_blocked[c] == true
--     local mark = is_blocked and '[*]' or '[ ]'
--     local status = is_blocked and 'Restore' or 'Suppress'
--
--     table.insert(items, {
--       action = is_blocked and 'unblock' or 'block',
--       id = c,
--       text = string.format('  %s %s Code: [%s]', mark, status, c),
--     })
--   end
--
--   for f, _ in pairs(M.removed_flags) do
--     table.insert(items, { action = 'none', text = '  [-] ⚙️ [AUTOMATED]: ' .. f })
--   end
--
--   if #items == 0 then
--     vim.notify('✅ Clean Slate: No active lints.', vim.log.levels.INFO)
--     return
--   end
--
--   -- 🔍 THE CODES & FLAGS MEMORY INVENTORY TRACER
--   print('--- [PIO DEEP TRACE START] ---')
--   print('1. Contents of active_file_blocked:')
--   for k, v in pairs(active_file_blocked) do
--     print(string.format('   Key: [%s] -> Value: %s (Type: %s)', k, tostring(v), type(k)))
--   end
--
--   print('2. Total count in active_file_blocked loop:')
--   local test_count = 0
--   for _ in pairs(active_file_blocked) do
--     test_count = test_count + 1
--   end
--   print('   Count is: ' .. test_count)
--   print('--- [PIO DEEP TRACE END] ---')
--
--   -- Calculate how many codes are actually loaded in memory right now
--   local block_count = 0
--   for _ in pairs(active_file_blocked) do
--     block_count = block_count + 1
--   end
--   local short_db_name = vim.fs.basename(filter_db_path) or '.filter.json'
--   vim.ui.select(items, {
--     -- prompt = 'Filter Panel (Toggle items, press Esc to Save & Apply)',
--     -- prompt = string.format('DB Path: %s (Loaded keys: %d)', filter_db_path, block_count),
--     prompt = string.format('📁 %s | 🔑 Blocked: %d', short_db_name, block_count),
--     format_item = function(item)
--       return item.text
--     end,
--   }, function(choice)
--     if not choice then
--       -- User exits: Flush the current session modifications to file cleanly
--       local f = io.open(filter_db_path, 'wb')
--       if f then
--         local payload = { codes = active_file_blocked, flags = M.removed_flags }
--         f:write(require('nvimpio.utils.misc').jsonFormat(payload))
--         f:close()
--       end
--
--       vim.schedule(function()
--         if vim.api.nvim_buf_is_valid(bufnr) then
--           vim.api.nvim_buf_call(bufnr, function()
--             local old = vim.o.shortmess
--             vim.o.shortmess = old .. 'F'
--             vim.cmd('silent! checktime | silent! edit!')
--             vim.o.shortmess = old
--           end)
--         end
--       end)
--       return
--     end
--
--     if choice.action ~= 'none' then
--       if choice.action == 'reset' then
--         active_file_blocked = {}
--       elseif choice.action == 'block' then
--         active_file_blocked[choice.id] = true
--       elseif choice.action == 'unblock' then
--         active_file_blocked[choice.id] = nil
--       end
--
--       -- Instantly save state down to disk so recursive panel loops pull the true context maps
--       local f = io.open(filter_db_path, 'wb')
--       if f then
--         local payload = { codes = active_file_blocked, flags = M.removed_flags }
--         f:write(require('nvimpio.utils.misc').jsonFormat(payload))
--         f:close()
--       end
--     end
--
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
-- M.session_discovered_codes = {}
--
-- -- Defined exactly once to fix the 'redefined-local' linter warning
-- local markers = { 'platformio.ini', '.git' }
--
-- -- 1. Unified database path resolver (Accepts bufnr OR raw absolute path string)
-- local function get_db_path(source)
--   local f = ''
--
--   if type(source) == 'string' then
--     -- It's a raw file path string (Headless route)
--     f = source
--   elseif type(source) == 'number' or source == nil then
--     -- It's a buffer ID or nil (Live UI route)
--     local bufnr = source or vim.api.nvim_get_current_buf()
--     f = vim.api.nvim_buf_get_name(bufnr)
--   end
--
--   -- Resolve workspace root based on the discovered file path
--   local root_dir = (f ~= '') and vim.fs.root(f, markers) or nil
--
--   -- Fallback logic to protect loose files
--   if not root_dir and (type(source) == 'number' or source == nil) then
--     local bufnr = source or vim.api.nvim_get_current_buf()
--     local clients = vim.lsp.get_clients({ bufnr = bufnr })
--     if #clients > 0 then
--       root_dir = clients[1].config.root_dir
--     end
--   end
--
--   root_dir = root_dir or vim.uv.cwd()
--   return vim.fs.joinpath(root_dir, '.filter.json')
-- end
--
-- -- 2. Load persistent json arrays from disk
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
--     local payload = { codes = M.manual_blocked_codes, flags = M.removed_flags }
--     local pretty = require('nvimpio.utils.misc').jsonFormat(payload)
--     f:write(pretty)
--     f:close()
--   end
-- end
--
-- -- ===================================================================
-- -- 4. 🟢 ENGINE PATH A: Clean Project-Wide Toolchain Flags (Rigid Root)
-- -- ===================================================================
-- function M.clean_project_wide_flags(project_root, diagnostics)
--   if not diagnostics or #diagnostics == 0 then
--     return
--   end
--
--   local boiler = require('nvimpio.boilerplate')
--   boiler.remove = boiler.remove or {}
--
--   local flags_updated = false
--   for _, diag in ipairs(diagnostics) do
--     local code = diag.code
--     local msg = diag.message or ''
--
--     -- Identify toolchain driver errors using generic syntax rules
--     local is_drv = false
--     if type(code) == 'string' then
--       is_drv = code:match('^drv_') or code:match('^fatal_') or msg:lower():match('argument')
--     end
--
--     if is_drv then
--       local flag = msg:match('(%-[fmWOdsx][%w%-%.%*]+)')
--       if flag and not M.removed_flags[flag] then
--         table.insert(boiler.remove, flag)
--         M.removed_flags[flag] = true
--         flags_updated = true
--       end
--     end
--   end
--
--   -- Write updates straight to disk if a new bad compiler argument was caught
--   if flags_updated then
--     local filter_db_path = vim.fs.joinpath(project_root, '.filter.json')
--     local f = io.open(filter_db_path, 'wb')
--     if f then
--       local payload = { codes = M.manual_blocked_codes, flags = M.removed_flags }
--       f:write(require('nvimpio.utils.misc').jsonFormat(payload))
--       f:close()
--     end
--
--     local boilerplate_gen = boiler.boilerplate_gen
--     if boilerplate_gen then
--       pcall(boilerplate_gen, '.clangd', project_root)
--     end
--   end
-- end
-- -- function M.clean_file_path_pipeline(absolute_file_path, diagnostics)
-- --   -- print(absolute_file_path)
-- --   if not absolute_file_path or absolute_file_path == '' then
-- --     return {}
-- --   end
-- --   diagnostics = diagnostics or {}
-- --
-- --   local filter_db_path = get_db_path(absolute_file_path)
-- --   local project_root = vim.fs.dirname(filter_db_path) -- Derive root folder directly from db location
-- --
-- --   -- Isolated disk lookup matching standard JSON loader
-- --   local manual_blocked = {}
-- --   local db_file = io.open(filter_db_path, 'rb')
-- --   if db_file then
-- --     local raw = db_file:read('*all')
-- --     db_file:close()
-- --     if raw and raw ~= '' then
-- --       local ok, data = pcall(vim.json.decode, raw)
-- --       if ok and data and type(data.codes) == 'table' then
-- --         for k, v in pairs(data.codes) do
-- --           local s = (type(k) == 'string') and k or v
-- --           if type(s) == 'string' and s ~= '' then
-- --             manual_blocked[s] = true
-- --           end
-- --         end
-- --       end
-- --     end
-- --   end
-- --
-- --   local boiler = require('nvimpio.boilerplate')
-- --   boiler.remove = {}
-- --
-- --   local clean_diagnostics = {}
-- --   for _, diag in ipairs(diagnostics) do
-- --     local keep = true
-- --     local code = diag.code
-- --     local msg = diag.message or ''
-- --
-- --     local is_drv = false
-- --     if type(code) == 'string' then
-- --       local lower_code = code:lower()
-- --       local lower_msg = msg:lower()
-- --       local has_driver_prefix = lower_code:match('^drv_') or lower_code:match('^fatal_')
-- --       local has_flag_keywords = lower_msg:match('argument') or lower_msg:match('unknown flag') or lower_msg:match('command line option')
-- --
-- --       if has_driver_prefix or has_flag_keywords then
-- --         is_drv = true
-- --       end
-- --     end
-- --
-- --     if is_drv then
-- --       keep = false
-- --       -- local f = msg:match('(%-[%w%-%.%*]+)')
-- --       -- [fmWOdsx] represents the universal language categories used by the entire GCC and Clang compiler family globally
-- --       -- f: Compiler Features / Optimizations (e.g., -fexceptions, -fno-rtti)
-- --       -- m: Machine / Architecture Directives (e.g., -mlongcalls, -mthumb)
-- --       -- W: Warning parameters (e.g., -Wno-deprecated, -Wsign-compare)
-- --       -- O: Optimization Levels (e.g., -Os, -O2)
-- --       -- d / s / x: Internal Debugging, Standards, and Language flags (e.g., -ggdb, -std=c++17, -xc++)
-- --       -- Starts strictly with a hyphen followed by a valid single-letter flag category indicator (f, m, W, O, d, s, x)
-- --       local f = msg:match('(%-[fmWOdsx][%w%-%.%*]+)')
-- --       if f then
-- --         table.insert(boiler.remove, f)
-- --         M.removed_flags[f] = true
-- --       end
-- --     elseif code and manual_blocked[code] then
-- --       keep = false
-- --     end
-- --
-- --     if code and type(code) == 'string' and code ~= '' and not is_drv then
-- --       M.session_discovered_codes[code] = true
-- --     end
-- --
-- --     if keep then
-- --       table.insert(clean_diagnostics, diag)
-- --     end
-- --   end
-- --
-- --   local boilerplate_gen = boiler.boilerplate_gen
-- --   if boilerplate_gen then
-- --     pcall(boilerplate_gen, '.clangd', project_root)
-- --   end
-- --
-- --   return clean_diagnostics
-- -- end
--
-- -- ===================================================================
-- -- 5. 🟢 ENGINE PATH B: Clean Source Code File Diagnostics (Pure Files)
-- -- ===================================================================
-- function M.clean_file_path_pipeline(absolute_file_path, diagnostics)
--   if not diagnostics or #diagnostics == 0 then
--     return diagnostics
--   end
--
--   local project_root = vim.fs.root(absolute_file_path, { 'platformio.ini', '.git' }) or vim.uv.cwd()
--   local filter_db_path = vim.fs.joinpath(project_root, '.filter.json')
--
--   -- Read the project-specific blocked codes dictionary map
--   local manual_blocked = {}
--   local db_file = io.open(filter_db_path, 'rb')
--   if db_file then
--     local raw = db_file:read('*all')
--     db_file:close()
--     if raw and raw ~= '' then
--       local ok, data = pcall(vim.json.decode, raw)
--       if ok and data and type(data.codes) == 'table' then
--         for k, v in pairs(data.codes) do
--           local s = (type(k) == 'string') and k or v
--           if type(s) == 'string' and s ~= '' then
--             manual_blocked[s] = true
--           end
--         end
--       end
--     end
--   end
--
--   local clean_diagnostics = {}
--   for _, diag in ipairs(diagnostics) do
--     local code = diag.code
--     if not (code and manual_blocked[code]) then
--       table.insert(clean_diagnostics, diag)
--       if code and type(code) == 'string' and code ~= '' then
--         M.session_discovered_codes[code] = true
--       end
--     end
--   end
--
--   return clean_diagnostics
-- end
-- -- function M.clean_diagnostics_pipeline(diagnostics, bufnr)
-- --   bufnr = bufnr or vim.api.nvim_get_current_buf()
-- --   local absolute_file_path = vim.api.nvim_buf_get_name(bufnr)
-- --   print(absolute_file_path)
-- --   return M.clean_file_path_pipeline(absolute_file_path, diagnostics)
-- -- end
--
-- -- ===================================================================
-- -- 6. INTERACTIVE DYNAMIC CHECKBOX PICKER
-- -- ===================================================================
-- function M.manage_file_diagnostics_interactive()
--   local bufnr = vim.api.nvim_get_current_buf()
--   load_db(bufnr)
--   local items = {}
--
--   if next(M.manual_blocked_codes) then
--     table.insert(items, { action = 'reset', text = '💥 Reset All Filters' })
--   end
--
--   local raw_diagnostics = vim.diagnostic.get(bufnr)
--   for _, d in ipairs(raw_diagnostics) do
--     local c = d.code or ''
--     local msg = d.message or ''
--     local is_automated_arg = c:match('^drv_') or c:match('^fatal_')
--     local is_flag_err = msg:match('argument') or msg:match('unknown flag')
--
--     if c ~= '' and not is_automated_arg and not is_flag_err then
--       M.session_discovered_codes[c] = true
--     end
--   end
--
--   local registered_keys = {}
--   for k, _ in pairs(M.session_discovered_codes) do
--     table.insert(registered_keys, k)
--   end
--   table.sort(registered_keys)
--
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
--   for f, _ in pairs(M.removed_flags) do
--     table.insert(items, { action = 'none', text = '  [-] ⚙️ [AUTOMATED]: ' .. f })
--   end
--
--   if #items == 0 then
--     vim.notify('✅ Clean Slate: No active lints.', vim.log.levels.INFO)
--     return
--   end
--
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
--     if choice.action == 'reset' then
--       M.manual_blocked_codes = {}
--     elseif choice.action == 'block' then
--       M.manual_blocked_codes[choice.id] = true
--     elseif choice.action == 'unblock' then
--       M.manual_blocked_codes[choice.id] = nil
--     end
--
--     save_db(bufnr)
--     M.manage_file_diagnostics_interactive()
--   end)
-- end
--
-- -------------------------------------------------------------
-- -- local boilerplate = require('nvimpio.boilerplate')
-- -- local boilerplate_gen = boilerplate.boilerplate_gen
-- --
-- -- local target_file = vim.fs.find(function(name)
-- --   return name:match('%.cpp$') or name:match('%.c$')
-- -- end, { limit = 1, path = vim.uv.cwd() .. '/src' })[1]
-- --
-- -- if not target_file then
-- --   boilerplate_gen([[main.cpp]], vim.uv.cwd() .. '/src')
-- --   boilerplate_gen([[main.hpp]], vim.uv.cwd() .. '/include')
-- --   target_file = vim.uv.cwd() .. '/src/main.cpp'
-- -- end
-- --
-- -- if target_file then
-- --   -- 1. Use Neovim's URI converter to locate the hidden memory buffer for the path
-- --   local target_uri = vim.uri_from_fname(target_file)
-- --   local target_bufnr = vim.uri_to_bufnr(target_uri)
-- --   -- 2. Query Neovim's diagnostic tracking pool for this specific buffer
-- --   local raw_diagnostics = vim.diagnostic.get(target_bufnr)
-- --   -- 3. Feed the results straight into your clean file pipeline core
-- --   print(vim.inspect(raw_diagnostics))
-- --   M.clean_file_path_pipeline(target_file, raw_diagnostics)
-- -- end
--
-- -- stylua: ignore end
-- return M
