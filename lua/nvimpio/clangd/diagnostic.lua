-- stylua: ignore start
local M = {}

-- Module scopes track cross-file automated session states safely
M.blocked = {  codes= {}, flags= {}}
-- M.manual_blocked_codes = M.manual_blocked_codes or {}
-- M.auto_removed_flags = M.auto_removed_flags or {}
M.session_discovered_codes = M.session_discovered_codes or {}

-- ⚡ DISK CACHE LAYER: Prevents synchronous file reads on hot diagnostic loops
M.cached_db_mtime = 0

local function get_db_path()
  return vim.fs.joinpath(OS.nvimpio_env_dir, OS.clangd_filter)
end

-- ===================================================================
-- 📁  1. SELF-HEALING ENGINE: Seeds a default configuration template if missing
-- ===================================================================
local function ensure_default_db_exists(db_path)
  -- Check if the file already exists on the hard drive
  local stat = vim.uv.fs_stat(db_path)
  -- File exists, do not overwrite it!
  if stat then return true end

  local raw_json = '{\n  "codes": {},\n  "flags": {}\n}'
  -- Perform a safe, single-point background disk write operation
  local f = io.open(db_path, 'wb')
  if f then
    f:write(raw_json)
    f:close()
    return true
  end
  return false
end

-- 2. Pure local JSON reading loop (Strictly separates codes from compiler flags)
local function parse_db_file_pure(db_path)
  ensure_default_db_exists(db_path)

  local blocked_codes = {  codes= {}, flags= {}}
  -- local blocked_codes = {}
  local f = io.open(db_path, 'rb')
  if not f then return blocked_codes end
  local raw = f:read('*all')
  f:close()

  if raw and raw ~= '' then
    local ok, data = pcall(vim.json.decode, raw)
    if ok and data and type(data.flags) == 'table' then
      for k, v in pairs(data.flags) do
        local code_str = nil
        if type(k) == 'string' and k ~= '' then code_str = k
        elseif type(v) == 'string' and v ~= '' then code_str = v end

        -- Ensure we only load it if it was explicitly marked as true inside the codes sub-section
        if code_str and data.codes[k] == true then blocked_codes.flags[code_str] = true end
      end
    end
    if ok and data and type(data.codes) == 'table' then
      for k, v in pairs(data.codes) do
        local code_str = nil
        if type(k) == 'string' and k ~= '' then code_str = k
        elseif type(v) == 'string' and v ~= '' then code_str = v end

        -- Ensure we only load it if it was explicitly marked as true inside the codes sub-section
        if code_str and data.codes[k] == true then blocked_codes.codes[code_str] = true end
      end
    end
  end
  return blocked_codes
end

-- ⚡ OPTIMIZED CACHE: Only reads disk if the JSON file's modified time (mtime) changes
function M.get_manual_blocked(filter_db_path)
  local stat = vim.uv.fs_stat(filter_db_path)
  local current_mtime = stat and stat.mtime.sec or 0

  if current_mtime == 0 or current_mtime ~= M.cached_db_mtime then
    M.blocked = parse_db_file_pure(filter_db_path)
    M.cached_db_mtime = current_mtime
  end

  return M.blocked
end
-- ⚡ OPTIMIZED CACHE: Only reads disk if the JSON file's modified time (mtime) changes
-- local function get_manual_blocked_cached(filter_db_path)
--   local stat = vim.uv.fs_stat(filter_db_path)
--   local current_mtime = stat and stat.mtime.sec or 0
--
--   if current_mtime == 0 or current_mtime ~= M.cached_db_mtime then
--     M.manual_blocked_codes = parse_db_file_pure(filter_db_path)
--     M.cached_db_mtime = current_mtime
--   end
--
--   return M.manual_blocked_codes
-- end

-- -- ========================================================================================
-- -- 🛠️ ENGINE PATH A: Auto Clean Project-Wide(col 0, raw 0) Toolchain Flags (The Extractor)
-- -- ========================================================================================
-- function M.clean_project_wide_flags(diagnostics)
--   if not diagnostics or #diagnostics == 0 then
--     return
--   end
--   local flags_updated = false
--
--   for _, diag in ipairs(diagnostics) do
--     local code = diag.code
--     local msg = diag.message or ''
--     local is_drv = type(code) == 'string' and (code:match('^drv_') or code:match('^fatal_') or msg:lower():match('argument'))
--
--     if is_drv then
--       -- [fmWOgsx] represents the universal language categories used by the entire GCC and Clang compiler family globally
--       -- f: Compiler Features / Optimizations (e.g., -fexceptions, -fno-rtti)
--       -- m: Machine / Architecture Directives (e.g., -mlongcalls, -mthumb)
--       -- W: Warning parameters (e.g., -Wno-deprecated, -Wsign-compare)
--       -- O: Optimization Levels (e.g., -Os, -O2)
--       -- g / s / x: Internal Debugging, Standards, and Language flags (e.g., -ggdb, -std=c++17, -xc++)
--       -- Starts strictly with a hyphen followed by a valid single-letter flag category indicator (f, m, W, O, d, s, x)
--       -- Generic character class limits flags to true compiler options (-m, -f, -W, etc.), dropping English text words
--       local flag = msg:match('(%-[fmWOgsx][%w%-%.%*]+)')
--       -- 🟢 SINGLE SEED: Only modify your private master module dictionary map!
--       if flag and not M.auto_removed_flags[flag] then
--         M.auto_removed_flags[flag] = true
--         flags_updated = true
--       end
--     end
--   end
--
--   if flags_updated then
--     local filter_db_path = get_db_path()
--     local current_blocked = parse_db_file_pure(filter_db_path)
--
--     local f = io.open(filter_db_path, 'wb')
--     if f then
--       local payload = { codes = current_blocked, flags = M.auto_removed_flags }
--       f:write(require('nvimpio.utils.misc').jsonFormat(payload))
--       f:close()
--     end
--
--     -- Trigger the boilerplate generation process
--     local boiler = require('nvimpio.boilerplate')
--     if boiler and boiler.boilerplate_gen then
--       -- pcall(boiler.boilerplate_gen, '.clangd', project_root, 'diagnostics wipe flags')
--       pcall(boiler.boilerplate_gen, '.clangd', 'diagnostics wipe flags')
--     end
--   end
-- end

function M.unknownArgs()
  local filter_db_path = get_db_path()
  local caced_blocked = M.get_manual_blocked(filter_db_path)

  local f = io.open(filter_db_path, 'wb')
  if f then
    -- local payload = { codes = manual_blocked, flags = M.auto_removed_flags }
    f:write(require('nvimpio.utils.misc').jsonFormat(caced_blocked))
    f:close()
  end
  M.cached_db_mtime = 0 -- Invalidate cache

  -- Trigger the boilerplate generation process
  local boiler = require('nvimpio.boilerplate')
  if boiler and boiler.boilerplate_gen then
    -- pcall(boiler.boilerplate_gen, '.clangd', OS.project_dir, 'diagnostics wipe flags')
    pcall(boiler.boilerplate_gen, '.clangd', 'diagnostics wipe flags')
  end
end

-- ========================================================================
-- 🛠️ ENGINE PATH B: manual Clean Source Code File Diagnostics (Pure Files)
-- ========================================================================
function M.clean_file_path_pipeline(diagnostics)
  if not diagnostics or #diagnostics == 0 then return diagnostics end
  local filter_db_path = get_db_path()

  -- Pure localized read ensures we only check blocks configured for THIS project folder
  -- local manual_blocked = get_manual_blocked_cached(filter_db_path)

  local clean_diagnostics = {}
  local flags_updated = false

  for _, diag in ipairs(diagnostics) do
    local show_diagnostics = true

    -- local code = diag.code
    local code = diag.code and tostring(diag.code) or nil
    local msg = diag.message or ''

    -- local is_drv = type(code) == 'string' and (code:match('^drv_') or code:match('^fatal_') or msg:lower():match('argument'))
    -- local is_drv = code and (code:match('^drv_') or code:match('^fatal_') or msg:lower():match('argument'))
    -- ⚡ OPTIMIZED: Case-insensitive match without allocating new strings via msg:lower()
    local is_drv = code and (
      code:match('^drv_')
      or code:match('^fatal_')
      or msg:match('[Aa][Rr][Gg][Uu][Mm][Ee][Nn][Tt]')
    )

    if is_drv then
      show_diagnostics = false
      -- [fmWOgsx] represents the universal language categories used by the entire GCC and Clang compiler family globally
      -- f*: Compiler Features / Optimizations , codegen, and system prefix maps (e.g., -fexceptions, -fno-rtti)
      -- m*: Target machine / Architecture Directives (e.g., -mlongcalls, -mthumb)
      -- W*: Warning parameters (e.g., -Wno-deprecated, -Wsign-compare)
      -- O*: Optimization Levels (e.g., -Os, -O2)
      -- g* / s* / x*: Internal Debugging, Standards, and Language flags (e.g., -ggdb, -std=c++17, -xc++)
      -- Starts strictly with a hyphen followed by a valid single-letter flag category indicator (f, m, W, O, d, s, x)
      -- Generic character class limits flags to true compiler options (-m, -f, -W, etc.), dropping English text words
      local flag = msg:match('(%-[fmWOgsx][%w%-%.%*]+)')

      -- 🟢 SINGLE SOURCE SEED: Update only your master memory dictionary map!
      if flag and not M.blocked.flags[flag] then
        M.blocked.flags[flag] = true  -- ** the only place updates M.auto_removed_flags
        flags_updated = true          -- if updated write it below to file
      end
    -- elseif code and manual_blocked[code] then show_diagnostics = false end
    elseif code and M.blocked.codes[code] then show_diagnostics = false end

    if show_diagnostics then table.insert(clean_diagnostics, diag) end
  end

  if flags_updated then
    vim.schedule(function()
    -- 🟢 SINGLE-POINT FLUSH POINT: Trigger only if a brand-new unknown flag was caught mid-flight
      local misc_ok, misc = pcall(require, 'nvimpio.utils.misc')
      local raw_payload = misc_ok and misc.jsonFormat
        -- and misc.jsonFormat({ codes = manual_blocked, flags = M.auto_removed_flags })
        -- and misc.jsonFormat({ codes = M.manual_blocked_codes, flags = M.auto_removed_flags })
        and misc.jsonFormat(M.blocked)
        or '{\n  "codes": {},\n  "flags": {}\n}'

      local f = io.open(filter_db_path, 'wb')
      if f then
        f:write(raw_payload)
        f:close()
        M.cached_db_mtime = 0 -- Invalidate mtime cache
      end

      -- Let the dynamic boilerplate loop read pio_diag.auto_removed_flags directly on disk generation!
      local boiler_ok, boiler = pcall(require, 'nvimpio.boilerplate')
      if boiler_ok and boiler and boiler.boilerplate_gen then
        pcall(boiler.boilerplate_gen, '.clangd', 'diagnostics clean_file_path_pipeline')
      end
    end)
  end

  return clean_diagnostics
end

-- ===================================================================
-- 💻 THE INTERACTIVE DYNAMIC CHECKBOX PICKER PANEL (STATE MACHINE)
-- ===================================================================
function M.manage_file_diagnostics_interactive()
  local bufnr = vim.api.nvim_get_current_buf()
  local filter_db_path = get_db_path()

  -- 🟢 SELF-HEALING INTERCEPTION: Guarantee the database file is active before memory tracking maps populate
  ensure_default_db_exists(filter_db_path)

  -- -- 🟢 THE NEOVIIM COMMAND PROTECTION SHIELD:
  -- -- If state_override contains a 'name' field, it is a Neovim command metadata block object!
  -- -- Discard it instantly and force it back to a clean disk load via parse_db_file_pure()
  -- local is_command_object = type(state_override) == 'table' and state_override.name ~= nil
  -- if is_command_object then state_override = nil end

  -- Initialize memory state tracking layer from disk or incoming RAM state
  -- local active_file_blocked = M.get_manual_blockedd(filter_db_path)
  local caced_blocked = M.get_manual_blocked(filter_db_path)
  local active_file_blocked = caced_blocked.codes

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
    local c = d.code and tostring(d.code) or ''
    local msg = d.message or ''
    local is_automated_arg = c:match('^drv_') or c:match('^fatal_')
    local is_flag_err = msg:match('[Aa][Rr][Gg][Uu][Mm][Ee][Nn][Tt]') or msg:lower():match('unknown flag')
    -- local is_flag_err = msg:lower():match('argument') or msg:lower():match('unknown flag')

    if c ~= '' and not is_automated_arg and not is_flag_err then
      M.session_discovered_codes[c] = true
    end
  end

  -- Sort keys alphabetically
  local registered_keys = {}
  for k, _ in pairs(M.session_discovered_codes) do table.insert(registered_keys, k) end
  table.sort(registered_keys)

  local items = {}
  -- 🟢 1. Dynamic check: Prepend "Reset All" if any items are currently blocked
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

  for f, _ in pairs(caced_blocked.flags) do
    table.insert(items, { action = 'none', text = '  [-] ⚙️ [AUTOMATED]: ' .. f })
  end

  if #items == 0 then
    vim.notify('✅ Clean Slate: No active lints.', vim.log.levels.INFO)
    return
  end

  local block_count = 0
  for _ in pairs(active_file_blocked) do block_count = block_count + 1 end

  --------------------------------------------------------------------------------------------
  vim.ui.select(items, {
    prompt = string.format('📁 %s | Blocked: %d', vim.fs.basename(filter_db_path), block_count),
    format_item = function(item) return item.text end,
  }, function(choice)
    -- GATE 1: User pressed Escape or q. Save choices to disk exactly once!
    if not choice then
      local f = io.open(filter_db_path, 'wb')
      if f then
        -- local payload = M.get_manual_blocked(filter_db_path)
        -- local payload = { codes = active_file_blocked, flags = M.auto_removed_flags }
        f:write(require('nvimpio.utils.misc').jsonFormat(caced_blocked))
        f:close()
        -- 🟢 Invalidate or refresh cache here so the getter reloads the new state
        M.cached_db_mtime = 0 -- Invalidate cache
      end

      -- Flush session cache arrays entirely out of RAM memory on exit
      -- M.session_discovered_codes = nil
      --Clean memory table safely without destroying the reference table pointer
      for k in pairs(M.session_discovered_codes) do M.session_discovered_codes[k] = nil end

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
      return -- Halts execution completely.
    end

    --------------------------------------------------------------------------------------------
    -- GATE 2: User clicked an automated read-only logger flag row item
    -- Do nothing, let user keep browsing
    if choice.action == 'none' then return end

    -- GATE 3: User selected a valid row checkbox item to toggle.
    -- This modifies active_file_blocked in live parent RAM memory instantly!
    if choice.action == 'reset' then
      -- 1. Clear table in place (preserves table pointer)
      for k in pairs(active_file_blocked) do active_file_blocked[k] = nil end
      -- 2. Update every item's state and text in memory
      for _, item in ipairs(items) do
        if item.id then
          item.action = 'block'
          item.text = string.format('  [ ] Suppress Code: [%s]', item.id)
        end
      end
    elseif choice.action == 'block' then
      active_file_blocked[choice.id] = true
      choice.action = 'unblock' -- Flip item state string
    elseif choice.action == 'unblock' then
      active_file_blocked[choice.id] = nil
      choice.action = 'block' -- Flip item state string
    end

    -- Dynamically recalculate choice.text so our live redraw engine can read it instantly
    if choice.id and choice.action ~= 'reset' then
      local is_blocked = active_file_blocked[choice.id] == true
      local mark = is_blocked and '[*]' or '[ ]'
      local status = is_blocked and 'Restore' or 'Suppress'
      choice.text = string.format('  %s %s Code: [%s]', mark, status, choice.id)
    end
    --------------------------------------------------------------------------------------------
    -- 🟢 2. DYNAMIC RESET ROW SYNC:
    -- Ensure "Reset All Filters" dynamically appears when something is blocked, 
    -- or disappears when all filters are cleared.
    local has_blocked = next(active_file_blocked) ~= nil
    local has_reset_row = items[1] and items[1].action == 'reset'

    if has_blocked and not has_reset_row then
      -- First item blocked: insert "Reset All" row at position 1
      table.insert(items, 1, { action = 'reset', text = '💥 Reset All Filters' })
    elseif not has_blocked and has_reset_row then
      -- All items cleared: remove "Reset All" row from position 1
      table.remove(items, 1)
    end
    --------------------------------------------------------------------------------------------
  end)
end
-- stylua: ignore end
return M
