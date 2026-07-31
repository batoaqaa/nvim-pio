-- stylua: ignore start
local M = {}

-- Module scopes track cross-file automated session states safely
M.blocked = { proj_codes= {}, pckg_codes= {}, flags= {} }
M.session_discovered_codes = M.session_discovered_codes or {}

local autoProj, autoPckg = false, true
-- ⚡ DISK CACHE LAYER: Prevents synchronous file reads on hot diagnostic loops
M.cached_db_mtime = 0

function M.get_db_path() return vim.fs.joinpath(OS.nvimpio_env_dir, OS.clangd_filter) end

-- ===================================================================
-- 📁  1. SELF-HEALING ENGINE: Seeds a default configuration template if missing
-- ===================================================================
local function ensure_default_db_exists(db_path)
  -- Check if the file already exists on the hard drive
  local stat = vim.uv.fs_stat(db_path)
  -- File exists, do not overwrite it!
  if stat then return true end

  local raw_json = '{\n  "proj_codes": {},\n  "pckg_codes": {},\n  "flags": {}\n}'
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

  local blocked_codes = { proj_codes= {}, pckg_codes= {}, flags= {}}

  local f = io.open(db_path, 'rb')
  if not f then return blocked_codes end
  local raw = f:read('*all')
  f:close()

  if raw and raw ~= '' then
    local ok, data = pcall(vim.json.decode, raw)
    if ok and data and type(data) == 'table' then
      blocked_codes = data
    end
  end
  return blocked_codes
end

-- ⚡ OPTIMIZED CACHE: Only reads disk if the JSON file's modified time (mtime) changes
function M.get_manual_blocked(filter_db_path)
  local stat = vim.uv.fs_stat(filter_db_path)

  -- Combine sec and nsec to catch fast same-second file updates
  -- local current_mtime = stat and (stat.mtime.sec + (stat.mtime.nsec or 0) / 1e9) or 0
  local current_mtime = stat and stat.mtime.sec or 0

  if current_mtime == 0 or current_mtime ~= M.cached_db_mtime then
    M.blocked = parse_db_file_pure(filter_db_path)
    M.cached_db_mtime = current_mtime
  end

  return M.blocked
end


-- function M.unknownArgs()
--   local filter_db_path = M.get_db_path()
--   local caced_blocked = M.get_manual_blocked(filter_db_path)
--
--   local f = io.open(filter_db_path, 'wb')
--   if f then
--     -- local payload = { codes = manual_blocked, flags = M.auto_removed_flags }
--     f:write(require('nvimpio.utils.misc').jsonFormat(caced_blocked))
--     f:close()
--   end
--   M.cached_db_mtime = 0 -- Invalidate cache
--
--   -- Trigger the boilerplate generation process
--   local boiler = require('nvimpio.boilerplate')
--   if boiler and boiler.boilerplate_gen then
--     -- pcall(boiler.boilerplate_gen, '.clangd', OS.project_dir, 'diagnostics wipe flags')
--     pcall(boiler.boilerplate_gen, '.clangd', 'diagnostics wipe flags')
--   end
-- end

-- ========================================================================
-- 🛠️ ENGINE PATH B: manual Clean Source Code File Diagnostics (Pure Files)
-- ========================================================================
function M.clean_file_path_pipeline(result)  -- change pio flags/codes  --> write
  local diagnostics = result and result.diagnostics
  if not diagnostics or #diagnostics == 0 then return diagnostics end

  -- Safe path resolution
  local raw_uri = result.uri
  local target_path = raw_uri and raw_uri ~= "" and vim.fs.normalize(vim.uri_to_fname(raw_uri)) or ""
  local project_dir    = OS.project_dir

  -- Safe framework_root matching
  local framework_root = _G.metadata and _G.metadata.framework_root
  local toolchain_root = _G.metadata and _G.metadata.toolchain_root

  -- Lowercase ONLY on Windows to handle clangd's drive-letter/user casing quirks
  if OS.is_win then
    target_path    = target_path:lower()
    framework_root = framework_root and framework_root:lower()
    toolchain_root = toolchain_root and toolchain_root:lower()
    project_dir    = project_dir and project_dir:lower()
  end

  local is_pio = (
    (framework_root and framework_root ~= "" and target_path:find(framework_root, 1, true) ~= nil)
    or (toolchain_root and toolchain_root ~= "" and target_path:find(toolchain_root, 1, true) ~= nil)
  ) or false
  -- local is_pio = (framework_root and framework_root ~= "")
  --   and (target_path:find(framework_root, 1, true) ~= nil)
  --   or false
  local is_proj = target_path:find(project_dir, 1, true) ~= nil

  -- Localized shortcuts for hot-loop execution speed
  local tbl_insert = table.insert
  local str_match = string.match
  local clean_diagnostics = {}
  local flags_updated = false


  -- Pre-verify storage tables exist
  M.blocked = M.blocked or {}
  M.blocked.flags = M.blocked.flags or {}
  M.blocked.pckg_codes = M.blocked.pckg_codes or {}
  M.blocked.proj_codes = M.blocked.proj_codes or {}

  local blocked_flags = M.blocked.flags
  local blocked_pckg_codes = M.blocked.pckg_codes
  local blocked_proj_codes = M.blocked.proj_codes

  for i = 1, #diagnostics do
    local diag = diagnostics[i]
    local show_diagnostics = true

    -- local code = diag.code
    local code = diag.code and tostring(diag.code) or nil
    local msg = diag.message or ''

    -- Check if the error is positioned at Row 0, Column 0
    local range = diag.range and diag.range['start']
    local is_row0_col0 = range and (range.line == 0 and range.character == 0)

    -- if diagnostics for [column 0 , row 0]
    if is_row0_col0 then
      -- print('1: ' .. code)
      -- Evaluate match on either code OR message (code can be nil!)
      local is_setup_issue =
        str_match(msg,'%.clangd')
        or str_match(msg,'compile_commands')
        or (code and (str_match(code,'^drv_') or str_match(code,'^fatal_')))
        or str_match(msg,'[Aa][Rr][Gg][Uu][Mm][Ee][Nn][Tt]')
      if is_setup_issue then -- if they are compiler/config/setup errors
        -- [fmWOgsx] represents the universal language categories used by the entire GCC and Clang compiler family globally
        -- f*: Compiler Features / Optimizations , codegen, and system prefix maps (e.g., -fexceptions, -fno-rtti)
        -- m*: Target machine / Architecture Directives (e.g., -mlongcalls, -mthumb)
        -- W*: Warning parameters (e.g., -Wno-deprecated, -Wsign-compare)
        -- O*: Optimization Levels (e.g., -Os, -O2)
        -- dM or dD (used to dump macro definitions)
        -- g* / s* / x*: Internal Debugging, Standards, and Language flags (e.g., -ggdb, -std=c++17, -xc++)
        -- Starts strictly with a hyphen followed by a valid single-letter flag category indicator (f, m, W, O, d, s, x)
        -- Generic character class limits flags to true compiler options (-m, -f, -W, etc.), dropping English text words
        -- local flag = str_match(msg,'(%-[fmWOdgsx][%w%-%.%*]+)')
        -- Matches flags like -fno-shrink-wrap, -mlongcalls, -Wno-unused even inside single quotes '...'
        local flag = str_match(msg, "'?(%-[fmWOdgsx][%w%-%.%*]+)'?")

        -- Update master dictionary if a new flag was caught
        if flag then
          show_diagnostics = false
          if not blocked_flags[flag] then
            blocked_flags[flag] = true  -- ** the only place updates M.blocked.flags
            flags_updated = true          -- if updated write it below to file
          end
        elseif code then
          -- if (code and blocked_pckg_codes[code]) then show_diagnostics = false
          -- elseif autoPckg then
            -- Suppress diagnostics inside the pio framework root
            show_diagnostics = false
            -- If it's a Row 0 / Col 0 setup issue with NO flag in the msg (like fatal_too_many_errors),
            -- capture its error code into blocked_pckg_codes!
            if not blocked_pckg_codes[code] then
              blocked_pckg_codes[code] = true
              flags_updated = true
            end
          -- end
        end
      end
    elseif is_pio then
      -- print('2: ' .. code)
      if (code and blocked_pckg_codes[code]) then show_diagnostics = false
      elseif autoPckg then
        -- Suppress diagnostics inside the pio framework root
        show_diagnostics = false
        if code and not blocked_pckg_codes[code] then
          blocked_pckg_codes[code] = true  -- ** the only place updates M.blocked.pckg_codes
          flags_updated = true          -- if updated write it below to file
        end
      end
    elseif is_proj then
      -- print('3: ' .. code)
      if (code and blocked_proj_codes[code]) then show_diagnostics = false
      elseif autoProj then
        -- Suppress diagnostics inside the pio framework root
        show_diagnostics = false
        if code and not blocked_proj_codes[code] then
          blocked_proj_codes[code] = true  -- ** the only place updates M.blocked.pckg_codes
          flags_updated = true          -- if updated write it below to file
        end
      end
    end
    -- elseif code and blocked_pckg_codes[code] then show_diagnostics = false end

    if show_diagnostics then tbl_insert(clean_diagnostics, diag) end
  end

  if flags_updated then  -- write
    vim.schedule(function()
      -- Let the dynamic boilerplate loop read pio_diag.M.blocked
      local boiler_ok, boiler = pcall(require, 'nvimpio.boilerplate')
      if boiler_ok and boiler and boiler.boilerplate_gen then
        pcall(boiler.boilerplate_gen, '.clangd', 'diagnostics clean_file_path_pipeline')
      end

      local filter_db_path = M.get_db_path()
      local misc_ok, misc = pcall(require, 'nvimpio.utils.misc')
      if (misc_ok and misc) then
        misc.writeFile(filter_db_path, misc.jsonFormat(M.blocked), {})
        M.cached_db_mtime = 0 -- Invalidate mtime cache
      end
    end)
  end

  return clean_diagnostics
end

-- ===================================================================
-- 💻 THE INTERACTIVE DYNAMIC CHECKBOX PICKER PANEL (STATE MACHINE)
-- ===================================================================
function M.manage_file_diagnostics_interactive()   -- change pckg_codes  --> write
  local bufnr = vim.api.nvim_get_current_buf()
  local filter_db_path = M.get_db_path()

  -- 🟢 SELF-HEALING INTERCEPTION: Guarantee the database file is active before memory tracking maps populate
  ensure_default_db_exists(filter_db_path)

  -- Initialize memory state tracking layer from disk or incoming RAM state
  local caced_blocked = M.get_manual_blocked(filter_db_path)
  local active_file_blocked

  local check_file = vim.fs.normalize(OS.getBufFilename(bufnr))
  if check_file:find(_G.metadata.framework_root, 1, true) then
    active_file_blocked = caced_blocked.pckg_codes
  elseif check_file:find(OS.project_dir, 1, true) then
    active_file_blocked = caced_blocked.proj_codes
  else
    active_file_blocked = caced_blocked.proj_codes
  end


  M.session_discovered_codes = M.session_discovered_codes or {}

  -- Seed tracking lists with pckg keys currently active in memory
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
  -- Dynamic check: Prepend "Reset All" if any items are currently blocked
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
      --Clean memory table safely without destroying the reference table pointer
      for k in pairs(M.session_discovered_codes) do M.session_discovered_codes[k] = nil end

      vim.schedule(function()
        local misc_ok, misc = pcall(require, 'nvimpio.utils.misc')
        if (misc_ok and misc) then
          -- Let the dynamic boilerplate loop read pio_diag.M.blocked
          local boiler_ok, boiler = pcall(require, 'nvimpio.boilerplate')
          if boiler_ok and boiler and boiler.boilerplate_gen then
            pcall(boiler.boilerplate_gen, '.clangd', 'diagnostics clean_file_path_pipeline')
          end

          misc.writeFile(filter_db_path, misc.jsonFormat(caced_blocked), {})

          -- Invalidate or refresh cache here so the getter reloads the new state
          M.cached_db_mtime = 0 -- Invalidate mtime cache
        end

        -- 1. Tell all running clangd clients that configuration changed
        for _, client in ipairs(vim.lsp.get_clients({ name = 'clangd' })) do
          if client.rpc and client.rpc.notify then
            client.rpc.notify('workspace/didChangeConfiguration', { settings = {} })
          end
        end
        -- 2. Touch active buffers so clangd re-checks their diagnostics
        local bufs = vim.api.nvim_list_bufs()
        for _, b in ipairs(bufs) do
          if vim.api.nvim_buf_is_valid(b) and vim.api.nvim_buf_is_loaded(b) and vim.bo[b].buflisted then
            vim.api.nvim_buf_call(b, function()
              local old = vim.o.shortmess
              vim.o.shortmess = old .. 'F'
              vim.cmd('silent! checktime | silent! edit!')
              vim.o.shortmess = old
            end)
          end
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

    -- Format updated text string so Telescope's selection.display updates live in buffer
    if choice.id and choice.action ~= 'reset' then
      local is_blocked = active_file_blocked[choice.id] == true
      local mark = is_blocked and '[*]' or '[ ]'
      local status = is_blocked and 'Restore' or 'Suppress'
      choice.text = string.format('  %s %s Code: [%s]', mark, status, choice.id)
    end
    --------------------------------------------------------------------------------------------
    -- 2. DYNAMIC RESET ROW SYNC:
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
