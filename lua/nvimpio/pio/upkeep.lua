---@class platformio.utils.pio
local M = {}

local clangd = require('nvimpio.clangd.control')
local misc = require('nvimpio.utils.misc')
local term = require('nvimpio.utils.term')
local boilerplate = require('nvimpio.boilerplate')

local boilerplate_gen = boilerplate.boilerplate_gen

-- INFO:
-- =============================================================================
-- UNIVERSAL TOOLCHAIN DETECTION
-- =============================================================================
-- stylua: ignore
function M.get_sysroot_triplet(cc_compiler)
  local bin_path = vim.fn.fnamemodify(cc_compiler, ':h')

  -- Early exit if path is nil or not a directory
  if not bin_path or vim.fn.isdirectory(bin_path) == 0 then return nil end

  -- Normalize backslashes to forward slashes for cross-platform consistency
  bin_path = bin_path:gsub('\\', '/')
  local files = vim.fn.readdir(bin_path)
  local triplet = nil

  -- Loop through files to find the compiler and extract the triplet
  for _, name in ipairs(files) do
    -- Pattern: ^(.*) matches triplet, %- matches dash, g[c%+][c%+] matches gcc/g++
    local match = name:match('^(.*)%-g[c%+][c%+]')
    if match then triplet = misc.normalizePath(match) break
    end
  end

  -- Return nil if no compiler was found in the bin directory
  if not triplet then return nil end

  -- toolchain_root is the parent of the 'bin' folder
  local toolchain_root = misc.normalizePath(vim.fn.fnamemodify(bin_path, ':h'))
  -- sysroot folder is expected to have the same name as the triplet
  local sysroot = misc.normalizePath(toolchain_root .. '/' .. triplet)
  local query_driver = misc.normalizePath(bin_path .. '/' .. triplet .. '-*')

  -- Only return data if the sysroot folder actually exists on disk
  if vim.fn.isdirectory(sysroot) == 1 then
    _G.metadata.triplet = triplet
    _G.metadata.sysroot = sysroot
    _G.metadata.toolchain_root = toolchain_root
    _G.metadata.query_driver = query_driver
    return {
      triplet = triplet,
      sysroot = sysroot,
      toolchain_root = toolchain_root,
      query_driver = query_driver,
    }
  end
  return nil
end


--INFO:
-- Fast environment detection from platformio.ini file(no external calls)
-- stylua: ignore
--=============================================================================
-- Helper function to extract connected hardware ports using PlatformIO core
-- local function get_connected_ports()
--   if vim.fn.executable('pio') ~= 1 then
--     return {}
--   end
--
--   -- Spawn an explicit JSON hardware scan via the core engine
--   local ok, obj = pcall(function()
--     return vim.system({ 'pio', 'device', 'list', '--json' }):wait()
--   end)
--
--   if not ok or not obj or obj.code ~= 0 or not obj.stdout then
--     return {}
--   end
--
--   -- Parse output safely into data tables
--   local parse_ok, devices = pcall(vim.json.decode, obj.stdout)
--   if not parse_ok or type(devices) ~= 'table' then
--     return {}
--   end
--
--   local paths = {}
--   for _, dev in ipairs(devices) do
--     if dev.port then
--       paths[dev.port] = true
--     end
--   end
--   return paths
-- end


--=============================================================================
--INFO:get pio project metadata info
local fetch_metadata -- Forward declare the variable shell
local refreshBusy = false
-- stylua: ignore
fetch_metadata = function(callback, active_env, from, attempts)
  from = (type(from) == 'string' and from ~= '') and from or 'PIO: '

  attempts = tonumber(attempts) or 1
  local meta = _G.metadata

  -- Set up file paths
  local build_dir = misc.joinPath(vim.uv.cwd(), '.pio', 'build')
  local build_env_dir = misc.joinPath(build_dir, active_env)
  local checksum_file = misc.joinPath(build_dir, 'project.checksum')
  local idedata_file = misc.joinPath(build_env_dir, 'idedata.json')

  local function fire_callback(status)
    refreshBusy = false
    vim.schedule(function()
      if type(callback) == 'function' then callback(status) end
    end)
  end
  if not active_env or active_env == '' then fire_callback(false) return end

  --INFO:INTERNAL PROCESSOR: Applies parsed data to _G.metadata
  ---------------------------------------------------------
  local function apply_metadata(data)
    -- local function apply_metadata(data, checksum)
    if not data then
      return false
    end

    local norm = function(p)
      return misc.normalizePath(p) or ''
    end

    -- 1. Base Paths & Compilers
    meta.cc_path = norm(data.cc_path)
    meta.cxx_path = norm(data.cxx_path)
    meta.gdb_path = norm(data.gdb_path)
    pcall(M.get_sysroot_triplet, meta.cc_path)

    -- local activeEnv, metadata = M.get_active_env(from)
    -- if activeEnv and activeEnv ~= '' then
    --   metadata = metadata or {}
    --   _G.metadata.core_dir = metadata.core_dir
    --   _G.metadata.packages_dir = metadata.packages_dir
    --   _G.metadata.platforms_dir = metadata.platforms_dir
    --   _G.metadata.default_envs = metadata.default_envs
    --   _G.metadata.envs = metadata.envs
    --   _G.metadata.active_env = activeEnv
    -- end

    -- Secure the validation signature token right after creation succeeds
    local read_ok, fresh_checksum = misc.readFile(checksum_file)
    if read_ok and fresh_checksum ~= '' then meta.last_projectChecksum = fresh_checksum end

    return true
  end


  -- ----------------------------------------------------------------
  -- -- STEP 1: Cache Path (idedata.json exists )
  -- ----------------------------------------------------------------
  -- Complete Cache-Hit Evaluation Rule
  local idok, content = misc.readFile(idedata_file)
  if idok and content ~= '' then
    local cok, decoded = pcall(vim.json.decode, content)
    if cok and apply_metadata(decoded) then
      -- cli
      require('nvimpio.pio.cli').buildCompileDB(from, active_env, function(is_successful)
        if is_successful then
          -- OS.notify('Database is ready. Proceeding with analysis...')
          clangd.getUnknownArgs(from)
        else
          OS.notify('Skipping next steps due to compilation database failure.', 'error')
        end
      end)

      -- gui
      -- if attempts > 0 then
      --   local cb = function(status)
      --     M.handlePioDB(status, active_env, function(success)
      --       if success then do end end
      --     end)
      --   end
      --
      --   clangd.clangdIntall(function(clangdCmd)
      --     local check_file = vim.fs.find(function(name)
      --       return name:match('%.cpp$') or name:match('%.c$')
      --     end, { limit = 1, path = vim.uv.cwd() .. '/src' })[1]
      --     if not check_file then
      --       boilerplate_gen([[main.cpp]], vim.uv.cwd() .. '/src')
      --       boilerplate_gen([[main.hpp]], vim.uv.cwd() .. '/include')
      --       check_file = vim.uv.cwd() .. '/src/main.cpp'
      --     end
      --     local argscmd = string.format('%s --compile-commands-dir=. --check=%s --log=error', clangdCmd, check_file)
      --     local dbcmd = string.format('pio run -t compiledb -e %s', active_env)
      --     -- M.run_sequence({ cmnds = { idecmd, dbcmd }, cb = cb, from = string.format('%s refresh ' , from) })
      --     M.run_sequence({ cmnds = { dbcmd, argscmd }, cb = cb, from = string.format('%s refresh ', from) })
      --   end, 'clangd')
      -- end

      OS.notify(from .. 'Metadata synced from cache', 'info')
      require('nvimpio.pio.metadata').save_project_config(from)
      fire_callback(true)
      return true
    end
  end

  ------------------------------------------------------------------------------------
  -- STEP 2: Auto-Initialize (If file idedata.json missing)
  ------------------------------------------------------------------------------------
  -- buildIdedata()

  -- cli
  require('nvimpio.pio.cli').buildIdedata(from, active_env, function(is_successful)
    if is_successful then
      -- OS.notify(from .. 'Idedata is ready. Proceeding with analysis...')
        -- Execute recursive check loop to accurately verify and load newly compiled files
      if attempts > 0 then fetch_metadata(callback, active_env, from, attempts - 1)
      else fire_callback(false) end
    else
      OS.notify(from .. 'Skipping next steps due to compilation idedata failure.', 'error')
      fire_callback(false)
    end
  end)

  -- gui
  -- local cb = function(status)
  --   M.handleIdedata(status, active_env, function(success)
  --     if success then
  --       OS.notify(string.format('%s Initializing project metadata success for %s.', from, active_env), 'info')
  --
  --       -- Execute recursive check loop to accurately verify and load newly compiled files
  --       if attempts > 0 then fetch_metadata(callback, active_env, from, attempts - 1)
  --       else fire_callback(false) end
  --     else
  --       OS.notify(from .. 'Build Failed', 'error')
  --       fire_callback(false)
  --     end
  --   end)
  -- end
  --
  -- clangd.clangdIntall(function(clangdCmd)
  --   local check_file = vim.fs.find(function(name)
  --     return name:match('%.cpp$') or name:match('%.c$')
  --   end, { limit = 1, path = vim.uv.cwd() .. '/src' })[1]
  --   if not check_file then
  --     boilerplate_gen([[main.cpp]], vim.uv.cwd() .. '/src')
  --     boilerplate_gen([[main.hpp]], vim.uv.cwd() .. '/include')
  --     check_file = vim.uv.cwd() .. '/src/main.cpp'
  --   end
  --   local argscmd = string.format('%s --compile-commands-dir=. --check=%s --log=error', clangdCmd, check_file)
  --   local idecmd = string.format('pio run -t idedata -e %s -s', active_env)
  --   local dbcmd = string.format('pio run -t compiledb -e %s', active_env)
  --   -- M.run_sequence({ cmnds = { idecmd, dbcmd }, cb = cb, from = string.format('%s refresh ' , from) })
  --   M.run_sequence({ cmnds = { idecmd, dbcmd, argscmd }, cb = cb, from = string.format('%s refresh ', from) })
  -- end, 'clangd')
end


-------------------------------------------------------------------------------
--INFO:
-- stylua: ignore
function M.pio_refresh(callback, from)
  from = (type(from) == 'string' and from ~= '') and from or 'PIO: '

  if refreshBusy then
    OS.notify(string.format('%s refresh busy ...', from), 'info')
    if type(callback) == 'function' then vim.schedule(function() callback(false) end) end
    return
  end
  refreshBusy = true

  -- local active_env = vim.tbl_get(_G, "metadata", "active_env")
  local active_env = _G.metadata and _G.metadata.active_env

  if active_env and active_env ~= '' then
    -- OS.notify(msg .. 'active_env= ' .. active_env, 'info')
    fetch_metadata(callback, active_env, from, 1)
  else
    OS.notify(from ..' No active env', 'error')
    refreshBusy = false
    if type(callback) == 'function' then vim.schedule(function() callback(false) end) end
  end
end

-------------------------------------------------------------------------------
-- INFO:
-- Fix compile_commands.json file with absoulute paths
-- stylua: ignore
function M.compile_commandsFix() --M.dbPathsFix()
  local filename = vim.fs.joinpath(vim.uv.cwd(), 'compile_commands.json')
  local content = vim.fn.readfile(filename)
  if #content == 0 then return end

  local start_time = vim.loop.hrtime()
  local ok, data = pcall(vim.json.decode, table.concat(content, '\n'))
  if not ok or type(data) ~= 'table' then return end

  -- 1. Build Path Map (Scan toolchain)
  local path_map = {}
  local pio_binaries = _G.metadata.query_driver or '/bin/*'
  -- local pio_binaries = (_G.metadata.toolchain_root or "") .. '/bin/*'
  for _, full_path in ipairs(vim.fn.glob(pio_binaries, false, true)) do
    local name = full_path:match('([^/\\\\]+)$'):gsub('%.exe$', '')
    path_map[name] = full_path
  end

  -- 2. Update Entries
  local modified = false
  local prntFlags = true
  for _, entry in ipairs(data) do
    -- Standard normalization
    if entry.directory then entry.directory = misc.normalizePath(entry.directory) end
    if entry.file then entry.file = misc.normalizePath(entry.file) end
    if entry.arguments then entry.arguments = misc.normalizeFlags(entry.arguments) end
    if entry.output then entry.output = misc.normalizePath(entry.output) end

    if entry.command then
      -- Extract compiler and everything after it
      local compiler, args = entry.command:match("^%s*(%S+)(.*)")
      if compiler then
        local is_absolute = compiler:sub(1, 1) == '/' or compiler:match('^%a:')

        if not is_absolute then
          local short_name = compiler:match('([^/\\\\]+)$'):gsub('%.exe$', '')

          if path_map[short_name] then
            -- Use normalizePath on the new path
            local full_compiler_path = misc.normalizePath(path_map[short_name])

            -- Quote the path if it contains spaces
            if full_compiler_path:find(" ") then
              full_compiler_path = '"' .. full_compiler_path .. '"'
            end
            if prntFlags then
              -- print(string.format('ful_compiler_path = %s flags=%s', full_compiler_path, args))
              prntFlags = false
            end
            entry.command = full_compiler_path .. args
            modified = true
          end
        end
      end
    end
  end
  -- -- 3. Save with Formatting
  if modified then
    local jok, formatted = pcall(misc.jsonFormat, data)
    -- local jok, formatted = pcall(M.pretty_print, data)
    if not jok then
      OS.notify('Formatting failed: ' .. formatted, 'error')
      return
    end

    local wk, err = misc.writeFile(filename, formatted, { overwrite = true, mkdir = true })
    if not wk then OS.notify(err, 'error') end

    local end_time = vim.loop.hrtime()
    local duration = (end_time - start_time) / 1e6
    OS.notify(string.format('compiledb: paths fixed in %.2fms', duration), "info")
    -- clangd.restart()
  end
  OS.notify("no need to fixPaths")
  _G.metadata.isBusy = false
end

-- INFO:
--configuration for running sequential commands on ToggleTerminal
-- stylua: ignore
-- Initialize
-- =============================================================================
-- =============================================================================
-- =============================================================================
-- =============================================================================
-- local current_token -- = tostring(math.random(10000, 99999))
-- local current_id = -1 -- Holds 0 for DONE, or 1-9 for PASS
--
-- local session_counter = 1 -- Our high-performance integer counter
-- local pio_buffer = '' -- Initialize to prevent nil concatenation crashes
-- local callBack = nil -- Your execution hook function pointer
-- local fromMsg = ''
-- M.queue = {}
-- term.stdout_callback = M.stdoutcallback
-- local trm
-- local nvimpio = require('nvimpio')
--
-- -- Ensure this table is declared in your module scope or function closure
-- local clangd_extracted_args = {}
-- -- Set this to true when launching the clangd terminal, false when done
-- local clangd_check_active = false
-- M.token_echo_passed = false
--
-- -- INFO: ToggleTerminal commands stdout filter
-- -- stylua: ignore
-- -- =============================================================================
-- function M.stdoutcallback(_, _, data, _)
--   if not data or #data == 0 then
--     return
--   end
--
--   if #data > 1 then
--     -- local content = pio_buffer .. table.concat(data, '', 1, #data - 1)
--     local content = pio_buffer .. table.concat(data, '', 1, #data)
--     pio_buffer = data[#data] -- Save the new partial line
--
--     ---------------------------------------------------------------------------
--     -- 🛠️ INJECTED CLANGD FLAG EXTRACTION LOGIC
--     ---------------------------------------------------------------------------
--     -- If your clangd check sequence is running, scrape the incoming buffer data
--     -- if clangd_check_active then
--     --   -- 1. Exclude lines containing .clang-format configurations to prevent false hits
--     --   if not string.find(content, "%.clang%-format") then
--     --     -- 2. Extract your targeted unknown compiler arguments
--     --     for arg in string.gmatch(content, "unknown argument[:%s]+'([^']+)'") do
--     --       table.insert(clangd_extracted_args, string.format('"%s"', arg:gsub('[;%.]$', '')))
--     --     end
--     --   end
--     --   print('check')
--     --   print(vim.inspect(clangd_extracted_args))
--     -- end
--
--
--
--
--     -- Add this state variable to your module scope (at the top of your file)
--
--     -- Inside your callback function:
--     if clangd_check_active then
--       -- 1. Create your two distinct patterns
--       local  start_pattern_done = '_CMMNDS_' .. current_token .. '":"DONE'
--
--       -- 2. Check if the initial command echo has just streamed past
--
--       local _, start_idx = string.find(content, start_pattern_done, 1, true)
--
--
--       local target_text = content
--       if start_idx then
--         M.token_echo_passed = true
--         target_text = string.sub(content, start_idx + 1)
--       end
--
--       -- 3. Check if the final output result has arrived (signals the absolute end)
--
--       -- 4. THE GATED LOOP: Only extract AFTER the echo has passed, but BEFORE the final done token closes it
--       if M.token_echo_passed and not string.find(target_text, "%.clang%-format") then
-- clangd_extracted_args = {}
--         print(vim.inspect(clangd_extracted_args))
--         for arg in string.gmatch(target_text, "unknown argument[:%s]+'([^']+)'") do
--           table.insert(clangd_extracted_args, string.format('"%s"', arg:gsub('[;%.]$', '')))
--         end
--         print(vim.inspect(clangd_extracted_args))
--       end
--     end
--
--     ---------------------------------------------------------------------------
--
--
--     local pass_target = 'PASS' .. current_id
--
--     local pass_pattern = '_CMMNDS_' .. current_token .. ':' .. pass_target
--     local fail_pattern = '_CMMNDS_' .. current_token .. ':FAIL'
--     local done_pattern = '_CMMNDS_' .. current_token .. ':DONE'
--
--     local has_pass = content:find(pass_pattern) ~= nil
--     local has_done = content:find(done_pattern) ~= nil
--     local has_fail = content:find(fail_pattern) ~= nil
--
--     if has_pass or has_fail or has_done then
--       local active_cb = callBack
--
--
--       local final_status = 'FAIL'
--       if has_fail then
--         final_status = 'FAIL'
--         callBack = nil
--         M.queue = {}
--         pio_buffer = ''
--         -- M.queue = {} -- Instantly wipe remaining queue items to halt the pipeline
--       elseif has_done then
--         final_status = 'DONE'
--         callBack = nil
--         pio_buffer = ''
--         M.queue = {}
--       elseif has_pass then
--         final_status = pass_target
--       end
--
--       if final_status and active_cb then
--         vim.schedule(function() active_cb(final_status) end)
--       end
--
--       return -- Break out immediately upon executing the callback
--     end
--
--   else
--     -- Only one element (no newline yet;) means the line isn't finished yet
--     pio_buffer = pio_buffer .. data[1]
--   end
--
--   -- 3. Safety Trim (Prevents memory leaks if no newline ever comes)
--   if #pio_buffer > 5000 then
--     pio_buffer = pio_buffer:sub(-2500)
--   end
-- end
-- -- =============================================================================
-- -- =============================================================================
-- local current_token -- = tostring(math.random(10000, 99999))
-- local current_id = -1 -- Holds 0 for DONE, or 1-9 for PASS
--
-- local session_counter = 1 -- Our high-performance integer counter
-- local pio_buffer = '' -- Initialize to prevent nil concatenation crashes
-- local callBack = nil -- Your execution hook function pointer
-- local fromMsg = ''
-- M.queue = {}
-- term.stdout_callback = M.stdoutcallback
-- local trm
--
-- local clangd_extracted_args = {}
-- local clangd_check_active = false
--
-- -- Safe persistent string sandbox for the run history
-- M.current_run_raw_text = ''
--
-- function M.stdoutcallback(_, _, data, _)
--   if not data or #data == 0 then
--     return
--   end
--
--   if #data > 1 then
--     local content = pio_buffer .. table.concat(data, '', 1, #data)
--     pio_buffer = data[#data] -- Save the new partial line
--
--     ---------------------------------------------------------------------------
--     -- 1. CONTINUOUSLY ACCUMULATE FRESH MULTI-LINE CHUNKS SAFELY
--     ---------------------------------------------------------------------------
--     if clangd_check_active then
--       M.current_run_raw_text = M.current_run_raw_text .. content
--     end
--
--     local pass_target = 'PASS' .. current_id
--     local pass_pattern = '_CMMNDS_' .. current_token .. ':' .. pass_target
--     local fail_pattern = '_CMMNDS_' .. current_token .. ':FAIL'
--     local done_pattern = '_CMMNDS_' .. current_token .. ':DONE'
--
--     local has_pass = content:find(pass_pattern) ~= nil
--     local has_done = content:find(done_pattern) ~= nil
--     local has_fail = content:find(fail_pattern) ~= nil
--
--     if has_pass or has_fail or has_done then
--       local active_cb = callBack
--       local final_status = 'FAIL'
--
--       if has_fail or has_done then
--         final_status = has_fail and 'FAIL' or 'DONE'
--         callBack = nil
--         M.queue = {}
--         pio_buffer = ''
--
--         -----------------------------------------------------------------------
--         -- 2. PARSE THE ISOLATED TEXT SANDBOX ON COMPLETION
--         -----------------------------------------------------------------------
--         if clangd_check_active then
--           clangd_extracted_args = {}
--
--           -- Look for boundaries in our private, un-truncated string sandbox
--           local start_pattern = '_CMMNDS_' .. current_token .. '":"' .. final_status
--           local _, start_idx = string.find(M.current_run_raw_text, start_pattern, 1, true)
--
--           if not start_idx then
--             local fallback_echo = '_CMMNDS_' .. current_token .. '":"DONE'
--             _, start_idx = string.find(M.current_run_raw_text, fallback_echo, 1, true)
--           end
--
--           local end_pattern = '_CMMNDS_' .. current_token .. ':' .. final_status
--           local end_idx = string.find(M.current_run_raw_text, end_pattern, 1, true)
--
--           -- Slice out the exact text segment between the boundary markers
--           if start_idx and end_idx and end_idx > start_idx then
--             local fresh_run_logs = string.sub(M.current_run_raw_text, start_idx + 1, end_idx - 1)
--
--             if not string.find(fresh_run_logs, '%.clang%-format') then
--               local seen = {}
--               for arg in string.gmatch(fresh_run_logs, "unknown argument[:%s]+'([^']+)'") do
--                 local clean_flag = string.format('"%s"', arg:gsub('[;%.]$', ''))
--                 if not seen[clean_flag] then
--                   seen[clean_flag] = true
--                   table.insert(clangd_extracted_args, clean_flag)
--                 end
--               end
--             end
--           end
--
--           -- Wipe the isolated task tracking states completely
--           M.current_run_raw_text = ''
--           clangd_check_active = false
--         end
--         -----------------------------------------------------------------------
--       elseif has_pass then
--         final_status = pass_target
--       end
--
--       if final_status and active_cb then
--         vim.schedule(function()
--           active_cb(final_status)
--         end)
--       end
--
--       return -- Break out immediately upon executing the callback
--     end
--   else
--     ---------------------------------------------------------------------------
--     -- TARGET DATA[1] STRINGS TO PREVENT TABLE CONCATENATION CRASHES
--     ---------------------------------------------------------------------------
--     -- Only one element means the line isn't finished yet
--     pio_buffer = pio_buffer .. data[1]
--
--     -- Sync single lines into our isolated sandbox if the check loop is active
--     if clangd_check_active then
--       M.current_run_raw_text = M.current_run_raw_text .. data[1]
--     end
--   end
--
--   -- Your safety guard trims pio_buffer normally, but M.current_run_raw_text is unaffected!
--   if #pio_buffer > 5000 then
--     pio_buffer = pio_buffer:sub(-2500)
--   end
-- end
-- -- =============================================================================
-- ⏳ 1. CRITICAL MODULE STATE TRACKER FOR TIMEOUTS
M.safety_timer = nil
--- Dynamic Timeout Reset Routine
local function stop_safety_timer()
  if M.safety_timer then
    M.safety_timer:stop()
    M.safety_timer:close()
    M.safety_timer = nil
  end
end
-- -- =============================================================================
local current_token -- = tostring(math.random(10000, 99999))
local session_counter = 1 -- Our high-performance integer counter
local current_id = -1

local callBack = nil
M.queue = {}
term.stdout_callback = M.stdoutcallback

local clangd_extracted_args = {}
local clangd_check_active = false

local fromMsg = ''
local trm
local pio_buffer = ''
local content = ''

function M.stdoutcallback(_, _, data, _)
  if not data or #data == 0 then
    return
  end

  if #data > 1 then
    content = content .. pio_buffer .. table.concat(data, '', 1, #data)
    pio_buffer = data[#data]
  else
    -- Safe single item array evaluation
    -- pio_buffer = pio_buffer .. data[1]
    content = content .. pio_buffer .. data[1]
    pio_buffer = data[1]
  end

  local pass_target = 'PASS' .. current_id
  local has_pass = content:find('_CMMNDS_' .. current_token .. ':' .. pass_target) ~= nil
  local has_done = content:find('_CMMNDS_' .. current_token .. ':DONE') ~= nil
  local has_fail = content:find('_CMMNDS_' .. current_token .. ':FAIL') ~= nil

  if has_pass or has_fail or has_done then
    local active_cb = callBack
    local final_status = has_fail and 'FAIL' or (has_done and 'DONE' or pass_target)

    if has_fail or has_done then
      -- ✅ SUCCESSFUL RUN DETECTED: Kill the countdown timer immediately!
      -- stop_safety_timer()
      callBack = nil
      M.queue = {}

      -----------------------------------------------------------------------
      -- 🌟 ONE-TIME EXTRACTOR ON TERMINATION (HISTORY COMPLETELY INTACT!)
      -----------------------------------------------------------------------
      if clangd_check_active then
        clangd_extracted_args = {}

        -- 1. Find boundaries on the raw, un-truncated content string
        local start_pattern = '_CMMNDS_' .. current_token .. '":"' .. final_status
        local _, start_idx = string.find(content, start_pattern, 1, true)

        if not start_idx then
          local fallback_echo = '_CMMNDS_' .. current_token .. '":"DONE'
          _, start_idx = string.find(content, fallback_echo, 1, true)
        end

        local end_pattern = '_CMMNDS_' .. current_token .. ':' .. final_status
        local end_idx = string.find(content, end_pattern, 1, true)

        -- 2. Slice and parse the exact fresh run text block
        if start_idx and end_idx and end_idx > start_idx then
          local fresh_run_logs = string.sub(content, start_idx + 1, end_idx - 1)

          if not string.find(fresh_run_logs, '%.clang%-format') then
            local seen = {}
            for arg in string.gmatch(fresh_run_logs, "unknown argument[:%s]+'([^']+)'") do
              local clean_flag = string.format('"%s"', arg:gsub('[;%.]$', ''))
              if not seen[clean_flag] then
                seen[clean_flag] = true
                table.insert(clangd_extracted_args, clean_flag)
              end
            end
          end
        else
          return
        end

        clangd_check_active = false
      end

      -- 🏁 3. FLUSH THE BUFFER CLEAN HERE AT THE END OF THE COMMAND RUN
      pio_buffer = ''
      content = ''
      -----------------------------------------------------------------------
    end

    if final_status and active_cb then
      vim.schedule(function()
        active_cb(final_status)
      end)
    end

    return
  end
end
-- =============================================================================

-- =============================================================================
local function pop(queue)
  local current_step = table.remove(queue, 1)
  local base_cmd = current_step[1]
  current_id = current_step[2]
  current_token = current_step[3]

  -- Formulate the target words dynamically
  local target_word = current_id == 0 and 'DONE' or ('PASS' .. current_id)

  -- Create your target echo layouts
  local pass_echo = string.format('_CMMNDS_%s":"%s', current_token, target_word)
  local fail_echo = string.format('_CMMNDS_%s":"FAIL', current_token)

  -- Format native platform operators properly to escape quotes securely
  local win_str = string.format('  && echo %s || echo %s', pass_echo, fail_echo)
  local nix_str = string.format('  && echo "%s" || echo "%s"', pass_echo, fail_echo)
  local full_shell_cmd = base_cmd .. (OS.is_win and win_str or nix_str)
  return full_shell_cmd
end

-- INFO: commands sequencer
-- stylua: ignore
-- =============================================================================
local nvimpio = require('nvimpio')
M.run_sequence = function(tasks)
  M.queue = {}
  local commands = tasks.cmnds
  fromMsg = tasks.from
  callBack = tasks.cb -- 1. Save the callback in a local variable

  local token = string.format('%04d', session_counter)

  session_counter = session_counter + 1
  if session_counter > 9999 then
    session_counter = 1
  end

  local total = #commands
  for i, cmd in ipairs(commands) do
    local step_id = (i == total) and 0 or i
    table.insert(M.queue, { cmd, step_id, token })
  end

  if not nvimpio.is_active then
    require('nvimpio.pio.metadata')
  end

  if callBack then
    vim.schedule(function()
      content = ''
      pio_buffer = ''
      clangd_extracted_args = {} -- Clear the collected flags table
      clangd_check_active = false -- Arm the parsing loop tracker

      -- stop_safety_timer()
      -- local max_execution_time_ms = 20000
      -- local uv = vim.uv or vim.loop
      --
      -- M.safety_timer = uv.new_timer()
      -- M.safety_timer:start(
      --   max_execution_time_ms,
      --   0,
      --   vim.schedule_wrap(function()
      --     if clangd_check_active or #content > 0 then
      --       stop_safety_timer()
      --       pio_buffer = ''
      --       content = ''
      --       clangd_check_active = false
      --       M.queue = {} -- Break the queue sequence to prevent consecutive glitches
      --
      --       local fallback_cb = callBack
      --       callBack = nil
      --       OS.notify(fromMsg .. ' ⚠️ Clangd pipeline stalled. Hard buffer reset triggered!', 'error')
      --       if fallback_cb and type(fallback_cb) == 'function' then
      --         fallback_cb('FAIL')
      --       end
      --     end
      --   end)
      -- )

      term.stdout_callback = M.stdoutcallback
      callBack('INIT')
    end)
  end
end

------------------------------------------------------
-- Handle after pioinit execution
-- =============================================================================
-- stylua: ignore
function M.cleanSequencer()
  _G.metadata.isBusy = false
  term.stdout_callback = nil -- Careful: make sure this doesn't break other terms
  -- if trm then trm:close() end
end

-- stylua: ignore
function M.handlePioinitDb(result, board, on_done)
  local active_env
  if result == 'INIT' then
    -- OS.notify(string.format("active_env=%s board=%s", active_env, board), 'info')
    if #M.queue > 0 then
      _G.metadata.isBusy = true
      -- boilerplate.core_dir = _G.metadata.core_dir
      boilerplate.core_dir = require('nvimpio').config.pio_storage_dir
      boilerplate_gen([[platformio.ini]], vim.g.platformioRootDir)

      trm = term.ToggleTerminal(pop(M.queue), 'float')
      -- active_env = M.get_active__env('PIO init+db: ')
      if trm and on_done and type(on_done) == "function" then
        vim.keymap.set('n', '<leader>\\t', function() trm:open() end, { desc = 'open Term' })
      end
    end
  elseif result == 'PASS1' then -- current_id
    OS.notify('PIO init+db:  pass ' .. current_id, "info")
      local meta = require('nvimpio.pio.metadata')
      active_env, _ = meta.get_active_env('PIO init+db: ')
    -- if not active_env or (active_env == board) then
      -- boilerplate_gen([[main.cpp]], vim.g.platformioRootDir .. '/src')
      -- boilerplate_gen([[main.hpp]], vim.g.platformioRootDir .. '/include')
      boilerplate_gen([[main.cpp]], vim.uv.cwd() .. '/src')
      boilerplate_gen([[main.hpp]], vim.uv.cwd() .. '/include')
      if #M.queue > 0 then trm:send(pop(M.queue), false) end
    -- else
    --   if on_done and type(on_done) == "function" then on_done(false) end
    --   M.cleanSequencer()
    -- end
  -- elseif result == 'PASS2' then
  elseif result == 'DONE' then -- result of the last command
    OS.notify('PIO init+db: Done', "info")
    if not active_env or (active_env ~= board) then
      OS.notify(string.format('PIO init+db active_env: %s', board), 'info')
      _G.metadata.active_env = board
    end
    M.pio_refresh(function(success)
      if on_done and type(on_done) == "function" then on_done(true) end
      if success then boilerplate.core_dir = _G.metadata.core_dir end
    end, 'PIO init+db: ')
    if trm then trm:close() end
    M.cleanSequencer()
  elseif result == 'FAIL' then
    if on_done and type(on_done) == "function" then on_done(false) end
    M.cleanSequencer()
  end
end


-- stylua: ignore
function M.handlePioinit(result, board, on_done)
  if result == 'INIT' then
    -- OS.notify(string.format("active_env=%s board=%s", active_env, board), 'info')
    if #M.queue > 0 then
      _G.metadata.isBusy = true
      boilerplate.core_dir = require('nvimpio').config.pio_storage_dir
      boilerplate_gen([[platformio.ini]], vim.g.platformioRootDir)

      trm = term.ToggleTerminal(pop(M.queue), 'float')
      if trm and on_done and type(on_done) == "function" then
        vim.keymap.set('n', '<leader>\\t', function() trm:open() end, { desc = 'open Term' })
      end
    end
  -- elseif result == 'PASS1' then
  elseif result == 'DONE' then -- result of the last command
    OS.notify('PIO: project init Done', "info")
    boilerplate_gen([[main.cpp]], vim.uv.cwd() .. '/src')
    boilerplate_gen([[main.hpp]], vim.uv.cwd() .. '/include')
    if trm then trm:close() end
    if on_done and type(on_done) == "function" then on_done(true) end
    _G.metadata.active_env = board
    M.cleanSequencer()
  elseif result == 'FAIL' then
    if on_done and type(on_done) == "function" then on_done(false) end
    M.cleanSequencer()
  end
end


------------------------------------------------------
-- Handle after piolib execution
-- =============================================================================
-- stylua: ignore
function M.handlePioInstall(result, on_done)
  if result == 'INIT' then
    if #M.queue > 0 then
      _G.metadata.isBusy = true
      trm = term.ToggleTerminal(pop(M.queue), 'float')
      if trm and on_done and type(on_done) == "function" then
        vim.keymap.set('n', '<leader>\\t', function() trm:open() end, { desc = 'open Term' })
      end
    end
  elseif result == 'PASS' .. current_id then
      OS.notify('PIO install:  pass ' .. current_id, "info")
      if #M.queue > 0 then trm:send(pop(M.queue), false) end
  -- elseif result == 'PASS2' then
  elseif result == 'DONE' then -- result of the only and the last command
    OS.notify('PIO install: Done', "info")

    -- 1. Always remove the script
    local script_path = vim.fs.joinpath(OS.cache_dir, 'get-platformio.py')
    os.remove(script_path)
    -- 2. Find and remove random temp folders like .piocore-installer-xxxx
    local temp_patterns = { ".piocore-installer-*", "platformio-core-installer-*" }
    for _, pattern in ipairs(temp_patterns) do
      local matches = vim.fn.glob(pattern, true, true)
      for _, path in ipairs(matches) do
        if vim.fn.isdirectory(path) == 1 then vim.fn.delete(path, "rf") end
      end
    end

    if on_done and type(on_done) == "function" then on_done(true) end
    -- if trm then trm:close() end
    M.cleanSequencer()
    trm:shutdown()
  elseif result == 'FAIL' then
     OS.notify('Installation failed! Check logs and press :q to close.', 'error')
    if on_done and type(on_done) == "function" then on_done(false) end
    M.cleanSequencer()
  end
end

------------------------------------------------------
-- Handle create clang-format
-- =============================================================================
-- stylua: ignore
function M.clangFormat(result)
  if result == 'INIT' then
    if #M.queue > 0 then
      _G.metadata.isBusy = true
      trm = term.ToggleTerminal(pop(M.queue), 'float')
    end
  elseif result == 'DONE' then -- result of the only and the last command
    OS.notify('Clang formatter: Done', "info")
    if trm then trm:close() end
    M.cleanSequencer()
  elseif result == 'FAIL' then
    M.cleanSequencer()
  end
end

------------------------------------------------------
-- Handle command
-- =============================================================================
-- stylua: ignore
function M.handleIdedata0(result, active_env, on_done)
  if result == 'INIT' then
    if #M.queue > 0 then
      _G.metadata.isBusy = true
      trm = term.ToggleTerminal(pop(M.queue), 'float')
    end
  elseif result == 'PASS' .. current_id then
    OS.notify(string.format('%sidedata  pass%s', fromMsg, current_id), "info")
    if #M.queue > 0 then trm:send(pop(M.queue), false) end
  -- elseif result == 'PASS2' then
  elseif result == 'DONE' then -- result of the only and the last command
    OS.notify(string.format('%s compiledb success for %s.', fromMsg, active_env), "info")
    vim.defer_fn(function()
      require('nvimpio.clangd.control').getUnknownArgs(fromMsg)
    end, 50) -- 50ms delay, adjust as needed
    if on_done and type(on_done) == 'function' then on_done(true) end
    -- vim.schedule(function()
    --   require('nvimpio.clangd.control').getUnknownArgs(fromMsg)
    --   if on_done and type(on_done) == 'function' then on_done(true) end
    -- end)
    if trm then trm:close() end
    M.cleanSequencer()
  elseif result == 'FAIL' then
    M.cleanSequencer()
  end
end

-- =============================================================================
local pass1 = false
-- stylua: ignore
function M.handlePioDB(result, active_env, on_done)
  if result == 'INIT' then
    if #M.queue > 0 then
      pass1 = false
      _G.metadata.isBusy = true
      trm = term.ToggleTerminal(pop(M.queue), 'float')
    end
  elseif result == 'PASS1' then -- .. current_id then                         -- compiledb PASS1
    OS.notify(string.format('%s compiledb success for %s.', fromMsg, active_env), "info")
    pass1  = true

    boilerplate.args = {}
    boilerplate_gen('.clangd', vim.g.platformioRootDir) -- read user '.clangd'

    clangd_extracted_args = {}       -- Clear the collected flags table
    clangd_check_active = true
    -- vim.defer_fn(function()
      -- require('nvimpio.clangd.control').getUnknownArgs(fromMsg)
      if #M.queue > 0 then trm:send(pop(M.queue), false) end
    -- end, 50) -- 50ms delay, adjust as needed
  elseif result == 'DONE' then -- result of the only and the last command
    if on_done and type(on_done) == 'function' then
      on_done(true)
      if pass1 then
        vim.defer_fn(function()
          boilerplate.args = clangd_extracted_args
          boilerplate_gen('.clangd', vim.g.platformioRootDir)
          OS.notify(string.format('%s Clangd ✅Extracted %s flags', fromMsg, #clangd_extracted_args), 'info')
          clangd.restart()
        end, 500) -- 50ms delay, adjust as needed
      end
    end
    if trm then trm:close() end
    M.cleanSequencer()
  elseif result == 'FAIL' then
    if on_done and type(on_done) == 'function' then
      if pass1 then
        vim.defer_fn(function()
          boilerplate.args = clangd_extracted_args
          boilerplate_gen('.clangd', vim.g.platformioRootDir)
          OS.notify(string.format('%s Clangd ✅Extracted %s flags', fromMsg, #clangd_extracted_args), 'info')
          clangd.restart()
        end, 500) -- 50ms delay, adjust as needed
        on_done(true)
      else on_done(false) end
    end
    if trm then trm:close() end
    M.cleanSequencer()
  end
end

------------------------------------------------------
-- Handle command
-- =============================================================================
local pass2 = false
-- stylua: ignore
function M.handleIdedata(result, active_env, on_done)
  if result == 'INIT' then
    if #M.queue > 0 then
      pass2 = false
      _G.metadata.isBusy = true
      trm = term.ToggleTerminal(pop(M.queue), 'float')
    end
  elseif result == 'PASS1' then -- .. current_id then                         -- idedata PASS1
    OS.notify(string.format('%sidedata  for %s', fromMsg, active_env), "info")
    if #M.queue > 0 then trm:send(pop(M.queue), false) end
  elseif result == 'PASS2' then -- .. current_id then                         -- compiledb PASS1
    OS.notify(string.format('%s compiledb success for %s.', fromMsg, active_env), "info")
    pass2  = true

    boilerplate.args = {}
    boilerplate_gen('.clangd', vim.g.platformioRootDir) -- read user '.clangd'

    clangd_extracted_args = {}       -- Clear the collected flags table
    clangd_check_active = true
    -- vim.defer_fn(function()
      -- require('nvimpio.clangd.control').getUnknownArgs(fromMsg)
      if #M.queue > 0 then trm:send(pop(M.queue), false) end
    -- end, 50) -- 50ms delay, adjust as needed
  elseif result == 'DONE' then                                       -- unknown args DONE
    if on_done and type(on_done) == 'function' then
      on_done(true)
      if pass2 then
        vim.defer_fn(function()
          boilerplate.args = clangd_extracted_args
          boilerplate_gen('.clangd', vim.g.platformioRootDir)
          OS.notify(string.format('%s Clangd ✅Extracted %s flags', fromMsg, #clangd_extracted_args), 'info')
          clangd.restart()
        end, 500) -- 50ms delay, adjust as needed
      end
    end
    if trm then trm:close() end
    M.cleanSequencer()
  elseif result == 'FAIL' then                                       -- FAIL
    if on_done and type(on_done) == 'function' then
      if pass2 then
        vim.defer_fn(function()
          boilerplate.args = clangd_extracted_args
          boilerplate_gen('.clangd', vim.g.platformioRootDir)
          OS.notify(string.format('%s Clangd ✅Extracted %s flags', fromMsg, #clangd_extracted_args), 'info')
          clangd.restart()
        end, 500) -- 50ms delay, adjust as needed
        on_done(true)
      else on_done(false) end
    end
    if trm then trm:close() end
    M.cleanSequencer()
  end
end

------------------------------------------------------
-- Handle command
-- =============================================================================
-- stylua: ignore
function M.handleClangdCheck(result, on_done)
  if result == 'INIT' then
    if #M.queue > 0 then
      clangd_extracted_args = {}       -- Clear the collected flags table
      clangd_check_active = true     -- Arm the parsing loop tracker
      _G.metadata.isBusy = true
      trm = term.ToggleTerminal(pop(M.queue), 'float')
    end
  elseif result == 'DONE' then -- result of the only and the last command
    OS.notify(string.format('%sclangd check  done', fromMsg), 'info')
    local final_args = clangd_extracted_args -- Hold the pointer reference for the scheduled function
    vim.schedule(function()
      if on_done and type(on_done) == 'function' then on_done(true, final_args) end
    end)
    if trm then trm:close() end
    M.cleanSequencer()
  elseif result == 'FAIL' then
    OS.notify(string.format('%s clangd check  fail', fromMsg), 'info')
    local final_args = clangd_extracted_args -- Hold the pointer reference for the scheduled function
    vim.schedule(function()
      if on_done and type(on_done) == 'function' then on_done(true, final_args) end
    end)
    if trm then trm:close() end
    M.cleanSequencer()
  end
end

------------------------------------------------------
-- Handle after piolib execution
-- =============================================================================
-- stylua: ignore
function M.handlePiolib(result)
  if result == 'INIT' then
    if #M.queue > 0 then
      _G.metadata.isBusy = true
      trm = term.ToggleTerminal(pop(M.queue), 'float')
      -- if trm then trm:open() end
    end
  elseif result == 'PASS' then
    OS.notify('PIO lib+db:  pass ' .. current_id, "info")
    -- if #M.queue > 0 then trm:send(table.remove(M.queue, 1), false) end
    if #M.queue > 0 then trm = term.ToggleTerminal(table.remove(M.queue, 1), 'float') end
  elseif result == 'DONE' then -- result of the last command
    vim.schedule(function()
      OS.notify('PIO lib+db: Done', "info")
      M.pio_refresh(function(success)
        if success then clangd.getUnknownArgs('PIO lib+db: ') end
      end, 'PIO lib+db: ')
    end)
    if trm then trm:close() end
    M.cleanSequencer()
  elseif result == 'FAIL' then
    M.cleanSequencer()
  end
end
return M
