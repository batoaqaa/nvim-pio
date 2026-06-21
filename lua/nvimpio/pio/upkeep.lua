local M = {}

local misc = require('nvimpio.utils.misc')

-- stylua: ignore start
-- INFO:
-- =============================================================================
-- UNIVERSAL TOOLCHAIN DETECTION
-- =============================================================================
function M.get_sysroot_triplet(cc_compiler)
  local bin_path = vim.fs.normalize(vim.fn.fnamemodify(cc_compiler, ':h'))
  if not bin_path or vim.fn.isdirectory(bin_path) == 0 then return nil end
  if not bin_path or vim.fn.isdirectory(bin_path) == 0 then return nil end

  -- 1. toolchain_root is the parent of the 'bin' folder
  local toolchain_root = vim.fs.normalize(vim.fn.fnamemodify(bin_path, ':h'))


  -- Strategy A: Check if a folder named after the compiler target exists inside toolchain_root
  local fname = vim.fn.fnamemodify(cc_compiler, ':t:r') -- e.g., "xtensa-esp32s3-elf-g++"
  local compiler_prefix = string.match(fname, "^([^-]+-[^-]+-[^-]+)") -- e.g., "xtensa-esp32s3-elf"

  local triplet = nil
  if compiler_prefix and vim.fn.isdirectory(toolchain_root .. "/" .. compiler_prefix) == 1 then
    triplet = compiler_prefix
  end

  -- Strategy B: Absolute dynamic lookup matching sibling compiler names
  if not triplet then
    local files = vim.fn.readdir(bin_path)
    for _, name in ipairs(files) do
      local match = vim.fn.fnamemodify(name, ':t:r') -- e.g., "xtensa-esp32-elf-gcc"
      if match then
        local sibling_triplet = string.match(match, "^([^-]+-[^-]+-[^-]+)")
        if sibling_triplet and vim.fn.isdirectory(toolchain_root .. "/" .. sibling_triplet) == 1 then
          triplet = sibling_triplet
          break
        end
      end
    end
  end

  -- Strategy C: Fallback to the layout where the folder mirrors the package name wrapper
  if not triplet then
    local folder_name = vim.fn.fnamemodify(toolchain_root, ':t') -- e.g., "toolchain-xtensa-esp-elf"
    local package_prefix = string.match(folder_name, "^toolchain%-(.+)$")

    if package_prefix and vim.fn.isdirectory(toolchain_root .. "/" .. package_prefix) == 1 then
      triplet = package_prefix
    end
  end

  -- Strategy D: Absolute dynamic lookup (Scans the folder structure for standard header locations)
  if not triplet then
    local include_dirs = vim.fs.find('include', { path = toolchain_root, type = 'directory', limit = 3 })
    for _, inc_path in ipairs(include_dirs) do
      local parent_folder = vim.fn.fnamemodify(vim.fs.normalize(inc_path), ':h:t')
      if parent_folder:match('-elf$') then triplet = parent_folder; break; end
    end
  end
  -- if not triplet then return nil end

  -- local query_driver = vim.fs.normalize(bin_path .. '/*')
  -- local query_driver = vim.fs.normalize(toolchain_root .. '/**/' .. triplet .. '*')
  local query_driver = vim.fs.normalize(triplet .. '-*')

  _G.metadata.triplet = triplet
  _G.metadata.toolchain_root = toolchain_root
  _G.metadata.query_driver = query_driver

  -- sysroot folder is expected to have the same name as the triplet
  local sysroot = vim.fs.joinpath(toolchain_root, triplet)
  -- Check if sysroot folder actually exists on disk (Optional fallback validation)
  -- If it doesn't exist, we fall back to toolchain_root so your metadata never breaks!
  if vim.fn.isdirectory(sysroot) == 1 then _G.metadata.sysroot = sysroot
  else _G.metadata.sysroot = toolchain_root end

  -- 1. Essential: Normalize slashes to match the host system style
  local normalized_compiler = vim.fs.normalize(cc_compiler)
  local auto_defines = {}
  -- 2. Pass the arguments as an isolated Lua array table. 
  -- This completely shields the flags from PowerShell's parser!
  local obj = vim.system({ normalized_compiler, "-dM", "-E", "-x", "c++", "-" }, {
    stdin = "\n" -- Clean input stream data
  }):wait()
  -- 3. Check if the direct process returned data
  if obj.code == 0 and obj.stdout then
    -- Convert the raw stdout block into an array of lines
    local lines = vim.split(obj.stdout, "\n")
    for _, line in ipairs(lines) do
      local macro, value = line:match("^#define%s+([%w_]+)%s*(.*)")
      if macro then
        -- GENERIC INCLUSION RULES: Only capture clear target flags
        -- 1. Keeps short system targets like __ELF__ or __xtensa__
        local is_short_target = macro:match("^__[a-zA-Z0-9]+__$")
        -- 2. Keeps pure standard variables like __cplusplus
        local is_language_std = macro:match("^__cplusplus$")
        -- 3. Keeps clear, readable configuration tokens that do not use internal prefixes
        local is_clean_token  = not macro:match("^__")
        if is_short_target or is_language_std or is_clean_token then
          value = value:gsub("%s*//.*$", ""):gsub("\r$", ""):gsub("%s*$", "")
          if value == "" then table.insert(auto_defines, "-D" .. macro)
          else table.insert(auto_defines, "-D" .. macro .. "=" .. value) end
        end
      end
    end
    _G.metadata.auto_defines = auto_defines
  -- else
  --   print("Compiler process execution failed.")
  --   if obj.stderr and obj.stderr ~= "" then print("Error details: " .. obj.stderr) end
  end


  return {
    triplet = triplet,
    sysroot = _G.metadata.sysroot,
    toolchain_root = toolchain_root,
    query_driver = query_driver,
    auto_defines = auto_defines,
  }
end

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

  -- Gather ports dynamically using your unified scanner function helper
  local ports = M.get_connected_ports()
  if #ports == 0 then ports = { 'Auto Detect' } end

  -- Define the steps mapping sequence arrays (Expanded to 6 steps)
  local steps = {
    {
      p = ' [1/6] Select Targeted Serial Port ', c = ports,
      s = function(x) p_state.selected_port = x vim.g.platformio_selected_port = x end,
    },
    {
      p = ' [2/6] Select Upload Speed (Baud) ', c = speeds,
      s = function(x) p_state.upload_speed = x end,
    },
    {
      p = ' [3/6] Select Serial Monitor Speed ', c = speeds,
      s = function(x) p_state.monitor_speed = x end,
    },
    {
      p = ' [4/6] Set Monitor RTS Pin State ', c = { '0', '1' },
      s = function(x) p_state.monitor_rts = x end,
    },
    {
      p = ' [5/6] Set Monitor DTR Pin State ', c = { '0', '1' },
      s = function(x) p_state.monitor_dtr = x end,
    },
    {
      p = ' [6/6] Select Serial Monitor Filter ',
      c = { 'default (none)', 'direct', 'send_on_enter', 'direct, send_on_enter' },
      s = function(x) p_state.monitor_filters = x end,
    },
  }

  -- Defensive, Context-Aware File System Injector Engine
  local function inject_into_ini()
    local path = vim.fs.joinpath(vim.uv.cwd(), 'platformio.ini')
    if vim.fn.filereadable(path) ~= 1 then return end
    local raw_lines = vim.fn.readfile(path)
    _G.isBusy = true

    -- Build our fresh patches table dynamically based on user selections
    local patches = {}
    if p_state.selected_port and p_state.selected_port ~= 'Auto Detect' then
      table.insert(patches, 'upload_port = ' .. p_state.selected_port)
      table.insert(patches, 'monitor_port = ' .. p_state.selected_port)
    end
    if p_state.upload_speed  then table.insert(patches, 'upload_speed = ' .. p_state.upload_speed) end
    if p_state.monitor_speed then table.insert(patches, 'monitor_speed = ' .. p_state.monitor_speed) end
    if p_state.monitor_rts   then table.insert(patches, 'monitor_rts = ' .. p_state.monitor_rts) end
    if p_state.monitor_dtr   then table.insert(patches, 'monitor_dtr = ' .. p_state.monitor_dtr) end

    -- HERE IS THE PLACE: Inserted dynamically right after your pin states
    if p_state.monitor_filters and p_state.monitor_filters ~= 'default (none)' then
      table.insert(patches, 'monitor_filters = ' .. p_state.monitor_filters)
    end

    local hardware_keys = {
      upload_port = true, monitor_port = true, upload_speed = true,
      monitor_speed = true, monitor_filters = true, monitor_rts = true, monitor_dtr = true
    }

    -- Categorize the file structure line-by-line
    local structured_lines = {}
    local current_section = "pre_header"
    local env_section_exists = false

    for _, line in ipairs(raw_lines) do
      local trimmed = line:match("^%s*(.-)%s*$")
      local section_match = trimmed:match("^%s*%[%s*([^%]]+)%s*%]%s*$")

      if section_match then
        current_section = section_match:gsub("%s", "")
        if current_section == "env" then env_section_exists = true end
        table.insert(structured_lines, { type = "header", name = current_section, text = line })
      elseif trimmed:match("^[;#]") then
        table.insert(structured_lines, { type = "comment", section = current_section, text = line })
      elseif trimmed == "" then
        table.insert(structured_lines, { type = "empty", section = current_section, text = line })
      else
        local key_name = trimmed:match("^%s*([%w_]+)%s*=")
        if current_section == "env" and key_name and hardware_keys[key_name] then
          -- Skip historical port configurations to cleanly overwrite them
        else
          table.insert(structured_lines, { type = "property", section = current_section, text = line })
        end
      end
    end

    -- If [env] didn't exist at all, find [platformio] and insert the header structure
    if not env_section_exists then
      local insert_idx = #structured_lines + 1
      for idx, l in ipairs(structured_lines) do
        if l.type == "header" and l.name == "platformio" then
          insert_idx = idx + 1
          while structured_lines[insert_idx] and structured_lines[insert_idx].section == "platformio" do
            insert_idx = insert_idx + 1
          end
          break
        end
      end
      table.insert(structured_lines, insert_idx, { type = "header", name = "env", text = "[env]" })
    end

    -- Inject our new parameters directly underneath the [env] header entry row
    for idx, l in ipairs(structured_lines) do
      if l.type == "header" and l.name == "env" then
        for i = #patches, 1, -1 do
          table.insert(structured_lines, idx + 1, { type = "property", section = "env", text = patches[i] })
        end
        break
      end
    end

    -- Final Assembly: Enforce clean formatting and spacing rules
    local final_lines = {}
    local last_line_type = "empty"

    for _, l in ipairs(structured_lines) do
      if l.type == "header" and l.name ~= "platformio" and last_line_type ~= "empty" then
        if #final_lines > 0 and final_lines[#final_lines] ~= "" then
          table.insert(final_lines, "")
        end
      end

      if l.type == "empty" then
        if last_line_type ~= "empty" and last_line_type ~= "header" then
          table.insert(final_lines, l.text)
          last_line_type = "empty"
        end
      else
        table.insert(final_lines, l.text)
        last_line_type = l.type
      end
    end

    while #final_lines > 0 and final_lines[#final_lines]:match("^%s*$") do
      table.remove(final_lines)
    end

    vim.fn.writefile(final_lines, path)
    vim.schedule(function() vim.cmd('checktime') end)
    vim.defer_fn(function() _G.isBusy = false end, 500)
  end

  -- Linear Execution Wizard Runner Loop
  local function run(step_idx)
    if not steps[step_idx] then
      inject_into_ini()
      local msg = string.format(
        'Injected: Port: %s | Upload: %s baud | Filter: %s',
        p_state.selected_port or 'Auto',
        p_state.upload_speed or 'Ini',
        p_state.monitor_filters or 'None'
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

  run(1)
end

--=============================================================================
--INFO:get pio project metadata info
local fetch_metadata -- Forward declare the variable shell
local refreshBusy = false
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
    vim.schedule(function() if type(callback) == 'function' then callback(status) end end)
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
          -- If it's outside your projecto repo, or inside the downloaded library cache, it's third-party!
          -- Unlike -I, the -isystem flag requires a separator (space or =) in clangd configuration files to parse correctly.
          local prefix = (not is_under_project or is_managed_lib) and "-isystem " or "-I"
          -- local prefix = (not is_under_project or is_managed_lib) and "-I" or "-I"
          -- Direct concatenation optimization
          table.insert(res, prefix .. clean_path)
        end
      end
      return res
    end

    -- 3. Get PlatformIO project libdep includes paths
    local function get_libdeps_includes(root_path, board)
      if not root_path or not board then return {}, {} end

      local base_dir = vim.fs.joinpath(root_path, ".pio", "libdeps", board)
      if vim.fn.isdirectory(base_dir) == 0 then return {}, {} end

      local src_dirs = vim.fs.find("src", { path = base_dir, type = "directory", limit = math.huge })
      local flat_libs = {}
      local nested_libs = {}

      for _, src_path in ipairs(src_dirs) do
        local normalized_path = vim.fs.normalize(src_path)

        -- INSTANT GENERIC CHECK: Scan ONLY the first layer of the directory (no slow recursive loops)
        local is_nested = false
        local handle = vim.uv.fs_scandir(normalized_path)

        if handle then
          while true do
            local name, type_str = vim.uv.fs_scandir_next(handle)
            if not name then break end

            -- If it contains even one sub-folder, treat it as a nested library path
            if type_str == "directory" then is_nested = true break end
          end
        end

        -- Sort the paths into their perfect configuration streams
        if is_nested then table.insert(nested_libs, "-I" .. normalized_path)
        else table.insert(flat_libs, "-isystem " .. normalized_path) end
      end

      -- return flat_libs, nested_libs
      return nested_libs
    end

    -- 4. Base Paths & Compilers
    meta.cc_path = norm(data.cc_path)
    meta.cxx_path = norm(data.cxx_path)
    meta.gdb_path = norm(data.gdb_path)
    -- M.get_sysroot_triplet(meta.cxx_path)
    pcall(M.get_sysroot_triplet, meta.cxx_path)

    -- 5. Flags & Defines
    meta.cc_flags = map_list(data.cc_flags)
    meta.cxx_flags = map_list(data.cxx_flags)
    meta.defines = map_list(data.defines)

    -- 6. Includes (Completely automated and isolated)
    local inc = data.includes or {}
    meta.includes_build = map_includes(inc.build)
    meta.includes_toolchain = map_includes(inc.toolchain)
    meta.includes_compatlib = map_includes(inc.compatlib)
    -- meta.includes_libdeps = map_includes(get_pio_includes(project_root, active_env))
    meta.includes_libdeps = get_libdeps_includes(project_root, active_env)
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
    if read_ok and fresh_checksum ~= '' and fresh_checksum ~= meta.last_projectChecksum then
      meta.last_projectChecksum = fresh_checksum
      OS.notify('checksum change ', 'info')
    end

    vim.schedule(function()
      local boiler = require('nvimpio.boilerplate')
      if boiler and boiler.boilerplate_gen then
        -- pcall(boiler.boilerplate_gen, '.clangd', project_root, 'upkeep')
        pcall(boiler.boilerplate_gen, '.clangd', 'upkeep')
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
      if (from == 'Meta active_env change: ')then
      -- cli
        require('nvimpio.pio.cli').buildCompileDB(from, active_env, function(is_successful)
          if is_successful then
            -- OS.notify('Database is ready. Proceeding with analysis...')
            -- clangd.getUnknownArgsCli(from)
          else
            OS.notify('Skipping next steps due to compilation database failure.', 'error')
          end
        end)
      else
      -- gui
        if attempts > 0 then
          local cb = function(status)
            require('nvimpio.device.parser').handlePioDB(status, active_env, function(success)
              -- if success then do end end
              if success then do end end
            end)
          end

          local dbcmd = string.format('pio run -t compiledb -e %s', active_env)
          require('nvimpio.device.parser').run_sequence({ cmnds = { dbcmd }, cb = cb, from = string.format('%s refresh ' , from) })
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
          --   local dbcmd = string.format('pio run -t compiledb -e %s', active_env)
          --   -- require('nvimpio.device.parser')run_sequence({ cmnds = { idecmd, dbcmd }, cb = cb, from = string.format('%s refresh ' , from) })
          --   require('nvimpio.device.parser').run_sequence({ cmnds = { dbcmd, argscmd }, cb = cb, from = string.format('%s refresh ', from) })
          -- end, 'clangd')
        end
      end

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
  -- require('nvimpio.pio.cli').buildIdedata(from, active_env, function(is_successful)
  --   if is_successful then
  --     -- OS.notify(from .. 'Idedata is ready. Proceeding with analysis...')
  --       -- Execute recursive check loop to accurately verify and load newly compiled files
  --     if attempts > 0 then fetch_metadata(callback, active_env, from, attempts - 1)
  --     else fire_callback(false); return end
  --   else
  --     OS.notify(from .. 'Skipping next steps due to compilation idedata failure.', 'error')
  --     fire_callback(false)
  --     print('out')
  --     return
  --   end
  -- end)

  -- gui
  local cb = function(status)
    require('nvimpio.device.parser').handleIdedata(status, active_env, function(success)
      if success then
        OS.notify(string.format('%s Initializing project metadata success for %s.', from, active_env), 'info')
        -- Execute recursive check loop to accurately verify and load newly compiled files
        if attempts > 0 then fetch_metadata(callback, active_env, from, attempts - 1)
        else fire_callback(false) end
      else
        OS.notify(from .. 'Build Failed', 'error')
        fire_callback(false)
      end
    end)
  end
  local idecmd = string.format('pio run -t idedata -e %s -s', active_env)
  local dbcmd = string.format('pio run -t compiledb -e %s', active_env)
  require('nvimpio.device.parser').run_sequence({ cmnds = { idecmd, dbcmd }, cb = cb, from = string.format('%s refresh ' , from) })
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
  --   require('nvimpio.device.parser').run_sequence({ cmnds = { idecmd, dbcmd, argscmd }, cb = cb, from = string.format('%s refresh ', from) })
  -- end, 'clangd')
end


-------------------------------------------------------------------------------
--INFO:
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
    if entry.directory then entry.directory = vim.fs.normalize(entry.directory) end
    if entry.file then entry.file = vim.fs.normalize(entry.file) end
    if entry.arguments then entry.arguments = vim.fs.normalizeFlags(entry.arguments) end
    if entry.output then entry.output = vim.fs.normalize(entry.output) end

    if entry.command then
      -- Extract compiler and everything after it
      local compiler, args = entry.command:match("^%s*(%S+)(.*)")
      if compiler then
        local is_absolute = compiler:sub(1, 1) == '/' or compiler:match('^%a:')

        if not is_absolute then
          local short_name = compiler:match('([^/\\\\]+)$'):gsub('%.exe$', '')

          if path_map[short_name] then
            -- Use normalizePath on the new path
            local full_compiler_path = vim.fs.normalize(path_map[short_name])

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
  _G.isBusy = false
end
return M
