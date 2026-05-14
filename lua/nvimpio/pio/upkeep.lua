---@class platformio.utils.pio
local M = {}

local clangd = require('nvimpio.clangd.control')
local misc = require('nvimpio.utils.misc')

local boilerplate = require('nvimpio.boilerplate')
local boilerplate_gen = boilerplate.boilerplate_gen

local term = require('nvimpio.utils.term')

local core_dir = os.getenv('PLATFORMIO_CORE_DIR')
-- stylua: ignore
if not core_dir then core_dir = vim.fs.joinpath(OS.home, '.platformio') end

--INFO: get PIO binary folder
-- stylua: ignore
------------------------------------------------------
function M.get_pio_bin_dir()
  -- 3. Use 'Scripts' for Windows and 'bin' for Unix-like systems
  local bin_subfolder = OS.is_win and 'penv/Scripts' or 'penv/bin'

  -- Normalize the path to handle mix of '/' and '\' on Windows
  local full_path = vim.fs.joinpath(core_dir, bin_subfolder)
  return full_path
end

--INFO: Verify PIO version
-- stylua: ignore
------------------------------------------------------
function M.verify_version()
  vim.system({ 'pio', '--version' }, { text = true }, function(obj)
    vim.schedule(function()
      if obj.code == 0 then OS.notify('PlatformIO Version: ' .. vim.trim(obj.stdout), 'info')
      else OS.notify('❌ PlatformIO execution error: ' .. (obj.stderr or 'Unknown error'), 'error') end
    end)
  end)
end





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

  -- OS.notify('triplet= ' .. triplet, "info")
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
-- stylua: ignore
-------------------------------------------------------------------------------
-- function M.updateDefaultEnv()
--   local path = vim.fn.getcwd() .. "/platformio.ini"
--   local active_env = _G.metadata.active_env
--   if not active_env or active_env == "" then return end
--
--   _G.metadata.isBusy = true
--   local ok, content = misc.readFile(path)
--   if not ok or not content then
--     _G.metadata.isBusy = false
--     return
--   end
--
--   local new_lines = {}
--   local updated = false
--   local in_platformio = false
--
--   -- Process text and newline separately to maintain file integrity
--   for text, newline in content:gmatch("([^\r\n]*)([\r\n]+)") do
--     local is_header = text:match("^%s*%[([^%]]+)%]")
--
--     if is_header == "platformio" then
--       in_platformio = true
--     elseif is_header then
--       -- If leaving [platformio] without updating, insert it now
--       if in_platformio and not updated then
--         table.insert(new_lines, "default_envs = " .. active_env .. newline)
--         updated = true
--       end
--       in_platformio = false
--     end
--
--     if in_platformio and text:match("^%s*default_envs%s*=") then
--       table.insert(new_lines, "default_envs = " .. active_env .. newline)
--       updated = true
--     else
--       -- Keep original text and original newline (preserves spacing)
--       table.insert(new_lines, text .. newline)
--     end
--   end
--
--   -- Fallback for missing sections
--   if not updated then
--     if in_platformio then
--       table.insert(new_lines, "default_envs = " .. active_env .. "\n")
--     else
--       table.insert(new_lines, 1, "[platformio]\ndefault_envs = " .. active_env .. "\n\n")
--     end
--   end
--
--   misc.writeFile(path, table.concat(new_lines), {})
--   OS.notify("PIO reset default_envs: " .. active_env)
--   _G.metadata.isBusy = false
-- -------------------------------------------------------------------------------
-- end

--INFO:
-- Fast environment detection from platformio.ini file(no external calls)
-- stylua: ignore
--=============================================================================
-- Helper function to extract connected hardware ports using PlatformIO core
local function get_connected_ports()
  if vim.fn.executable('pio') ~= 1 then
    return {}
  end

  -- Spawn an explicit JSON hardware scan via the core engine
  local ok, obj = pcall(function()
    return vim.system({ 'pio', 'device', 'list', '--json' }):wait()
  end)

  if not ok or not obj or obj.code ~= 0 or not obj.stdout then
    return {}
  end

  -- Parse output safely into data tables
  local parse_ok, devices = pcall(vim.json.decode, obj.stdout)
  if not parse_ok or type(devices) ~= 'table' then
    return {}
  end

  local paths = {}
  for _, dev in ipairs(devices) do
    if dev.port then
      paths[dev.port] = true
    end
  end
  return paths
end

function M.get_active__env(from)
  local msg = (type(from) == 'string' and from ~= '') and from or 'PIO: '

  -- 1. Locate the configuration using safe, cross-platform Neovim core logic
  local files = vim.fs.find('platformio.ini', {
    path = vim.api.nvim_buf_get_name(0):match('(.*[/\\])') or vim.uv.cwd(),
    upward = true,
    stop = OS.home,
  })

  local path = files[1]
  if not path then
    OS.notify(msg .. 'platformio.ini not found.', 'error')
    return nil
  end

  -- 2. Extract contents
  local ok, content = misc.readFile(path)
  if not ok or not content then
    OS.notify(msg .. 'Could not read platformio.ini at ' .. path, 'warn')
    return nil
  end

  local default_envs_raw = ''
  local valid_envs = {}
  local env_ports = {} -- Map of environment configurations to their specified port profiles
  local current_section = nil
  local in_platformio_block = false

  -- 3. Parse lines and isolate target parameters
  for line in vim.gsplit(content, '[\r\n]+') do
    line = line:gsub('^%s+', ''):gsub('%s+$', '')

    local section = line:match('^%[(.+)%]$')
    if section then
      current_section = section
      in_platformio_block = (section == 'platformio')

      local env_name = section:match('^env:(.+)')
      if env_name then
        valid_envs[env_name] = true
      end
    end

    -- Capture hardware target keys (e.g. upload_port = COM3 or /dev/ttyUSB0)
    if current_section and current_section:match('^env:') then
      local port_val = line:match('^upload_port%s*=%s*(.+)')
      if port_val then
        local env_name = current_section:match('^env:(.+)')
        env_ports[env_name] = port_val
      end
    end

    if in_platformio_block then
      local def = line:match('^default_envs%s*=%s*(.*)')
      if def then
        default_envs_raw = def
      end
    end
  end

  -- Fetch physical hardware ports active right now
  local connected_ports = get_connected_ports()

  -- Helper closure to verify if an environment matches a plugged-in USB board
  local function is_physically_connected(env_name)
    local target_port = env_ports[env_name]
    if not target_port then
      return true
    end -- If no port is locked in INI, default to true (auto-detect)
    return connected_ports[target_port] == true
  end

  -- 4. Evaluate explicitly specified configurations first
  if default_envs_raw ~= '' then
    for env_name in default_envs_raw:gmatch('([^%s,]+)') do
      if valid_envs[env_name] and is_physically_connected(env_name) then
        return env_name
      end
    end
  end

  -- 5. Fallback selection scanning matching active targets sequentially
  for env_name, _ in pairs(valid_envs) do
    if is_physically_connected(env_name) then
      return env_name
    end
  end

  -- 6. Ultimate baseline recovery (First key parsed chronologically)
  return next(valid_envs)
end




-- function M.get_active__env(from)
--   local msg = (type(from) == 'string' and from ~= '') and from or 'PIO: '
--   local path
--
--   for _, dir in ipairs({ vim.api.nvim_buf_get_name(0):match('(.*[/\\])'), (vim.uv.cwd() .. '/') }) do
--     local tmp = dir .. 'platformio.ini'
--     local filestat = vim.uv.fs_stat(tmp)
--     if filestat and filestat.type == 'file' then
--       path = vim.fs.normalize(tmp)
--       break
--     end
--   end
--   if not path or path == '' then return OS.notify(msg .. 'platformio.ini not found or no [env] defined.', "error") end
--
--   -- Read file content (returns string or nil)
--   local ok, content = misc.readFile(path)
--   if not ok or not content then return OS.notify(msg .. 'platformio.ini not found in ' .. path, "warn") end
--
--   local default_envs_raw = ''
--   local first_env = nil
--   local valid_envs = {}
--   local in_platformio_block = false
--
--   -- Iterate lines from the content string
--   for line in vim.gsplit(content, '\n') do
--     -- Section Detection: [section_name]
--     local section = line:match('^%s*%[(.+)%]%s*$')
--     if section then
--       in_platformio_block = (section == 'platformio')
--       local env_name = section:match('^env:(.+)')
--       if env_name then
--         if not first_env then first_env = env_name end
--         valid_envs[env_name] = true
--       end
--     end
--
--     -- Collect the default_envs string from [platformio] block
--     if in_platformio_block then
--       local def = line:match('^%s*default_envs%s*=%s*(.+)')
--       if def then default_envs_raw = def end
--     end
--   end
--
--   -- Validation: Find the first default_env that actually exists as a block
--   if default_envs_raw ~= '' then
--     -- OS.notify(default_envs_raw, "info")
--     for env_name in default_envs_raw:gmatch('([^%s,]+)') do
--       if valid_envs[env_name] then return env_name end
--     end
--   end
--
--
--   -- if _G.metadata.default_envs[1] ~= nil and _G.metadata.active_env == _G.metadata.default_envs[1] then
--   --   _G.metadata.active_env = default_envs
--     -- M.updateDefaultEnv()
--   -- end
--
--   -- if (_G.metadata.active_env ~= default_envs)then
--   --   _G.metadata.active_env = default_envs
--   --   -- M.updateDefaultEnv()
--   -- end
--   -- Fallback to the very first [env:...] block found in the file
--   return first_env
-- end

--INFO:
--stylua: ignore
-------------------------------------------------------------------------------
function M.pio_refresh(callback, from)
  local msg = (type(from)=='string' and from ~= '') and from or 'PIO: '
  OS.notify(msg ..'Config sync ...', "info")

  local function on_done(active_env)
    if active_env then OS.notify(msg .. 'active_env= ' .. active_env, "info") end
    if active_env then M.fetch_metadata(callback, active_env, from, 1) end
  end
  M.fetch_config(on_done, from)
end

-- INFO:
-- =============================================================================
-- Get project configuration
-- =============================================================================
-- stylua: ignore
function M.fetch_config(on_done, from)
  local msg = (type(from) == 'string' and from ~= '') and from or 'PIO: '
  local meta = _G.metadata

  local active_env
  vim.system({ 'pio', 'project', 'config', '--json-output' }, { text = true }, function(obj)
    vim.schedule(function()
      -- 1. Check Execution
      if obj.code ~= 0 then
        local errmsg = obj.code == 127 and "'pio' not found" or (obj.stderr or 'Unknown Error')
        return OS.notify(msg .. 'Config Error: ' .. errmsg, "error")
      end

      -- 2. Decode JSON safely
      local ok, decoded = pcall(vim.json.decode, obj.stdout or '')
      if not ok or type(decoded) ~= 'table' then
        return OS.notify(msg .. 'Failed to decode config JSON', "error")
      end

      -- local formated = misc.jsonFormat(decoded)
      -- local file = misc.joinPath(vim.uv.cwd(), 'config.json')
      -- misc.writeFile(file, formated, {})

      -- Reset core structure
      meta.envs = {}
      meta.default_envs = {}
      local valid_envs = {}

      -- 3. Parse Sections
      for _, section in ipairs(decoded) do
        local name, data = section[1], section[2]
        if name == 'platformio' then
          for _, kv in ipairs(data) do
            meta[kv[1]] = kv[2]
          end
        elseif name:match('^env:') then
          local env_name = name:match('^env:(.+)')
          if not active_env then active_env = env_name end
          valid_envs[env_name] = true
          meta.envs[env_name] = {}
          for _, kv in ipairs(data) do
            meta.envs[env_name][kv[1]] = kv[2]
          end
        end
      end

      -- 4. Assign active_env
      -- Validation: Find the first default_env that actually exists as a block
      for _, env_name in ipairs(meta.default_envs) do
        if valid_envs[env_name] then
          active_env = env_name
          break
        end
      end
      meta.active_env = active_env
      -- M.updateDefaultEnv()

      -- 5. Resolve Paths (INI -> Env -> Default)
      local path_map = {
        { key = 'core_dir', env = 'PLATFORMIO_CORE_DIR', sub = '/.platformio' },
        { key = 'packages_dir', env = 'PLATFORMIO_PACKAGES_DIR', sub = '/.platformio/packages' },
        { key = 'platforms_dir', env = 'PLATFORMIO_PLATFORMS_DIR', sub = '/.platformio/platforms' },
      }

      for _, item in ipairs(path_map) do
        local val = meta[item.key]
        -- Fallback chain
        if not val or val == '' then
          val = os.getenv(item.env) or (OS.home .. item.sub)
        end
        -- Expand variables and Normalize
        if type(val) == 'string' then
          val = val:gsub('%%${platformio.core_dir}', meta.core_dir or '')
          meta[item.key] = misc.normalizePath(val)
        end
      end

      -- 6. Trigger next step
      if meta.active_env ~= '' then
        OS.notify(msg .. 'Config sync successful', "info")
      else
        OS.notify(msg .. 'No [env:] found. Please add a board.', "error")
      end

      if on_done then
        vim.schedule(function() on_done(active_env) end)
      end
    end)
  end)
end

--INFO:
-- get pio project metadata info
-- stylua: ignore
--=============================================================================
function M.fetch_metadata(callback, env, from, attempts)
  local msg = (type(from)=='string' and from ~= '') and from or 'PIO: '
  local meta = _G.metadata
  local active_env = env or meta.active_env
  if not active_env or active_env == '' then
    return
  end

  -- Set up file paths
  local build_dir = misc.joinPath(vim.uv.cwd(), '.pio', 'build')
  local build_env_dir = misc.joinPath(build_dir, active_env)
  local checksum_file = misc.joinPath(build_dir, 'project.checksum')
  local idedata_file = misc.joinPath(build_env_dir, 'idedata.json')

  --INFO:
  --INTERNAL PROCESSOR: Applies parsed data to _G.metadata
  ---------------------------------------------------------
  local function apply_metadata(data, checksum)
    if not data then return false end

    local norm = function(p) return misc.normalizePath(p) or '' end

    -- Helper for flags/defines to keep order and formatting
    local quote_map = function(list, prefix)
      local res = {}
      for _, v in ipairs(list or {}) do
        local val = prefix and (prefix .. norm(v)) or v
        table.insert(res, string.format('%s', val))
      end
      return res
    end

    -- 1. Base Paths & Compilers
    meta.cc_path = norm(data.cc_path)
    meta.cc_compiler = meta.cc_path
    meta.cxx_path = norm(data.cxx_path)
    meta.gdb_path = norm(data.gdb_path)

    -- 2. Flags & Defines
    meta.cc_flags = quote_map(data.cc_flags)
    meta.cxx_flags = quote_map(data.cxx_flags)
    meta.defines = quote_map(data.defines)

    -- 3. Includes (Build, Toolchain, Compatlib)
    local inc = data.includes or {}
    meta.includes_build = quote_map(inc.build, '-I')
    meta.includes_toolchain = quote_map(inc.toolchain, '-isystem')
    meta.includes_compatlib = quote_map(inc.compatlib, '-isystem')
    meta.last_projectChecksum = checksum
    pcall(M.get_sysroot_triplet, meta.cc_compiler)

    return true
  end

  --INFO:
  --Generate idedata.json
  ---------------------------------------------------------
  local function buildIdedata()
    OS.notify(msg .. 'Initializing project metadata...', "info")
    vim.system({ 'pio', 'run', '-t', 'idedata', '-e', active_env, '-s' }, { text = true }, function(obj)
      vim.schedule(function()
        if obj.code == 0 then
          OS.notify(msg .. 'Initializing project metadata success.', "info")
          M.fetch_metadata(callback, active_env, from, attempts - 1) -- Recursive call after files created
        else
          OS.notify(msg .. 'Initialization failed. Build project manually.: ' .. obj.stderr, "error")
        end
      end)
    end)
    return true
  end

  -------------------------------------------------------------------
  -- STEP 1: Fast Checksum Check (project.checksum and idedata.json)
  -------------------------------------------------------------------
  local ok, current_checksum = misc.readFile(checksum_file)
  if ok and (type(current_checksum) == 'string' and current_checksum ~= '') then
    if current_checksum == meta.last_projectChecksum then
      OS.notify(msg .. 'Metadata synced with cache', "info")
      -- if callback then callback() end
      if callback then vim.schedule(callback) end
      return true
    end -- Already updated

    ----------------------------------------------------------------
    -- STEP 2: Cache Path (idedata.json exists and checksum changed)
    ----------------------------------------------------------------
    local idok, content = misc.readFile(idedata_file)
    if idok and (type(content) == 'string' and content ~= '') then
      local cok, decoded = pcall(vim.json.decode, content)

      -- local formated = misc.jsonFormat(decoded)
      -- local file = misc.joinPath(vim.uv.cwd(), 'idedata.json')
      -- misc.writeFile(file, formated, {})

      if cok and apply_metadata(decoded, current_checksum) then
        local metadata = require('nvimpio.pio.metadata')
        metadata.save_project_config(msg)
        OS.notify(msg .. 'Metadata synced from cache', "info")
        -- if callback then vim.schedule(callback) end

        if type(callback) == "function" then
          vim.schedule(callback)
        else
          -- If it's not a function, just do nothing or print a debug message
          OS.notify(msg .." Debug; callback was " .. type(callback), 'debug')
        end

        return true
      end
    -- else
    end
  -- else
  end
  ------------------------------------------------------------------------------------
  -- STEP 3: Auto-Initialize (If files project.checksum and idedata.json are missing)
  ------------------------------------------------------------------------------------
  buildIdedata()

  ---------------------------------------------------------
  -- STEP 4: Standard CLI Fallback (The Slow Path)
  ---------------------------------------------------------
  -- OS.notify(msg .. 'Metadata sync ...', "info")
  -- vim.system({ 'pio', 'project', 'metadata', '-e', active_env, '--json-output' }, { text = true }, function(obj)
  --   vim.schedule(function()
  --     if obj.code ~= 0 then
  --       if attempts > 0 then
  --         vim.defer_fn(function() M.fetch_metadata(attempts - 1, env) end, 500)
  --         return
  --       end
  --       return OS.notify(msg .. 'Metadata Error: ' .. (obj.stderr or 'Unknown'), "warn")
  --     end
  --
  --     local ook, raw_data = pcall(vim.json.decode, obj.stdout or '')
  --     local _, data = next(raw_data or {})
  --
  --     if ook and apply_metadata(data, current_checksum) then
  --       OS.notify(msg .. 'Metadata synced from CLI', "info")
  --       if callback then vim.schedule(callback) end
  --     else
  --       OS.notify(msg .. 'Failed to parse metadata output', "warn")
  --     end
  --   end)
  -- end)
end


-- INFO:
-- Fix compile_commands.json file with absoulute paths
-- stylua: ignore
-- =============================================================================
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
    clangd.restart()
  end
  OS.notify("no need to fixPaths")
  _G.metadata.isBusy = false
end

-- INFO:
--configuration for running sequential commands on ToggleTerminal
-- stylua: ignore
-- Initialize
-- =============================================================================
local current_token = tostring(math.random(10000, 99999))
local current_id = -1 -- Holds 0 for DONE, or 1-9 for PASS

local current_pass_current_token = ''
local current_fail_current_token = ''

local session_counter = 0 -- Our high-performance integer counter
local pio_buffer = '' -- Initialize to prevent nil concatenation crashes
local callBack = nil -- Your execution hook function pointer
local commandPassed = 0
M.queue = {}
term.stdout_callback = M.stdoutcallback
local trm
local nvimpio = require('nvimpio')

-- INFO: ToggleTerminal commands stdout filter
-- stylua: ignore
-- =============================================================================
function M.stdoutcallback(_, _, data)
  if not data or #data == 0 then
    return
  end

  if #data > 1 then
    -- local content = pio_buffer .. table.concat(data, '', 1, #data - 1)
    local content = pio_buffer .. table.concat(data, '', 1, #data)
    pio_buffer = data[#data] -- Save the new partial line

    -- local pass_target = current_id == 0 and 'DONE' or ('PASS' .. current_id)
    local pass_target = 'PASS' .. current_id

    -- local pass_pattern = '^%s*_CMMNDS_' .. current_token .. ':' .. pass_target
    -- local fail_pattern = '^%s*_CMMNDS_' .. current_token .. ':FAIL'
    local pass_pattern = '_CMMNDS_' .. current_token .. ':' .. pass_target
    local fail_pattern = '_CMMNDS_' .. current_token .. ':FAIL'
    local done_pattern = '_CMMNDS_' .. current_token .. ':DONE'

    local has_pass = content:find(pass_pattern) ~= nil
    local has_done = content:find(done_pattern) ~= nil
    local has_fail = content:find(fail_pattern) ~= nil
    if has_pass or has_fail or has_done then
      local active_cb = callBack

      -- Clear state boundaries instantly to block execution overlaps
      callBack = nil
      pio_buffer = '' -- Wipe buffer completely to lock out trailing shell prompts

      local final_status = 'FAIL'
      if has_fail then
        final_status = 'FAIL'
        M.queue = {} -- Instantly wipe remaining queue items to halt the pipeline
      elseif has_done then
        final_status = 'DONE'
        M.queue = {} -- Instantly wipe remaining queue items to halt the pipeline
      elseif has_pass then
        final_status = pass_target
      end

      -- 7. Safe Dispatch back to Neovim main UI thread after terminal settles
      if final_status and active_cb then
        vim.schedule(function()
          active_cb(final_status)
        end)
      end

      return -- Break out immediately upon executing the callback
    end

  else
    -- Only one element (no newline yet;) means the line isn't finished yet
    pio_buffer = pio_buffer .. data[1]
  end

  -- 3. Safety Trim (Prevents memory leaks if no newline ever comes)
  if #pio_buffer > 5000 then
    pio_buffer = pio_buffer:sub(-2500)
  end
end

-- function M.stdoutcallback(_, _, data)
--   if not data or #data == 0 then return end
--
--   -- 1. Correctly handle Neovim's data chunks
--   -- data[1] is the continuation of the previous chunk
--   -- data[#data] is a partial line (no newline yet)
--
--   if #data > 1 then
--     -- Join the buffer with the first element and all middle elements
--     --(everything except the last partial line)
--     -- 1. Stream Collection
--     local content = pio_buffer .. table.concat(data, "", 1, #data - 1)
--     pio_buffer = data[#data] -- Save the new partial line
--
--     -- 2. Build explicit, independent validation patterns
--     --    Using [^%%w]* safely abstracts colons, quotes, and spacing variations
--     local pass_pattern = '_CMMNDS_' .. current_token .. '[^%%w]*(PASS' .. current_id .. ')'
--     local done_pattern = '_CMMNDS_' .. current_token .. '[^%%w]*(DONE)'
--     local fail_pattern = '_CMMNDS_' .. current_token .. '[^%%w]*(FAIL)'
--
--     -- 3. Match Evaluation
--     local matched_pass = content:match(pass_pattern)
--     local matched_done = content:match(done_pattern)
--     local matched_fail = content:match(fail_pattern)
--
--     -- 4. Strict Priority Execution Block
--     if matched_pass or matched_done or matched_fail then
--       -- Default fallback state
--       local final_status = "FAIL"
--       -- Check fields in order of absolute priority
--       if matched_fail then
--         final_status = "FAIL"
--         M.queue = {} -- Instantly wipe remaining queue items to halt the pipeline
--       elseif matched_done then
--         final_status = "DONE"
--       elseif matched_pass then
--         final_status = matched_pass
--       end
--
--       -- 5. Safe Dispatch back to Neovim main thread
--       if final_status and callBack then
--         vim.schedule(function() callBack(final_status) end)
--       end
--     end
--
--   else
--     -- Only one element (no newline yet;) means the line isn't finished yet
--     pio_buffer = pio_buffer .. data[1]
--   end
--
--   -- 3. Safety Trim (Prevents memory leaks if no newline ever comes)
--   if #pio_buffer > 5000 then pio_buffer = pio_buffer:sub(-2500) end
-- end

--- Universal, bulletproof stream analyzer for Toggleterm
-- function M.stdoutcallback(t, job, data)
--   if not data or #data == 0 or not callBack then return end
--
--   -- 1. Stream Collection: Always merge chunks into a unified rolling buffer string
--   pio_buffer = pio_buffer .. table.concat(data, "")
--   if #pio_buffer > 2000 then pio_buffer = pio_buffer:sub(-2000) end
--
--   -- 2. Build explicit, strict target text indicators (Powershell strips quotes, uses ":")
--   --    If current_id is 0, we look for DONE. Otherwise we look for PASS<num>
--   local pass_target = current_id == 0 and "DONE" or ("PASS" .. current_id)
--
--   local expected_pass = '_CMMNDS_' .. current_token .. ':' .. pass_target
--   local expected_fail = '_CMMNDS_' .. current_token .. ':FAIL'
--
--   -- 3. High-Performance Substring Searches
--   --    Using plain byte searches turns off regex blocks completely, crushing prompt bugs!
--   local has_pass = pio_buffer:find(expected_pass, 1, true) ~= nil
--   local has_fail = pio_buffer:find(expected_fail, 1, true) ~= nil
--
--   -- 4. Priority Execution Gate
--   if has_pass or has_fail then
--     local active_cb = callBack
--
--     -- Wipe session state variables instantly to protect against duplicate flushes
--     callBack = nil
--     pio_buffer = ""
-- print(pass_target)
--     local final_status = "FAIL"
--     if has_fail then
--       final_status = "FAIL"
--       M.queue = {} -- Evacuate remainder table rows immediately on error
--     elseif has_pass then
--       -- Pass back the exact token word ("PASS1", "PASS9", or "DONE")
--       final_status = pass_target
--     end
--
--     -- Return control back to Neovim's main UI thread safely
--     vim.defer_fn(function()
--       vim.schedule(function()
--         pcall(active_cb, final_status)
--       end)
--     end, 50)
--   end
-- end
--xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx

-- function M.stdoutcallback(t, job, data)
--   if not data or #data == 0 or not callBack then return end
--
--   -- 1. Stream Collection: Accumulate all incoming pieces into our line-matching buffer
--   pio_buffer = pio_buffer .. table.concat(data, "")
--
--   -- 2. Line Isolation Loop: Process complete lines bounded by newlines (\n)
--   while pio_buffer:find("\n") do
--     -- Extract the first complete line and save the rest back to the buffer
--     local line, rest = pio_buffer:match("^([^\n]*)\n(.*)$")
--     pio_buffer = rest or ""
--
--     -- 3. Cross-Platform Normalization
--     line = line:gsub('\r', '') -- Strip hidden Windows carriage returns
--     line = line:gsub('\27%[[%d;]*%a', '') -- Strip invisible ANSI terminal escape/color codes
--
--     -- 4. Target Suffix Definition
--     local pass_target = current_id == 0 and "DONE" or ("PASS" .. current_id)
--
--     -- 5. THE CRUCIAL MATCH ENGINE:
--     --    We use Lua's '^' anchor to force matching at the ABSOLUTE START of the line.
--     --    We use a strict single colon ':' with NO quotes.
--     --    This matches ONLY your output line and completely ignores the typed input command!
--     local pass_pattern = '^%s*_CMMNDS_' .. current_token .. ':' .. pass_target
--     local fail_pattern = '^%s*_CMMNDS_' .. current_token .. ':FAIL'
--
--     -- Plain byte string find from the start of the line (immune to regex syntax bugs)
--     local has_pass = line:find(pass_pattern) ~= nil
--     local has_fail = line:find(fail_pattern) ~= nil
--
--     -- 6. Strict Priority Execution Gate
--     if has_pass or has_fail then
--       local active_cb = callBack
--
--       -- Clear state boundaries instantly to block execution overlaps
--       callBack = nil
--       pio_buffer = "" -- Wipe buffer completely to lock out trailing shell prompts
--
--       local final_status = "FAIL"
--       if has_fail then
--         final_status = "FAIL"
--         M.queue = {} -- Instantly wipe remaining queue items to halt the pipeline
--       elseif has_pass then
--         final_status = pass_target
--       end
--
--       -- 7. Safe Dispatch back to Neovim main UI thread after terminal settles
--       vim.defer_fn(function()
--         vim.schedule(function()
--           pcall(active_cb, final_status)
--         end)
--       end, 50)
--
--       return -- Break out immediately upon executing the callback
--     end
--   end
--
--   -- 8. Safety Trim (Prevents memory leaks on long compile logs if a line never finishes)
--   if #pio_buffer > 4000 then
--     pio_buffer = pio_buffer:sub(-1000)
--   end
-- end

-- function M.stdoutcallback(_, _, data)
--   if not data or #data == 0 then return end
--
--   -- 1. Correctly handle Neovim's data chunks
--   local target_text = ""
--
--   if #data > 1 then
--     -- Join the buffer with everything except the last partial line
--     target_text = pio_buffer .. table.concat(data, "", 1, #data - 1)
--     pio_buffer = data[#data] -- Save the new partial line
--   else
--     -- Append single element to buffer and test the whole combined buffer
--     pio_buffer = pio_buffer .. table.concat(data, "")
--     target_text = pio_buffer
--   end
--
--   -- 2. FIXED PATTERNS: Using %W* cleanly matches any non-alphanumeric punctuation
--   --    (like colons, quotes, or spaces) separating the token and your words!
--   local pass_pattern = '_CMMNDS_' .. current_token .. '%W*(PASS' .. current_id .. ')'
--   local done_pattern = '_CMMNDS_' .. current_token .. '%W*(DONE)'
--   local fail_pattern = '_CMMNDS_' .. current_token .. '%W*(FAIL)'
--
--   -- 3. Match Evaluation against the isolated text block
--   local matched_pass = target_text:match(pass_pattern)
--   local matched_done = target_text:match(done_pattern)
--   local matched_fail = target_text:match(fail_pattern)
--
--   -- 4. Strict Priority Execution Block
--   if matched_pass or matched_done or matched_fail then
--     local active_cb = callBack
--
--     -- Clear state boundaries instantly to prevent overlapping triggers
--     callBack = nil
--     if #data > 1 then pio_buffer = data[#data] else pio_buffer = "" end
--
--     -- Default fallback state
--     local final_status = "FAIL"
--
--     -- Check fields in order of absolute priority
--     if matched_fail then
--       print(matched_fail)
--       final_status = "FAIL"
--       M.queue = {} -- Instantly wipe remaining queue items to halt the pipeline
--     elseif matched_done then
--       print(matched_done)
--       final_status = "DONE"
--     elseif matched_pass then
--       print(matched_pass)
--       -- Captures and assigns your clean string token like "PASS1"
--       final_status = matched_pass
--     end
--
--     -- 5. Safe Dispatch back to Neovim main thread
--     if final_status and active_cb then
--       vim.schedule(function()
--         pcall(active_cb, final_status)
--       end)
--     end
--   end
--
--   -- 6. Safety Trim (Prevents memory leaks if no newline ever comes)
--   if #pio_buffer > 5000 then pio_buffer = pio_buffer:sub(-2500) end
-- end

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
M.run_sequence = function(tasks)
  M.queue = {}
  local commands = tasks.cmnds

  session_counter = session_counter + 1
  if session_counter > 9999 then session_counter = 1 end
  local token = string.format("%04d", session_counter)

  local total = #commands

  for i, cmd in ipairs(commands) do
    local step_id = (i == total) and 0 or i
    table.insert(M.queue, { cmd, step_id, token })
  end


  -- local done = string.format(' && echo _CMMNDS_%s":"DONE', current_current_token)
  -- local pass = string.format(' && echo _CMMNDS_%s":"PASS', current_current_token)
  -- local fail = string.format(' || echo _CMMNDS_%s":"FAIL', current_current_token)
  -- --
  -- for i, cmd in ipairs(commands) do
  --   local full_cmd = ''
  --   if i == #commands then full_cmd = cmd .. done .. fail
  --   else full_cmd = string.format("%s%s%01d%s",cmd, pass, i, fail) end
  --   table.insert(M.queue, full_cmd)
  -- end

  callBack = tasks.cb -- 1. Save the callback in a local variable

  if not nvimpio.is_active then
    require('nvimpio.pio.metadata')
  end

  if callBack then
    vim.schedule(function()
      commandPassed = 1
      pio_buffer = ''
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
  M.queue = {}
  callBack = nil
  pio_buffer = ''
  term.stdout_callback = nil -- Careful: make sure this doesn't break other terms
  -- if trm then trm:close() end
end

-- stylua: ignore
function M.handlePioinitDb(result, board, on_done)
  print(result)
  if result == 'INIT' then
    if #M.queue > 0 then
      _G.metadata.isBusy = true
      boilerplate.core_dir = _G.metadata.core_dir
      boilerplate_gen([[platformio.ini]], vim.g.platformioRootDir)

      -- trm = term.ToggleTerminal(table.remove(M.queue, 1), 'float')
      trm = term.ToggleTerminal(pop(M.queue), 'float')
      if trm and on_done and type(on_done) == "function" then
        vim.keymap.set('n', '<leader>\\t', function() trm:open() end, { desc = 'open Term' })
      end
    end
  elseif result == 'PASS' .. current_id then
    if commandPassed == 1 then
      local active_env = M.get_active__env('PIO init+db: ')
      OS.notify('PIO init+db:  pass ' .. commandPassed, "info")
      commandPassed = commandPassed + 1
      if not active_env or (active_env == board) then
        boilerplate_gen([[main.cpp]], vim.g.platformioRootDir .. '/src')
        boilerplate_gen([[main.hpp]], vim.g.platformioRootDir .. '/include')
        if #M.queue > 0 then
          -- trm = term.ToggleTerminal(table.remove(M.queue, 1), 'float')
          -- trm:send(table.remove(M.queue, 1), false)
          trm:send(pop(M.queue), false)
        end
      else
        if on_done and type(on_done) == "function" then on_done(false) end
        M.cleanSequencer()
      end
    -- elseif commandPassed == 2 then -- if you sned more than 2 commands you need this
    end
  elseif result == 'DONE' then -- result of the last command
    -- vim.schedule(function()
    OS.notify('PIO init+db:  pass ' .. commandPassed, "info")
    OS.notify('PIO init+db: Done', "info")
    M.pio_refresh(function()
      if on_done and type(on_done) == "function" then on_done(true)
      else clangd.getUnknownArgs() end
      boilerplate.core_dir = _G.metadata.core_dir
    end, 'PIO init+db: ')
    -- end)
    if trm then trm:close() end
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
print(result)
  if result == 'INIT' then
    if #M.queue > 0 then
      _G.metadata.isBusy = true
      trm = term.ToggleTerminal(pop(M.queue), 'float')
      -- trm = term.ToggleTerminal(table.remove(M.queue, 1), 'float')
      if trm and on_done and type(on_done) == "function" then
        vim.keymap.set('n', '<leader>\\t', function() trm:open() end, { desc = 'open Term' })
      end
      -- if trm then trm:open() end
    end
  elseif result == 'PASS' .. current_id then
    if commandPassed == 1 then
      OS.notify('PIO install:  pass ' .. commandPassed, "info")
      commandPassed = commandPassed + 1
      -- if #M.queue > 0 then trm:send(table.remove(M.queue, 1), false) end
      if #M.queue > 0 then
        -- trm = term.ToggleTerminal(table.remove(M.queue, 1), 'float')
        trm:send(pop(M.queue), false)
        -- if trm then
        --   trm:open()
        --   trm:send(table.remove(M.queue, 1), false)
        -- end
      end
    -- elseif commandPassed == 2 then -- if you sned more than 2 commands you need this
    end
  elseif result == 'DONE' then -- result of the only and the last command
    OS.notify('PIO install:  pass ' .. commandPassed, "info")
    OS.notify('PIO install: Done', "info")
    commandPassed = commandPassed + 1

    -- 1. Always remove the script
    -- vim.schedule(function()
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
    OS.notify('PIO install: success', 'info')

    -- if trm then trm:close() end
    if on_done and type(on_done) == "function" then on_done(true) end
    -- end)
    M.cleanSequencer()
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
      trm = term.ToggleTerminal(table.remove(M.queue, 1), 'float')
      -- if trm then trm:open() end
    end
  elseif result == 'DONE' then -- result of the only and the last command
    OS.notify('Clang formatter:  pass ' .. commandPassed, "info")
    OS.notify('Clang formatter: Done', "info")
    commandPassed = commandPassed + 1
    -- if trm then trm:close() end
    M.cleanSequencer()
  elseif result == 'FAIL' then
    M.cleanSequencer()
  end
end

-- =============================================================================
-- stylua: ignore
function M.handlePioDB(result)
  if result == 'INIT' then
    if #M.queue > 0 then
      _G.metadata.isBusy = true
      trm = term.ToggleTerminal(table.remove(M.queue, 1), 'float')
      -- if trm then trm:open() end
    end
  elseif result == 'DONE' then -- result of the only and the last command
    vim.schedule(function()
      OS.notify('PIO compiledb:  pass ' .. commandPassed, "info")
      OS.notify('PIO compiledb: Done', "info")
      M.pio_refresh(function()
        clangd.getUnknownArgs()
        boilerplate.core_dir = _G.metadata.core_dir
      end, 'PIO compiledb: ')
    end)
    -- if trm then trm:close() end
    M.cleanSequencer()
  elseif result == 'FAIL' then
    M.cleanSequencer()
  end
end

----------------------------------------------------
-- Handle after pioinit execution
-- stylua: ignore
function M.handlePioinit(result)
  if result == 'INIT' then

    if #M.queue > 0 then
      boilerplate.core_dir = _G.metadata.core_dir
      boilerplate_gen([[platformio.ini]], vim.g.platformioRootDir)
      boilerplate_gen([[.clang-format]], vim.g.platformioRootDir)
      boilerplate_gen([[.clangd]], vim.g.platformioRootDir)
      trm = term.ToggleTerminal(table.remove(M.queue, 1), 'float')
      _G.metadata.isBusy = true
      -- if trm then trm:open() end
    end
  elseif result == 'DONE' then -- result of the last command
    vim.schedule(function()
      OS.notify('PIO init:  pass ' .. commandPassed, "info")
      OS.notify('PIO init: Done', "info")

      -- \27[s   : Save current cursor position (the prompt)
      -- \r      : Go to start of line
      -- \27[A   : Move cursor UP one line (to space above prompt)
      -- \27[K   : Clear that line
      -- \27[33m : Color Yellow (optional)
      -- %s      : Your message
      -- \27[0m  : Reset color
      -- \27[u   : Restore cursor back to the prompt
      -- IMPORTANT: No \n at the end, so it doesn't execute
      -- local msg = '************ Please wait for project Initialization to finish ************'
      -- local clean_msg = string.format('\27[G\27[2K\27[33m%s\27[0m', msg)
      -- vim.api.nvim_chan_send(trm:job_id, clean_msg)

      -- local pio_refresh = require('nvimpio.pio.control').pio_refresh
      M.pio_refresh(function()
        boilerplate_gen([[.clangd]], _G.metadata.core_dir)
        clangd.restart()
        -- term.ToggleTerminal('echo "************ project Initialization success ************"', 'float')
      end, 'PIO init: ')
    end)
    M.cleanSequencer()
  elseif result == 'FAIL' then
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
      trm = term.ToggleTerminal(table.remove(M.queue, 1), 'float')
      -- if trm then trm:open() end
    end
  elseif result == 'PASS' then
    if commandPassed == 1 then
      OS.notify('PIO lib+db:  pass ' .. commandPassed, "info")
      commandPassed = commandPassed + 1
      -- if #M.queue > 0 then trm:send(table.remove(M.queue, 1), false) end
      if #M.queue > 0 then
        -- if trm then
          -- trm:open()
          -- trm:send(table.remove(M.queue, 1), false)
      trm = term.ToggleTerminal(table.remove(M.queue, 1), 'float')
        -- end
      end
    -- elseif commandPassed == 2 then -- if you sned more than 2 commands you need this
    end
  elseif result == 'DONE' then -- result of the last command
    vim.schedule(function()
      OS.notify('PIO lib+db:  pass ' .. commandPassed, "info")
      OS.notify('PIO lib+db: Done', "info")
      M.pio_refresh(function()
        clangd.getUnknownArgs()
      end, 'PIO lib+db: ')
    end)
    -- if trm then trm:close() end
    M.cleanSequencer()
  elseif result == 'FAIL' then
    M.cleanSequencer()
  end
end
return M
