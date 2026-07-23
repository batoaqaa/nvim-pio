-- stylua: ignore start
local M = {}

local boilerplate = require('nvimpio.boilerplate')
local boilerplate_gen = boilerplate.boilerplate_gen
local diagnosticClangd = require('nvimpio.clangd.diagnostic')
local has_pio_diag, pio_diag = pcall(require, 'nvimpio.clangd.diagnostic')

----------------------------------------------------------------------------------------
-- INFO: configure clangd lsp server
-----------------------------------------------------------------------------------------
function M.clangdIntall(callback, package_name)
  package_name = package_name or 'clangd'

  -- Modern Neovim 0.11+ way to ensure Mason binaries are found
  local bin_name = OS.is_win and package_name .. '.cmd' or package_name
  local mason_bin = vim.fs.joinpath(OS.data_dir, 'mason', 'bin')
  local mason_exe = vim.fs.joinpath(mason_bin, bin_name)

  local registry = require('mason-registry')

  local check_count = 0
  local max_checks = 60 -- 60 * 1000ms = 60 seconds timeout (installs take time)

  local function poll()
    registry.refresh(function()
      local pkg = registry.get_package(package_name)

      -- 1. SUCCESS: Installed and file is ready
      if pkg:is_installed() and vim.fn.executable(mason_exe) == 1 then
        if check_count > 0 then
          vim.schedule(function()
            OS.notify(package_name .. ' installed', 'info')
          end)
        end
        callback(mason_exe)
        return
      end

      -- 2. TRIGGER: Not installed and NOT installing? Start the install.
      if not pkg:is_installed() and not pkg:is_installing() then
        -- vim.schedule(function()
          OS.notify('Mason: Auto-installing ' .. package_name .. ' ...', 'info')
          pkg:install()
          -- After triggering install, we continue to poll to wait for completion
        -- end)
      end

      -- 3. WAIT: If we haven't timed out, check again in 1 second
      if check_count < max_checks then
        check_count = check_count + 1
        -- Visual feedback for long installs
        if check_count % 5 == 0 then
          vim.schedule(function()
            OS.notify('Mason: Waiting for ' .. package_name .. ' installation... ' .. check_count .. 'sec')
          end)
        end
        vim.defer_fn(poll, 1000)
        return
      end

      -- 4. FAIL/TIMEOUT: Return system fallback
      vim.notify('Mason: ' .. package_name .. ' setup timed out. Using system fallback.', vim.log.levels.WARN)
      callback(package_name)
    end)
  end
  poll()
end

-- INFO: set_clang_format_style()
--------------------------------------------------------------------------------
function M.setFormatStyle()
  local styles = { 'LLVM', 'Google', 'Chromium', 'Mozilla', 'WebKit', 'Microsoft', 'GNU' }
  -- vim.cmd('stopinsert')
  vim.ui.select(styles, {
    prompt = 'Select Clang-Format base style:',
  }, function(choice)
    if not choice then return end
    M.clangdIntall(function(clangdCmd)
      -- -- gui using terminal for setting clang-format style
      -- local cmd = string.format('%s --style=%s --dump-config > .clang-format', clangdCmd, choice:lower())
      -- local parser = require('nvimpio.device.parser')
      -- parser.run_sequence({
      --   cmnds = { cmd },
      --   cb = parser.clangFormat,
      --   from = 'clangdIntall',
      -- })

      -- cli using hidden system asynchronous command for setting clang-format style
      local cmd = { clangdCmd, string.format('--style=%s', choice:lower()), '--dump-config' }
      --1 -- Synchronously wait for completion (avoids callbacks and scheduling)
      --1 local obj = vim.system(cmd, { text = true }):wait()
      --2 -- asynchronous way
      vim.system(cmd, { text = true }, function(obj) -- 2
        -- Use vim.schedule to perform UI tasks/API calls on the main thread
        vim.schedule(function() -- 2
          if obj.code == 0 and obj.stdout and obj.stdout ~= '' then
            local file = io.open('.clang-format', 'w')
            if file then
              file:write(obj.stdout)
              file:close()

              OS.notify('Created .clang-format (' .. choice .. ')', OS.debug)
              M.restart()
              OS.notify('LSP Reloaded: Using ' .. choice .. ' style.', OS.debug)
            else
              OS.notify('Failed to save .clang-format to disk (Permission error?)', 'error')
            end
          else
            -- If the tool failed, print out its actual stderr reason
            local err_msg = (obj.stderr and obj.stderr ~= '') and obj.stderr or 'Unknown configuration failure'
            OS.notify('Failed to generate .clang-format. Error: ' .. err_msg, 'error')
          end
        end) -- 2
      end) -- 2
    end, 'clang-format')
  end)
end

-- INFO: get_clangd_unknown_args
--------------------------------------------------------------------------------
---@param from string
function M.getUnknownArgsCli(from)
  from = (type(from) == 'string' and from ~= '') and from or 'PIO: '

  -- Create a fast lookup set of all valid extensions
  -- 1. FIND: Grab the first .cpp or .c file in /src
  local extensions = { cc = true, cxx = true, ccm = true, ixx = true, cppm = true, mxx = true,
                        i = true, ii = true, m = true, mm = true, cuh = true, cpp = true,
                        --
                        c = true, cu = true, inl = true, tcc = true, C = true,
  }
  local getMainfile = function ()
    return vim.fs.find(function(name)
        -- Extract the text after the very last dot
        local ext = name:match("%.([^.]+)$")
        -- Return true if the extension exists in our target lookup set
        return extensions[ext] == true
    end, { limit = 1, path = OS.project_dir .. "/src" })[1]
  end
  local check_file = getMainfile()

  if not check_file then
    boilerplate_gen(_G.metadata.envs[_G.metadata.active_env].framework)
    check_file = getMainfile()
  end

  -- 2. SCAN: Run clangd (it will see all errors because .clangd is now empty)
  M.clangdIntall(function(clangdCmd)
    -- local output_chunks = {}
    -- local clangd_cmd = { "clangd", "--compile-commands-dir=.", "--check=" .. check_file, "--log=error" }
    -- -- 3. Run in a completely isolated background thread pool
    -- vim.system(clangd_cmd, {
    --   text = true,
    --   -- ⏳ THE BULLETPROOF TIMEOUT: Native OS process monitoring.
    --   -- Sets a generous maximum hard cutoff time limit (e.g., 60 seconds)
    --   -- to comfortably accommodate slow platform installations or library downloads.
    --   timeout = 60000,
    --   stdout = function(_, data) if data then table.insert(output_chunks, data) end end,
    --   stderr = function(_, data) if data then table.insert(output_chunks, data) end end,
    -- }, function(obj)
    --   vim.schedule(function()
    --   end)
    -- end)

    OS.notify('getting unknown arguments for file ' .. check_file, OS.debug)
    --------------------------------------------------------------------------------
    local cmd = { clangdCmd, '--compile-commands-dir=.', '--check=' .. check_file, '--log=error' }
    vim.system(cmd, { text = true }, function(obj)
      vim.schedule(function()
        local output = (obj.stdout or '') .. (obj.stderr or '')
        local args_table = {}
        local seen = {} --  Look-up filter to prevent duplicate flags

        local filter_db_path = pio_diag.get_db_path()
        local caced_blocked = pio_diag.get_manual_blocked(filter_db_path)
        local auto_removed_flags = caced_blocked.flags
        -- Extract anything clangd reports as an 'unknown argument'
        if not string.find(output, '%.clang%-format') then
          for arg in string.gmatch(output, "unknown argument[:%s]+'([^']+)'") do
            -- local clean_flag = string.format('"%s"', arg:gsub('[;%.]$', ''))
            local clean_flag = string.format('%s', arg:gsub('[;%.]$', ''))

            -- ✅ Only save the flag if we haven't encountered it yet on this run
            if not seen[clean_flag] then
              seen[clean_flag] = true
              table.insert(args_table, clean_flag)
              if not auto_removed_flags[clean_flag] then
                auto_removed_flags[clean_flag] = true
              end
            end
          end
        end
        -- 4. UPDATE: Rebuild with the new discovered flags
        -- require('nvimpio.clangd.diagnostic').unknownArgs()
        local misc_ok, misc = pcall(require, 'nvimpio.utils.misc')
        if (misc_ok and misc) then
          misc.writeFile(filter_db_path, misc.jsonFormat(caced_blocked), {})
          M.cached_db_mtime = 0 -- Invalidate mtime cache
        end
        -- local f = io.open(filter_db_path, 'wb')
        -- if f then
        --   f:write(require('nvimpio.utils.misc').jsonFormat(caced_blocked))
        --   f:close()
        -- end
        -- pio_diag.cached_db_mtime = 0 -- Invalidate cache

        -- Trigger the boilerplate generation process
        local boiler = require('nvimpio.boilerplate')
        if boiler and boiler.boilerplate_gen then
          -- pcall(boiler.boilerplate_gen, '.clangd', OS.project_dir, 'diagnostics wipe flags')
          pcall(boiler.boilerplate_gen, '.clangd', 'diagnostics wipe flags')
        end

        OS.notify(from .. ' Clangd ✅Extracted ' .. #args_table .. ' flags.', 'info')
        M.restart()
      end)
    end)
  end, 'clangd')
end

-- INFO: get_clangd_unknown_args
--------------------------------------------------------------------------------
---@param from string
function M.getUnknownArgsGui(from)
  from = (type(from) == 'string' and from ~= '') and from or 'PIO: '
  -- 1. RESET: Clear flags and rebuild .clangd (removes old 'Remove' block)
  boilerplate.args = {}

  -- Strip out any previous dynamic blocks to prevent endless growing
  -- boilerplate_gen('.clangd', vim.g.platformioRootDir) -- read user '.clangd'
  boilerplate_gen('.clangd') -- read user '.clangd'

  -- 2. FIND: Grab the first .cpp or .c file in /src
  local check_file = vim.fs.find(function(name)
    return name:match('%.cpp$') or name:match('%.c$')
  end, { limit = 1, path = vim.uv.cwd() .. '/src' })[1]

  if not check_file then
    -- boilerplate_gen([[main.cpp]], vim.uv.cwd() .. '/src')
    -- boilerplate_gen([[main.hpp]], vim.uv.cwd() .. '/include')
    -- boilerplate_gen([[arduino]])
    boilerplate_gen(_G.metadata.envs[_G.metadata.active_env].framework)
    check_file = vim.uv.cwd() .. '/src/main.cpp'
  end

  -- 3. SCAN: Run clangd (it will see all errors because .clangd is now empty)
  M.clangdIntall(function(clangdCmd)
    OS.notify('getting unknown arguments for file ' .. check_file, OS.debug)
    --------------------------------------------------------------------------------
    -- gui
    -- local cmd_str = string.format('%s -E -dM -xc++ %s', _G.metadata.cxx_path, table.concat(_G.metadata.cxx_flags, ' '))
    local cmd_str = string.format(
      '%s --compile-commands-dir=. --check=%s --query-driver=%s --log=error --enable-config --fallback-style=llvm --compile_args_from=filesystem',
      clangdCmd,
      check_file,
      _G.metadata.query_driver
    )
    -- local pio = require('nvimpio.pio.upkeep')
    local parser = require('nvimpio.device.parser')
    local cb = function(status)
      parser.handleClangdCheck(status, function(success, args_table)
        args_table = args_table or {}
        if success then
          boilerplate.args = args_table
          -- boilerplate_gen('.clangd', vim.g.platformioRootDir)
          boilerplate_gen('.clangd')

          OS.notify(from .. ' Clangd ✅Extracted ' .. #args_table .. ' flags.', OS.debug)
          M.restart()
        end
      end)
    end
    parser.run_sequence({ cmnds = { cmd_str }, cb = cb, from = string.format('%s clangdCmd', from) })
  end, 'clangd')
end
--------------------------------------------------------------------------------

----------------------------------------------------------------------------------------
-- INFO: configure clangd lsp server
-----------------------------------------------------------------------------------------


-- ============================================================================
-- NATIVE PATH EXPANDER (Fully Resolves Tildes, Drive Casing, and Slashes)
-- ============================================================================
local function normalize_absolute_path(path)
  if not path or path == '' then return '' end
  local expanded = vim.fn.fnamemodify(path, ':p')
  return vim.fs.normalize(expanded) --:lower()
end

local function get_validated_project_root(bufnr)
  -- local buf_name = normalize_absolute_path(vim.api.nvim_buf_get_name(bufnr))
  local buf_name = normalize_absolute_path(OS.getBufFilename(bufnr))
  if not buf_name or buf_name == '' then return normalize_absolute_path(OS.project_dir) end

  -- Sandbox Guard: Prevent indexing inside global platformio package cache folders
  -- if buf_name:find('.platformio', 1, true) then return normalize_absolute_path(OS.project_dir) end
  if buf_name:find(_G.metadata.framework_root, 1, true) then return normalize_absolute_path(OS.project_dir) end

  -- Native C-speed upward path tracer looking for framework landmarks
  local project_root = vim.fs.root(bufnr, {
    ".nvimpio", "compile_commands.json", "platformio.ini", "compile_flags.txt",
  })
  -- local absPath = normalize_absolute_path(project_root)
  -- print(absPath)
  return normalize_absolute_path(project_root) -- or OS.project_dir)
end

-- ============================================================================
function M.getClangdConfig()
  local server_name = 'clangd'
  -- Safe defaults (Standard clangd behavior)
  local q_driver, merged_json = '**', ''

  if _G.metadata and _G.metadata.query_driver and _G.metadata.query_driver ~= '' then
    -- q_driver = 'C:\\\\**\\\\*.exe,C:/**' --_G.metadata.query_driver
    q_driver = _G.metadata.query_driver
  end

  -- q_driver = '**/tools/**/bin/*gcc*,**/tools/**/bin/*g++*,**/.platformio/packages/toolchain-**/*'

  -- Format your template string
  -- local json_config = boilerplate_gen([[.clangdConfig.json]], OS.nvimpio_config_dir)
  local json_config = boilerplate_gen([[.clangdConfig.json]])
  if not json_config then return nil end

  -- local formatted_fallbackFlags = { '"-std=c++17"', '"-ferror-limit=0"' }  -- cxx std=c==17 + response file
  local _, count = json_config:gsub('%%s', '')
  -- Only use string.format if there is one or less %s
  if count <= 2 then
    -- merged_json = string.format(json_config or '', q_driver)
    -- merged_json = string.format(json_config or '', OS.project_dir, q_driver, table.concat(formatted_fallbackFlags, ','))
    -- local dbPath = vim.fs.joinpath(OS.nvimpio_config_dir, _G.metadata.active_env)
    local dbPath = OS.project_dir
    merged_json = string.format(json_config or '', normalize_absolute_path(dbPath), q_driver)
    -- merged_json = string.format(json_config or '', OS.nvimpio_config_dir, q_driver)
  end

  -- Decode JSON string -> Lua table
  local tok, clangd_config = pcall(vim.json.decode, merged_json)
  if not tok then return nil end

  -- NATIVE ASYNC ROOT DETECTOR: Routes paths through our sandbox filter helper
  clangd_config.root_dir = function(bufnr, on_dir) on_dir(get_validated_project_root(bufnr)) end

  -- NATIVE REUSE LAYER: Enforces explicit string path validation boundaries
  clangd_config.reuse_client = function(client, config)
    if client.name ~= server_name then return false end

    -- 1. FRAMEWORK CHECK: If the target file lives inside the framework, 
    -- bypass all downstream logic and instantly force reuse.
    local target_bufnr = config.bufnr or 0
    -- local check_file = vim.fs.normalize(vim.api.nvim_buf_get_name(target_bufnr))
    local check_file = vim.fs.normalize(OS.getBufFilename(target_bufnr))
    if check_file:find(_G.metadata.framework_root, 1, true) then return true end

    -- 2. RELIABLE STRING EXTRACTION: Evaluate the path directly and synchronously
    local proposed_root = get_validated_project_root(target_bufnr) or ""

    -- 3. VALIDATION SAFEGUARDS: Check the active server variables defensively
    if proposed_root == "" then return true end

    local running_client_root = client.config.root_dir or client.root_dir
     -- Safety: Spawn a fresh server instance if active client state is missing
    if not running_client_root or running_client_root == "" then return false end

    -- 4. WORKSPACE DIVISION MATCH: Separate distinct user workspace boundaries
    return normalize_absolute_path(running_client_root) == normalize_absolute_path(proposed_root)
  end
  -- =================================================================

  -- clangd_config.cmd_env = {
  --   "CLANGD_TRACE": "",
  --   CPATH = "",
  --   C_INCLUDE_PATH = "",
  --   CPLUS_INCLUDE_PATH = "",
  --   -- Ensures it uses the exact same environment variables as normal user mode
  --   HOME = vim.env.HOME,
  --   XDG_CONFIG_HOME = vim.env.XDG_CONFIG_HOME or (vim.env.HOME .. "/.config")
  -- }

  -- clangd_config.before_init = function(params, config)
  --   if params.rootUri then
  --     params.rootUri = vim.uri_from_fname(vim.fn.resolve(vim.uri_to_fname(params.rootUri)))
  --   end
  clangd_config.before_init = function(_, _)
    -- Step 1: Parse database into an isolated local table variable first
    if has_pio_diag and pio_diag then
      pio_diag.cached_db_mtime = 0 -- Invalidate cache
      local filter_db_path = vim.fs.joinpath(OS.nvimpio_env_dir, OS.clangd_filter)
      pio_diag.get_manual_blocked(filter_db_path)
      -- local f = io.open(filter_db_path, 'r')
      -- if f then
      --   local raw = f:read('*a')
      --   f:close()
      --   if raw and raw ~= '' then
      --     local ok, data = pcall(vim.json.decode, raw)
      --     if ok and data and type(data.flags) == 'table' then
      --       for flag, blocked in pairs(data.flags) do
      --         if blocked then pio_diag.auto_removed_flags[flag] = true end
      --       end
      --     end
      --     if ok and data and type(data.codes) == 'table' then
      --       for code, blocked in pairs(data.codes) do
      --         if blocked then pio_diag.manual_blocked_codes[code] = true end
      --       end
      --     end
      --   end
      -- end
    end
    -- Step 2: Refresh your physical configuration files natively last
    local boiler = require('nvimpio.boilerplate')
    if boiler and boiler.boilerplate_gen then pcall(boiler.boilerplate_gen, '.clangd') end
  end

  -- SOLID TRANSPORT-LAYER INTERCEPTOR HANDLER
  clangd_config.handlers = {
    ['textDocument/publishDiagnostics'] = function(err, result, ctx, config)
      if err or not result or not result.diagnostics then
        local default_handler = vim.lsp.handlers['textDocument/publishDiagnostics']
        if default_handler then default_handler(err, result, ctx, config) end
        return
      end

      if has_pio_diag and pio_diag then
        -- local target_path = vim.uri_to_fname(result.uri)
        -- local is_config = target_path:match('%.clangd$') or target_path:match('%.json$')
        -- -- if diagnostics for column 0 , row 0
        -- if is_config then
        --   if pio_diag.clean_file_path_pipeline then result.diagnostics = pio_diag.clean_file_path_pipeline(result.diagnostics) end
        --   -- if pio_diag.clean_project_wide_flags then pio_diag.clean_project_wide_flags(result.diagnostics) end
        --   -- return -- Block configuration diagnostics from polluting user view
        -- else
          if pio_diag.clean_file_path_pipeline then result.diagnostics = pio_diag.clean_file_path_pipeline(result) end
        -- end
      end

      local default_handler = vim.lsp.handlers['textDocument/publishDiagnostics']
      if default_handler then default_handler(err, result, ctx, config) end
    end,
  }

  if clangd_config then return clangd_config end
end

-- INFO: clangdRestart()
--------------------------------------------------------------------------------
function M.restart()
  local name = 'clangd'
  local old_client = nil

  -- local current_buf = vim.api.nvim_get_current_buf()
  -- for _, client in ipairs(vim.lsp.get_clients({ name = name, bufnr = current_buf })) do
  for _, client in ipairs(vim.lsp.get_clients({ name = name })) do
    old_client = client
    break
  end

  if not old_client then
    vim.lsp.enable(name, false)
    vim.lsp.config(name, M.getClangdConfig())
    vim.lsp.enable(name, true)
    OS.notify('[Clangd] instance initialized.', OS.debug)
    return
  end

  local old_id = old_client.id
  OS.notify('[Clangd] reset for client ID: ' .. old_id, OS.debug)

  local reload_group = vim.api.nvim_create_augroup('Clangd_Cold_Reset_Engine', { clear = true })

  vim.api.nvim_create_autocmd('LspDetach', {
    group = reload_group,
    desc = 'Re-activate state schemas the microsecond the old channel is deleted from memory',
    callback = function(args)
      if args.data.client_id == old_id then
        vim.api.nvim_del_augroup_by_id(reload_group)

        vim.schedule(function()
          OS.notify('[Clangd] Channels flushed. Re-enabling pure declarative workspace structures...', OS.debug)
          vim.lsp.enable(name, false)
          local clangConfig = M.getClangdConfig()
          vim.lsp.config(name, clangConfig)
          vim.lsp.enable(name, true)
          OS.notify('[Clangd] Dynamic cold-boot complete.', OS.debug)
        end)
      end
    end,
  })

  old_client:stop(false)
end

--=============================================================================
function M.init(clangd)
  OS.notify('Clangd Control: initialize', OS.debug)

  if clangd.install then require('nvimpio.clangd.config') end

  require('nvimpio.clangd.commands')
  require('nvimpio.clangd.diagnostic')

  if clangd.attach ~= "none" then
    require('nvimpio.clangd.attach').init(clangd)
  end

  -- -- -- Apply and Enable
  -- local clangConfig = M.getClangdConfig()
  -- vim.lsp.config('clangd', clangConfig)
  -- vim.lsp.enable('clangd')


  vim.keymap.set('n', 'gll', function()
    vim.cmd.edit(vim.lsp.log.get_filename())
  end, { desc = 'open LSP [l]og' })

end

return M
-- stylua: ignore end
