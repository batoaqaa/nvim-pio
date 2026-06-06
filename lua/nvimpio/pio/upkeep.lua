---@class platformio.utils.pio
local M = {}

-- local clangd = require('nvimpio.clangd.control')
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
    if match then triplet = vim.fs.normalizePath(match) break
    end
  end

  -- Return nil if no compiler was found in the bin directory
  if not triplet then return nil end

  -- toolchain_root is the parent of the 'bin' folder
  local toolchain_root = vim.fs.normalizePath(vim.fn.fnamemodify(bin_path, ':h'))

  -- sysroot folder is expected to have the same name as the triplet
  local sysroot = vim.fs.joinpath(toolchain_root, triplet)

  -- local query_driver = vim.fs.joinpath(bin_path, triplet) .. '-*'
  -- local query_driver = misc.normalizePath(bin_path .. '/' .. triplet .. '-*')
  local query_driver = vim.fs.normalizePath(bin_path .. '/*')

  _G.metadata = _G.metadata or {}
  _G.metadata.triplet = triplet
  _G.metadata.toolchain_root = toolchain_root
  _G.metadata.query_driver = query_driver

  -- Check if sysroot folder actually exists on disk (Optional fallback validation)
  -- If it doesn't exist, we fall back to toolchain_root so your metadata never breaks!
  if vim.fn.isdirectory(sysroot) == 1 then
    _G.metadata.sysroot = sysroot
  else
    _G.metadata.sysroot = toolchain_root
  end

  -- Extract the macros using the correct platform null device destination
  local auto_defines = {}
  local cmd = string.format('"%s" -E -dM -xc++ %s', cc_compiler, OS.devNul)
  local handle = io.popen(cmd)

  if handle then
    for line in handle:lines() do
      local macro, value = line:match("#define%s+([%w_]+)%s+(.*)")
      if macro and value ~= "" then
        local lower_macro = macro:lower()
        -- Generic pattern matchers that capture all major embedded ecosystems
        local is_arch    = lower_macro:match("xtensa") or lower_macro:match("arm") or lower_macro:match("riscv") or lower_macro:match("avr")
        local is_vendor  = lower_macro:match("esp") or lower_macro:match("stm") or lower_macro:match("nrf") or lower_macro:match("samd") or lower_macro:match("rp20")
        local is_version = macro == "__GNUC__" or macro == "__cplusplus" or macro == "__GNUC_MINOR__"
        if is_arch or is_vendor or is_version then
          -- Clean up trailing comments or whitespace from the compiler value
          value = value:gsub("%s*//.*$", ""):gsub("%s*$", "")
          table.insert(auto_defines, "-D" .. macro .. "=" .. value)
        end
      end
    end
    handle:close()
  end

  _G.metadata.auto_defines = auto_defines

  return {
    triplet = triplet,
    sysroot = _G.metadata.sysroot,
    toolchain_root = toolchain_root,
    query_driver = query_driver,
    auto_defines = auto_defines,
  }
end

-- stylua: ignore
--=============================================================================
--INFO: setup up device port
---Scans the hardware bus for active microcontrollers and returns a sorted list array of strings
---@return string[] ports A sequential list of discovered port strings
function M.get_connected_ports()
  if vim.fn.executable('pio') ~= 1 then return {} end

  -- Run the system command synchronously to fetch device mappings
  local ok, obj = pcall(function()
    return vim.system({ 'pio', 'device', 'list', '--json-output' }):wait()
  end)

  if not ok or not obj or obj.code ~= 0 or not obj.stdout then return {} end

  local parse_ok, devices = pcall(vim.json.decode, obj.stdout)
  if not parse_ok or type(devices) ~= 'table' then return {} end

  -- Clean property extraction loop with robust hardware device fallbacks
  local unique_paths = {}
  for _, dev in ipairs(devices) do
    local active_path = dev.port or dev.device
    if active_path and type(active_path) == 'string' and vim.trim(active_path) ~= '' then
      unique_paths[active_path] = true
    end
  end

  -- Flatten dictionary keys out into a sequential list array for selectors
  local ports = {}
  for path, _ in pairs(unique_paths) do
    table.insert(ports, path)
  end
  table.sort(ports)

  return ports
end

---Configures all PlatformIO hardware execution variables interactively
function M.configure_hardware_parameters()
  local p_state = _G.metadata.port_parameters
  local speeds = { '9600', '19200', '38400', '57600', '115200', '230400', '460800', '921600' }

  -- 1. Instantly gather ports using our new unified scanner function helper
  local ports = M.get_connected_ports()
  if #ports == 0 then
    ports = { 'Auto Detect' }
  end

  -- Define the steps mapping sequence arrays
  local steps = {
    {
      p = ' [1/5] Select Targeted Serial Port ',
      c = ports,
      s = function(x)
        p_state.selected_port = x
        vim.g.platformio_selected_port = x
      end,
    },
    {
      p = ' [2/5] Select Upload Speed (Baud) ',
      c = speeds,
      s = function(x)
        p_state.upload_speed = x
      end,
    },
    {
      p = ' [3/5] Select Serial Monitor Speed ',
      c = speeds,
      s = function(x)
        p_state.monitor_speed = x
      end,
    },
    {
      p = ' [4/5] Set Monitor RTS Pin State ',
      c = { '0', '1' },
      s = function(x)
        p_state.monitor_rts = x
      end,
    },
    {
      p = ' [5/5] Set Monitor DTR Pin State ',
      c = { '0', '1' },
      s = function(x)
        p_state.monitor_dtr = x
      end,
    },
  }

  -- Defensive, Context-Aware File System Injector Engine
  local function inject_into_ini()
    _G.metadata.isBusy = true
    local path = vim.fs.joinpath(vim.uv.cwd(), 'platformio.ini')
    if vim.fn.filereadable(path) ~= 1 then
      return
    end

    local lines, eol = {}, '\n'
    local f_in = io.open(path, 'rb')
    if f_in then
      local src = f_in:read('*all') or ''
      f_in:close()
      if src:find('\r\n') then
        eol = '\r\n'
      end
      for line in src:gmatch('[^\r\n]+') do
        if
          not line:match('^%s*upload_port%s*=')
          and not line:match('^%s*monitor_port%s*=')
          and not line:match('^%s*upload_speed%s*=')
          and not line:match('^%s*monitor_speed%s*=')
          and not line:match('^%s*monitor_filters%s*=')
          and not line:match('^%s*monitor_rts%s*=')
          and not line:match('^%s*monitor_dtr%s*=')
        then
          table.insert(lines, line)
        end
      end
    end

    local patches = { 'monitor_filters = direct, send_on_enter' }
    if p_state.selected_port and p_state.selected_port ~= 'Auto Detect' then
      table.insert(patches, 'upload_port = ' .. p_state.selected_port)
      table.insert(patches, 'monitor_port = ' .. p_state.selected_port)
    end
    if p_state.upload_speed then
      table.insert(patches, 'upload_speed = ' .. p_state.upload_speed)
    end
    if p_state.monitor_speed then
      table.insert(patches, 'monitor_speed = ' .. p_state.monitor_speed)
    end
    if p_state.monitor_rts then
      table.insert(patches, 'monitor_rts = ' .. p_state.monitor_rts)
    end
    if p_state.monitor_dtr then
      table.insert(patches, 'monitor_dtr = ' .. p_state.monitor_dtr)
    end

    local env_idx = nil
    for idx, line in ipairs(lines) do
      if line:match('^%s*%[%s*env%s*%]%s*$') then
        env_idx = idx
        break
      end
    end

    if env_idx then
      for i, cfg in ipairs(patches) do
        table.insert(lines, env_idx + i, cfg)
      end
    else
      table.insert(lines, '')
      table.insert(lines, '[env]')
      for _, cfg in ipairs(patches) do
        table.insert(lines, cfg)
      end
    end

    local f_out = io.open(path, 'wb')
    if f_out then
      f_out:write(table.concat(lines, eol) .. eol)
      f_out:close()
    end
    vim.defer_fn(function()
      _G.metadata.isBusy = false
    end, 500)
  end

  -- Linear Execution Wizard Runner Loop
  local function run(step_idx)
    if not steps[step_idx] then
      inject_into_ini()
      local msg = string.format(
        'Injected: Port: %s | Upload: %s baud | Monitor: %s baud',
        p_state.selected_port or 'Auto',
        p_state.upload_speed or 'Ini',
        p_state.monitor_speed or 'Ini'
      )
      return _G.OS and type(_G.OS.notify) == 'function' and _G.OS.notify(msg, 'info') or vim.notify(msg, 2)
    end

    vim.ui.select(steps[step_idx].c, { prompt = steps[step_idx].p }, function(sel)
      if not sel then
        return vim.notify('NVIM-PIO: Configuration wizard aborted.', 3)
      end
      steps[step_idx].s(sel)
      run(step_idx + 1)
    end)
  end

  -- Run the wizard sequence directly using instantaneous parsed arrays
  run(1)
end

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
  local build_dir = vim.fs.joinpath(vim.uv.cwd(), '.pio', 'build')
  local build_env_dir = vim.fs.joinpath(build_dir, active_env)
  local checksum_file = vim.fs.joinpath(build_dir, 'project.checksum')
  local idedata_file = vim.fs.joinpath(build_env_dir, 'idedata.json')

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
    if not data then return false end

    -- Cache the project workspace root path cleanly
    local project_root = vim.g.platformioRootDir or vim.uv.cwd() or '.'
    local norm_project_root = vim.fs.normalize(project_root) or ''

    local norm = function(p) return vim.fs.normalize(p) or '' end

    -- 1. HIGH-PERFORMANCE LIST MAPPER: Optimized for raw strings (Flags & Defines)
    local map_list = function(list)
      local res = {}
      for _, v in ipairs(list or {}) do
        -- Direct assignment is faster than string.format('%s', v) in LuaJIT
        table.insert(res, v)
      end
      return res
    end

    -- Sort final mapping tokens by path length descending to guarantee longest match branches slice first
    -- table.sort(discovered_roots, function(a, b)
    --   if type(a) == "string" and type(b) == "string" then
    --     return #a > #b
    --   end
    --   return false
    -- end)

    -- 2. RIGID WORKSPACE INCLUDE PATH SORTER (Zero Naming Assumptions)
    local map_includes = function(list)
      local res = {}
      for _, v in ipairs(list or {}) do
        local clean_path = norm(v)
        if clean_path ~= "" then

          -- DETERMINISTIC RULE LAYER:
          -- Check if the include path physically initiates inside your active project directory tree
          local is_under_project = clean_path:sub(1, #norm_project_root) == norm_project_root

          -- Check if it belongs to the temporary downloaded vendor packages registry folder
          local is_managed_lib = clean_path:match("%.pio/libdeps")

          -- If it's outside your project repo, or inside the downloaded library cache, it's third-party!
          local prefix = (not is_under_project or is_managed_lib) and "-isystem" or "-I"

          -- Direct concatenation optimization
          table.insert(res, prefix .. clean_path)
        end
      end
      return res
    end

    -- 3. Base Paths & Compilers
    meta.cc_path = norm(data.cc_path)
    meta.cxx_path = norm(data.cxx_path)
    meta.gdb_path = norm(data.gdb_path)
    pcall(M.get_sysroot_triplet, meta.cxx_path)

    -- 4. Flags & Defines
    meta.cc_flags = map_list(data.cc_flags)
    meta.cxx_flags = map_list(data.cxx_flags)
    meta.defines = map_list(data.defines)

    -- 5. Includes (Completely automated and isolated)
    local inc = data.includes or {}
    meta.includes_build = map_includes(inc.build)
    meta.includes_toolchain = map_includes(inc.toolchain)
    meta.includes_compatlib = map_includes(inc.compatlib)
    --

    -- --🟢  keep for later if to deal with cxx_flags
    -- if _G.metadata and type(_G.metadata.cxx_flags) == 'table' then
    --   local boiler = require('nvimpio.boilerplate')
    --   local pio_diag = require('nvimpio.clangd.diagnostic')
    --
    --   local flags_updated = false
    --
    --   -- Loop through every compiler flag supplied by idedata.json
    --   for _, flag in ipairs(_G.metadata.cxx_flags) do
    --     if type(flag) == 'string' then
    --       -- Rule A: It's an architecture machine directive flag (e.g., -mlongcalls)
    --       local is_machine_directive = flag:match('^%-m[%w%-]+')
    --
    --       -- Rule B: It's a heavy compiler loop/optimization tweak (e.g., -fno-tree-switch-conversion)
    --       local is_problematic_opt = flag:match('^%-fno%-tree%-') or flag:match('^%-fno%-jump%-')
    --
    --       if (is_machine_directive or is_problematic_opt) and not pio_diag.removed_flags[flag] then
    --         -- Permanently register the flag inside your plugin's dynamic databases
    --         pio_diag.removed_flags[flag] = true
    --         flags_updated = true
    --       end
    --     end
    --   end
    --
    --   -- Trigger your boilerplate writer to output the updated .clangd file to disk instantly
    --   if flags_updated and boiler.boilerplate_gen then
    --     pcall(boiler.boilerplate_gen, '.clangd', project_root)
    --
    --     -- Save the newly tracked flags down to your .filter.json file
    --     local filter_db_path = vim.fs.joinpath(project_root, '.filter.json')
    --     local f = io.open(filter_db_path, 'wb')
    --     if f then
    --       local payload = { codes = pio_diag.manual_blocked_codes, flags = pio_diag.removed_flags }
    --       f:write(require('nvimpio.utils.misc').jsonFormat(payload))
    --       f:close()
    --     end
    --   end
    -- end

    -- Secure the validation signature token right after creation succeeds
    local read_ok, fresh_checksum = misc.readFile(checksum_file)
    if read_ok and fresh_checksum ~= '' and fresh_checksum ~= meta.last_projectChecksum then OS.notify('checksum change ', 'info') end
    if read_ok and fresh_checksum ~= '' then meta.last_projectChecksum = fresh_checksum end

    vim.schedule(function()
      local boiler = require('nvimpio.boilerplate')
      if boiler and boiler.boilerplate_gen then
        pcall(boiler.boilerplate_gen, '.clangd', project_root, 'upkeep')
      end
    end)
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
      -- if (from ~= 'Meta active_env change: ')then
      -- cli
      require('nvimpio.pio.cli').buildCompileDB(from, active_env, function(is_successful)
        if is_successful then
          -- OS.notify('Database is ready. Proceeding with analysis...')
          -- clangd.getUnknownArgsCli(from)
        else
          OS.notify('Skipping next steps due to compilation database failure.', 'error')
        end
      end)

      -- else
      -- -- gui
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
      --     -- local argscmd = string.format('%s --compile-commands-dir=. --check=%s --log=error', clangdCmd, check_file)
      --     local argscmd = string.format('%s --compile-commands-dir=. --check=%s --query-driver=%s --log=error', clangdCmd, check_file, _G.metadata.query_driver)
      --     local dbcmd = string.format('pio run -t compiledb -e %s', active_env)
      --     -- M.run_sequence({ cmnds = { idecmd, dbcmd }, cb = cb, from = string.format('%s refresh ' , from) })
      --     M.run_sequence({ cmnds = { dbcmd, argscmd }, cb = cb, from = string.format('%s refresh ', from) })
      --   end, 'clangd')
      -- end
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
      else fire_callback(false); return end
    else
      OS.notify(from .. 'Skipping next steps due to compilation idedata failure.', 'error')
      fire_callback(false)
      print('out')
      return
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
  --   -- local argscmd = string.format('%s --compile-commands-dir=. --check=%s --log=error', clangdCmd, check_file)
  --   local argscmd = string.format('%s --compile-commands-dir=. --check=%s --query-driver=%s --log=error', clangdCmd, check_file, _G.metadata.query_driver)
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
    if entry.directory then entry.directory = vim.fs.normalizePath(entry.directory) end
    if entry.file then entry.file = vim.fs.normalizePath(entry.file) end
    if entry.arguments then entry.arguments = vim.fs.normalizeFlags(entry.arguments) end
    if entry.output then entry.output = vim.fs.normalizePath(entry.output) end

    if entry.command then
      -- Extract compiler and everything after it
      local compiler, args = entry.command:match("^%s*(%S+)(.*)")
      if compiler then
        local is_absolute = compiler:sub(1, 1) == '/' or compiler:match('^%a:')

        if not is_absolute then
          local short_name = compiler:match('([^/\\\\]+)$'):gsub('%.exe$', '')

          if path_map[short_name] then
            -- Use normalizePath on the new path
            local full_compiler_path = vim.fs.normalizePath(path_map[short_name])

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
-- local nvimpio = require('nvimpio')
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

  -- if not nvimpio.is_active then
  --   require('nvimpio.pio.metadata')
  -- end

  if callBack then
    vim.schedule(function()
      content = ''
      pio_buffer = ''
      clangd_extracted_args = {} -- Clear the collected flags table
      clangd_check_active = false -- Arm the parsing loop tracker

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
    OS.notify(fromMsg .. 'project init Done', "info")
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
      if require('nvimpio').nvimpio.is_active then _G.metadata.isBusy = true end
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
      require('nvimpio.clangd.control').getUnknownArgsCli(fromMsg)
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
          require('nvimpio.clangd.control').restart()
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
          require('nvimpio.clangd.control').restart()
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
          require('nvimpio.clangd.control').restart()
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
          require('nvimpio.clangd.control').restart()
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
        if success then require('nvimpio.clangd.control').getUnknownArgsCli('PIO lib+db: ') end
      end, 'PIO lib+db: ')
    end)
    if trm then trm:close() end
    M.cleanSequencer()
  elseif result == 'FAIL' then
    M.cleanSequencer()
  end
end
return M
