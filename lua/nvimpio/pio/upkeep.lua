---@class platformio.utils.pio
local M = {}

local misc = vim.misc

local boilerplate = require('nvimpio.boilerplate')
local boilerplate_gen = boilerplate.boilerplate_gen

local term = require('nvimpio.utils.term')

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
    if match then triplet = vim.misc.normalizePath(match) break
    end
  end

  -- Return nil if no compiler was found in the bin directory
  if not triplet then return nil end

  -- toolchain_root is the parent of the 'bin' folder
  local toolchain_root = vim.misc.normalizePath(vim.fn.fnamemodify(bin_path, ':h'))
  -- sysroot folder is expected to have the same name as the triplet
  local sysroot = vim.misc.normalizePath(toolchain_root .. '/' .. triplet)
  local query_driver = vim.misc.normalizePath(bin_path .. '/' .. triplet .. '-*')

  -- vim.misc.notify('triplet= ' .. triplet, "info")
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
function M.updateDefaultEnv()
  local path = vim.fn.getcwd() .. "/platformio.ini"
  local active_env = _G.metadata.active_env
  if not active_env or active_env == "" then return end

  _G.metadata.isBusy = true
  local ok, content = vim.misc.readFile(path)
  if not ok or not content then
    _G.metadata.isBusy = false
    return
  end

  local new_lines = {}
  local updated = false
  local in_platformio = false

  -- Process text and newline separately to maintain file integrity
  for text, newline in content:gmatch("([^\r\n]*)([\r\n]+)") do
    local is_header = text:match("^%s*%[([^%]]+)%]")

    if is_header == "platformio" then
      in_platformio = true
    elseif is_header then
      -- If leaving [platformio] without updating, insert it now
      if in_platformio and not updated then
        table.insert(new_lines, "default_envs = " .. active_env .. newline)
        updated = true
      end
      in_platformio = false
    end

    if in_platformio and text:match("^%s*default_envs%s*=") then
      table.insert(new_lines, "default_envs = " .. active_env .. newline)
      updated = true
    else
      -- Keep original text and original newline (preserves spacing)
      table.insert(new_lines, text .. newline)
    end
  end

  -- Fallback for missing sections
  if not updated then
    if in_platformio then
      table.insert(new_lines, "default_envs = " .. active_env .. "\n")
    else
      table.insert(new_lines, 1, "[platformio]\ndefault_envs = " .. active_env .. "\n\n")
    end
  end

  vim.misc.writeFile(path, table.concat(new_lines), {})
  vim.misc.notify("PIO reset default_envs: " .. active_env)
  _G.metadata.isBusy = false


  --#1 working robust but no space line(s) between sections
  -- local path = vim.fn.getcwd() .. "/platformio.ini"
  -- local active_env = _G.metadata.active_env
  -- if not active_env or active_env == "" then return end
  --
  -- -- 1. Read raw string via your uv.readFile
  -- local ok, content = vim.misc.readFile(path)
  -- if not ok then return end
  --
  -- local new_lines = {}
  -- local env_updated = false
  -- local in_platformio_section = false
  --
  -- -- 2. Process line by line with a State Machine
  -- -- This pattern handles \r\n and \n correctly without leaving phantom chars
  -- for line in (content .. "\n"):gmatch("([^\r\n]*)[\r\n]+") do
  --   local is_platformio_header = line:match("^%s*%[platformio%]")
  --   local is_other_header = line:match("^%s*%[") and not is_platformio_header
  --   local is_default_envs = line:match("^%s*default_envs%s*=")
  --
  --   -- Track if we are inside the [platformio] section
  --   if is_platformio_header then
  --     in_platformio_section = true
  --   elseif is_other_header then
  --     -- If we are leaving [platformio] and haven't updated yet, insert it now
  --     if in_platformio_section and not env_updated then
  --       table.insert(new_lines, "default_envs = " .. active_env)
  --       env_updated = true
  --     end
  --     in_platformio_section = false
  --   end
  --
  --   -- Update or keep the line
  --   if is_default_envs then
  --     table.insert(new_lines, "default_envs = " .. active_env)
  --     env_updated = true
  --   else
  --     table.insert(new_lines, line)
  --   end
  -- end
  --
  -- -- 3. Final Fallbacks
  -- if not env_updated then
  --   if in_platformio_section then
  --     -- We were in the section but hit the end of the file
  --     table.insert(new_lines, "default_envs = " .. active_env)
  --   else
  --     -- No [platformio] section existed at all
  --     table.insert(new_lines, 1, "[platformio]")
  --     table.insert(new_lines, 2, "default_envs = " .. active_env)
  --     table.insert(new_lines, 3, "")
  --   end
  -- end
  --
  -- -- 4. Reconstruct and write via your uv.writeFile
  -- -- Joining with \n is the most portable; Python/PIO will handle it on Windows.
  -- local final_content = table.concat(new_lines, "\n")
  --
  -- local write_ok, err = vim.misc.writeFile(path, final_content, {})
  -- if write_ok then
  --   -- print("🚀 PIO Sync: " .. active_env)
  --   vim.misc.notify("🚀 PIO Sync: " .. active_env, "info")
  -- else
  --   vim.misc.notify("PIO Sync Failed: " .. err, "error")
  -- end
-------------------------------------------------------------------------------
--#2 working not robust
  -- local path = vim.fn.getcwd() .. "/platformio.ini"
  -- local active_env = _G.metadata.active_env
  -- if not active_env or active_env == "" then return end
  --
  -- -- 1. Read raw string using your uv-based readFile
  -- local ok, content = vim.misc.readFile(path)
  -- if not ok or not content then return end
  --
  -- -- 2. Split into lines (handles both Windows \r\n and Linux \n)
  -- local lines = {}
  -- for line in content:gmatch("([^\r\n]*)\r?\n?") do
  --   table.insert(lines, line)
  -- end
  -- -- Note: gmatch often adds an extra empty line at the end, remove it if needed
  -- if lines[#lines] == "" then table.remove(lines) end
  --
  -- local found = false
  -- local platformio_index = -1
  --
  -- -- 3. Process the lines
  -- for i, line in ipairs(lines) do
  --   if line:match("^%s*%[platformio%]") then
  --     platformio_index = i
  --   end
  --
  --   if line:match("^%s*default_envs%s*=") then
  --     lines[i] = "default_envs = " .. active_env
  --     found = true
  --     break
  --   end
  -- end
  --
  -- -- 4. Injection logic if the key was missing
  -- if not found then
  --   if platformio_index ~= -1 then
  --     table.insert(lines, platformio_index + 1, "default_envs = " .. active_env)
  --   else
  --     table.insert(lines, 1, "[platformio]")
  --     table.insert(lines, 2, "default_envs = " .. active_env)
  --   end
  -- end
  --
  -- -- 5. Reconstruct and write using your uv-based writeFile
  -- -- We use \n for joining; PlatformIO/Python handles this fine on Windows
  -- local final_content = table.concat(lines, "\n")
  --
  -- local write_ok, err = vim.misc.writeFile(path, final_content, {})
  -- if write_ok then
  --   print("✅ Sync successful: default_envs = " .. active_env)
  -- else
  --   vim.misc.notify("Write failed: " .. err, "error")
  -- end
-------------------------------------------------------------------------------
end

--INFO:
-- Fast environment detection from platformio.ini file(no external calls)
-- stylua: ignore
--=============================================================================
function M.get_active__env(from)
  local msg = (type(from) == 'string' and from ~= '') and from or 'PIO: '
  local path

  for _, dir in ipairs({ vim.api.nvim_buf_get_name(0):match('(.*[/\\])'), (vim.uv.cwd() .. '/') }) do
    local tmp = dir .. 'platformio.ini'
    local filestat = vim.uv.fs_stat(tmp)
    if filestat and filestat.type == 'file' then
      path = vim.fs.normalize(tmp)
      break
    end
  end
  if not path or path == '' then return vim.misc.notify(msg .. 'platformio.ini not found or no [env] defined.', "error") end

  -- Read file content (returns string or nil)
  local ok, content = vim.misc.readFile(path)
  if not ok or not content then return vim.misc.notify(msg .. 'platformio.ini not found in ' .. path, "warn") end

  local default_envs_raw = ''
  local default_envs = nil
  local valid_envs = {}
  local in_platformio_block = false

  -- Iterate lines from the content string
  for line in vim.gsplit(content, '\n') do
    -- Section Detection: [section_name]
    local section = line:match('^%s*%[(.+)%]%s*$')
    if section then
      in_platformio_block = (section == 'platformio')
      local env_name = section:match('^env:(.+)')
      if env_name then
        if not default_envs then default_envs = env_name end
        valid_envs[env_name] = true
      end
    end

    -- Collect the default_envs string from [platformio] block
    if in_platformio_block then
      local def = line:match('^%s*default_envs%s*=%s*(.+)')
      if def then default_envs_raw = def end
    end
  end

  -- Validation: Find the first default_env that actually exists as a block [env:]
  if default_envs_raw ~= '' then
    if default_envs then vim.misc.notify(default_envs, "info")end
    for env_name in default_envs_raw:gmatch('([^%s,]+)') do
      if valid_envs[env_name] then default_envs = env_name end
    end
  end

  -- if _G.metadata.default_envs[1] ~= nil and _G.metadata.active_env == _G.metadata.default_envs[1] then
  --   _G.metadata.active_env = default_envs
  --   M.updateDefaultEnv()
  -- end

  if (_G.metadata.active_env ~= default_envs)then
    _G.metadata.active_env = default_envs
    M.updateDefaultEnv()
  end
  -- Fallback to the very first [env:...] block found in the file
  return default_envs
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
  local build_dir = vim.misc.joinPath(vim.uv.cwd(), '.pio', 'build')
  local build_env_dir = vim.misc.joinPath(build_dir, active_env)
  local checksum_file = vim.misc.joinPath(build_dir, 'project.checksum')
  local idedata_file = vim.misc.joinPath(build_env_dir, 'idedata.json')

  --INFO:
  --INTERNAL PROCESSOR: Applies parsed data to _G.metadata
  ---------------------------------------------------------
  local function apply_metadata(data, checksum)
    if not data then return false end

    local norm = function(p) return vim.misc.normalizePath(p) or '' end

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
    vim.misc.notify(msg .. 'Initializing project metadata...', "info")
    vim.system({ 'pio', 'run', '-t', 'idedata', '-e', active_env, '-s' }, { text = true }, function(obj)
      vim.schedule(function()
        if obj.code == 0 then
          vim.misc.notify(msg .. 'Initializing project metadata success.', "info")
          M.fetch_metadata(callback, active_env, from, attempts - 1) -- Recursive call after files created
        else
          vim.misc.notify(msg .. 'Initialization failed. Build project manually.', "error")
        end
      end)
    end)
    return true
  end

  ---------------------------------------------------------
  -- STEP 1: Fast Checksum Check (project.checksum and idedata.json)
  ---------------------------------------------------------
  local ok, current_checksum = vim.misc.readFile(checksum_file)
  if ok and (type(current_checksum) == 'string' and current_checksum ~= '') then
    if current_checksum == meta.last_projectChecksum then
      vim.misc.notify(msg .. 'Metadata synced with cache', "info")
      -- if callback then callback() end
      if callback then vim.schedule(callback) end
      return true
    end -- Already updated

    -- STEP 2: Cache Path (idedata.json exists and checksum changed)
    local idok, content = vim.misc.readFile(idedata_file)
    if idok and (type(content) == 'string' and content ~= '') then
      local cok, decoded = pcall(vim.json.decode, content)

      local formated = vim.misc.jsonFormat(decoded)
      local file = vim.misc.joinPath(vim.uv.cwd(), 'idedata.json')
      vim.misc.writeFile(file, formated, {})

      if cok and apply_metadata(decoded, current_checksum) then
        local metadata = require('nvimpio.pio.metadata')
        metadata.save_project_config(msg)
        vim.misc.notify(msg .. 'Metadata synced from cache', "info")
        -- if callback then vim.schedule(callback) end

        if type(callback) == "function" then
          vim.schedule(callback)
        else
          -- If it's not a function, just do nothing or print a debug message
          print(msg .." Debug; callback was " .. type(callback))
        end

        return true
      end
    -- else
    end
  -- else
  end
  ---------------------------------------------------------
  -- STEP 3: Auto-Initialize (If files project.checksum and idedata.json are missing)
  ---------------------------------------------------------
  buildIdedata()

  ---------------------------------------------------------
  -- STEP 4: Standard CLI Fallback (The Slow Path)
  ---------------------------------------------------------
  -- vim.misc.notify(msg .. 'Metadata sync ...', "info")
  -- vim.system({ 'pio', 'project', 'metadata', '-e', active_env, '--json-output' }, { text = true }, function(obj)
  --   vim.schedule(function()
  --     if obj.code ~= 0 then
  --       if attempts > 0 then
  --         vim.defer_fn(function() M.fetch_metadata(attempts - 1, env) end, 500)
  --         return
  --       end
  --       return vim.misc.notify(msg .. 'Metadata Error: ' .. (obj.stderr or 'Unknown'), "warn")
  --     end
  --
  --     local ook, raw_data = pcall(vim.json.decode, obj.stdout or '')
  --     local _, data = next(raw_data or {})
  --
  --     if ook and apply_metadata(data, current_checksum) then
  --       vim.misc.notify(msg .. 'Metadata synced from CLI', "info")
  --       if callback then vim.schedule(callback) end
  --     else
  --       vim.misc.notify(msg .. 'Failed to parse metadata output', "warn")
  --     end
  --   end)
  -- end)
end

-- INFO:
-- =============================================================================
-- Get project configuration
-- =============================================================================
-- stylua: ignore
function M.fetch_config(on_done, from)
  local msg = (type(from) == 'string' and from ~= '') and from or 'PIO: '
  local meta = _G.metadata
  local home = (os.getenv('HOME') or os.getenv('USERPROFILE') or ''):gsub('[\\/]+$', '')

  local active_env
  vim.system({ 'pio', 'project', 'config', '--json-output' }, { text = true }, function(obj)
    vim.schedule(function()
      -- 1. Check Execution
      if obj.code ~= 0 then
        local errmsg = obj.code == 127 and "'pio' not found" or (obj.stderr or 'Unknown Error')
        return vim.misc.notify(msg .. 'Config Error: ' .. errmsg, "error")
      end

      -- 2. Decode JSON safely
      local ok, decoded = pcall(vim.json.decode, obj.stdout or '')
      if not ok or type(decoded) ~= 'table' then
        return vim.misc.notify(msg .. 'Failed to decode config JSON', "error")
      end

      local formated = vim.misc.jsonFormat(decoded)
      local file = vim.misc.joinPath(vim.uv.cwd(), 'config.json')
      vim.misc.writeFile(file, formated, {})

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
      M.updateDefaultEnv()

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
          val = os.getenv(item.env) or (home .. item.sub)
        end
        -- Expand variables and Normalize
        if type(val) == 'string' then
          val = val:gsub('%%${platformio.core_dir}', meta.core_dir or '')
          meta[item.key] = vim.misc.normalizePath(val)
        end
      end

      -- if active_env then
      --   vim.misc.notify(msg .. 'active_env= ' .. active_env, "info")
      -- end
      -- 6. Trigger next step
      if meta.active_env ~= '' then
        vim.misc.notify(msg .. 'Config sync successful', "info")
      else
        vim.misc.notify(msg .. 'No [env:] found. Please add a board.', "error")
      end

      if on_done then
        vim.schedule(function() on_done(active_env) end)
      end
    end)
  end)
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
    local jok, formatted = pcall(vim.misc.jsonFormat, data)
    -- local jok, formatted = pcall(M.pretty_print, data)
    if not jok then
      print('Formatting failed: ' .. formatted)
      return
    end

    local wk, err = vim.misc.writeFile(filename, formatted, { overwrite = true, mkdir = true })
    if not wk then print(err) end

    local end_time = vim.loop.hrtime()
    local duration = (end_time - start_time) / 1e6
    vim.misc.notify(string.format('compiledb: paths fixed in %.2fms', duration), "info")
    vim.clangd.restart()
  end
  _G.metadata.isBusy = false
end


-- INFO:
--configuration for running sequential commands on ToggleTerminal
-- stylua: ignore
-- =============================================================================
local callBack = nil
local pio_buffer = '' -- Persistent stream buffer

-- INFO: ToggleTerminal commands stdout filter
-- stylua: ignore
-- =============================================================================
function M.stdoutcallback(_, _, data)
  if not data or #data == 0 then return end

  -- 1. Correctly handle Neovim's data chunks
  -- data[1] is the continuation of the previous chunk
  -- data[#data] is a partial line (no newline yet)

  if #data > 1 then
    -- Join the buffer with the first element and all middle elements
    --(everything except the last partial line)
    local content = pio_buffer .. table.concat(data, "", 1, #data - 1)
    pio_buffer = data[#data] -- Save the new partial line

    -- 2. Search for the status in the complete chunk
    --change the pattern to: content:match('_CMMNDS_:([^%s]+)')
    --this will grab everything until the next space or newline.
    local status = content:match('_CMMNDS_:(%a+)') -- pattern %a+ only matches letters (A-Z)

    if status and callBack then vim.schedule(function() callBack(status) end) end
  else
    -- Only one element (no newline yet;) means the line isn't finished yet
    pio_buffer = pio_buffer .. data[1]
  end

  -- 3. Safety Trim (Prevents memory leaks if no newline ever comes)
  if #pio_buffer > 5000 then pio_buffer = pio_buffer:sub(-2500) end
end

-- =============================================================================
local commandPassed = 0
M.queue = {}

local nvimpio = require('nvimpio')

-- INFO: commands sequencer
-- stylua: ignore
-- =============================================================================
M.run_sequence = function(tasks)
  M.queue = {}
  local commands = tasks.cmnds

  local done = ' && echo _CMMNDS_":"DONE'
  local pass = ' && echo _CMMNDS_":"PASS'
  local fail = ' || echo _CMMNDS_":"FAIL'
  --
  for i, cmd in ipairs(commands) do
    local full_cmd = ''
    if i == #commands then full_cmd = cmd .. done .. fail
    else full_cmd = cmd .. pass .. fail end
    table.insert(M.queue, full_cmd)
  end


  callBack = tasks.cb -- 1. Save the callback in a local variable

  commandPassed = 1
  pio_buffer = ''

  if not nvimpio.is_active then
    require('nvimpio.pio.metadata')
  end
  _G.metadata.isBusy = false
  term.stdout_callback = M.stdoutcallback
  vim.schedule(function() if callBack then callBack('INIT') end end)
end

local trm
local win_id
------------------------------------------------------
-- Handle after pioinit execution
-- =============================================================================
-- stylua: ignore
function M.cleanup_pio_session()
  vim.misc.deleteFile(vim.fs.joinpath(vim.g.platformioRootDir, '.ccls'))
  _G.metadata.isBusy = false
  M.queue = {}
  if win_id then vim.misc.closeMessage(win_id) end
  win_id = nil
  term.stdout_callback = nil -- Careful: make sure this doesn't break other terms
  if trm then trm:close() end
end

-- stylua: ignore
function M.handlePioinitDb(result, board)
  if result == 'INIT' then
    boilerplate.core_dir = _G.metadata.core_dir
    boilerplate_gen([[platformio.ini]], vim.g.platformioRootDir)
    boilerplate_gen([[.clang-format]], vim.g.platformioRootDir)
    -- boilerplate_gen([[.clangd]], vim.fs.joinpath(vim.env.XDG_CONFIG_HOME, 'clangd'), 'config.yaml')

    win_id = vim.misc.showMessage('************ Project Initializing ************')
    if #M.queue > 0 then
      _G.metadata.isBusy = true
      trm = term.ToggleTerminal(table.remove(M.queue, 1), 'float')
    end
  elseif result == 'PASS' then
    if commandPassed == 1 then
      vim.misc.notify('PIO init+db:  pass ' .. commandPassed, "info")
      local active_env = M.get_active__env('PIO init+db: ')
      if not active_env or (active_env == board) then
        local pio_refresh = require('nvimpio.pio.control').pio_refresh
        pio_refresh(function()

        -- 1. Ensure the plugin is active (Safe to call even if already active)
        if not nvimpio.is_active then
          nvimpio.setup()
        end

          -- local flags = filter_bad_args_with_clangd(_G.metadata.cxx_flags)
          --
          -- local include_flags = table.concat(vim.tbl_map(function(item)
          --   return '"' .. item .. '"'
          -- end, flags), ", ")
          -- print(include_flags)
          -- fix_clangd_args()
          commandPassed = commandPassed + 1
          if #M.queue > 0 then term.ToggleTerminal(table.remove(M.queue, 1), 'float') end
        end, 'PIO init+db: ')
      else
        M.cleanup_pio_session()
      end
    -- elseif commandPassed == 2 then -- if you sned more than 2 commands you need this
    end
  elseif result == 'DONE' then -- result of the last command
    vim.schedule(function()
      boilerplate.core_dir = _G.metadata.core_dir
      vim.misc.notify('PIO init+db:  pass ' .. commandPassed, "info")
      vim.misc.notify('PIO init+db: Done', "info")
      vim.misc.gitignore_lsp_configs('compile_commands.json')
      vim.clangd.getUnknownArgs()
    end)
    M.cleanup_pio_session()
  elseif result == 'FAIL' then
    M.cleanup_pio_session()
  end
end


----------------------------------------------------
-- Handle after pioinit execution
-- stylua: ignore
function M.handlePioinit(result)
  if result == 'INIT' then

    boilerplate.core_dir = _G.metadata.core_dir
    boilerplate_gen([[platformio.ini]], vim.g.platformioRootDir)

    boilerplate_gen([[.clang-format]], vim.g.platformioRootDir)

    boilerplate_gen([[.clangd]], vim.g.platformioRootDir)
    -- boilerplate_gen([[.clangd]], _G.metadata.core_dir)
    -- boilerplate_gen([[.clangd]], vim.fs.joinpath(vim.env.XDG_CONFIG_HOME, 'clangd'), 'config.yaml')

    win_id = vim.misc.showMessage('************ Project Initializing ************')
    if #M.queue > 0 then
      trm = term.ToggleTerminal(table.remove(M.queue, 1), 'float')
      _G.metadata.isBusy = true
    end
  elseif result == 'DONE' then -- result of the last command
    vim.schedule(function()
      vim.misc.notify('PIO init:  pass ' .. commandPassed, "info")
      vim.misc.notify('PIO init: Done', "info")
      vim.misc.gitignore_lsp_configs('compile_commands.json')

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
      -- vim.api.nvim_chan_send(trm.job_id, clean_msg)

      local pio_refresh = require('nvimpio.pio.control').pio_refresh
      pio_refresh(function()
        boilerplate_gen([[.clangd]], _G.metadata.core_dir)
        vim.misc.closeMessage(win_id)
        vim.clangd.restart()
        -- term.ToggleTerminal('echo "************ project Initialization success ************"', 'float')
      end, 'PIO init: ')
    end)
    M.cleanup_pio_session()
  elseif result == 'FAIL' then
    M.cleanup_pio_session()
  end
end

------------------------------------------------------
-- Handle after piolib execution
-- =============================================================================
-- stylua: ignore
function M.handlePiolib(result)
  if result == 'INIT' then
    if #M.queue > 0 then
      trm = term.ToggleTerminal(table.remove(M.queue, 1), 'float')
      _G.metadata.isBusy = true
    end
  elseif result == 'DONE' then -- result of the only and the last command
    vim.misc.notify('PIO lib:  pass ' .. commandPassed, "info")
    vim.misc.notify('PIO lib: Done', "info")
    commandPassed = commandPassed + 1
    M.queue = {}
    term.stdout_callback = nil
    _G.metadata.isBusy = false
  elseif result == 'FAIL' then
    M.queue = {}
    term.stdout_callback = nil
    _G.metadata.isBusy = false
  end
end

------------------------------------------------------
-- =============================================================================
-- stylua: ignore
function M.handlePiodb(target, result)
  if result == 'INIT' then
    if #M.queue > 0 then
      trm = term.ToggleTerminal(table.remove(M.queue, 1), 'float')
      _G.metadata.isBusy = true
    end
  elseif result == 'DONE' then -- result of the only and the last command
    vim.misc.notify('PIO db:  pass ' .. commandPassed, "info")
    vim.misc.notify('PIO db: Done', "info")
    commandPassed = commandPassed + 1
    target.isBusy = false
    M.queue = {}
    term.stdout_callback = nil
    _G.metadata.isBusy = false
  elseif result == 'FAIL' then
    target.isBusy = false
    M.queue = {}
    term.stdout_callback = nil
    _G.metadata.isBusy = false
  end
end

return M
