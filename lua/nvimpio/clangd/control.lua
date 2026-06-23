local M = {}

local boilerplate = require('nvimpio.boilerplate')
local boilerplate_gen = boilerplate.boilerplate_gen
local diagnosticClangd = require('nvimpio.clangd.diagnostic')
local has_pio_diag, pio_diag = pcall(require, 'nvimpio.clangd.diagnostic')

-- stylua: ignore start
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
        OS.notify('Mason: Auto-installing ' .. package_name .. ' ...', 'info')
        pkg:install()
        -- After triggering install, we continue to poll to wait for completion
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

----------------------------------------------------------------------------------------
-- INFO: configure clangd lsp server
-----------------------------------------------------------------------------------------
-----------------------------------------------------------------------------------------
function M.getClangdConfig()
  -- Safe defaults (Standard clangd behavior)
  local q_driver, merged_json = '**', ''

  if _G.metadata and _G.metadata.query_driver and _G.metadata.query_driver ~= '' then
    q_driver = _G.metadata.query_driver
  end

  -- Format your template string
  -- local json_config = boilerplate_gen([[.clangdConfig.json]], OS.nvimpio_config_dir)
  local json_config = boilerplate_gen([[.clangdConfig.json]])
  if not json_config then return nil end

  local formatted_fallbackFlags = { "-std=c++17", "-ferror-limit=0" }  -- cxx std=c==17 + response file
  for i = 1, #_G.metadata.includes_libdeps do
    table.insert(formatted_fallbackFlags, string.format('%q', _G.metadata.includes_libdeps[i]))
  end

  -- local f_flags = [["-std=c++17", "-xc++", "-ferror-limit=0"]]
  local _, count = json_config:gsub('%%s', '')
  -- Only use string.format if there is one or less %s
  if count <= 3 then
    merged_json = string.format(json_config or '', OS.project_dir, q_driver, table.concat(formatted_fallbackFlags, ',\n    '))
    -- merged_json = string.format(json_config or '', OS.project_dir, q_driver)
  end

  -- 'decode' converts JSON string -> Lua table
  local tok, clangd_config = pcall(vim.json.decode, merged_json)

  if not tok then return nil end

  -- 🥇 LEAN LIFECYCLE SEEDING LAYOUT
  clangd_config.before_init = function(_, _)
    -- Step 1: Parse database into an isolated local table variable first
    if has_pio_diag and pio_diag then
      local filter_db_path = OS.clangd_filter
      local f = io.open(filter_db_path, 'r')
      if f then
        local raw = f:read('*a')
        f:close()
        if raw and raw ~= '' then
          local ok, data = pcall(vim.json.decode, raw)
          if ok and data and type(data.flags) == 'table' then
            for flag, blocked in pairs(data.flags) do
              if blocked then pio_diag.removed_flags[flag] = true end
            end
          end
        end
      end
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
        local client = vim.lsp.get_client_by_id(ctx.client_id)
        local project_root_dir = client and client.config.root_dir or vim.uv.cwd()
        local target_path = vim.uri_to_fname(result.uri)
        local is_config = target_path:match('%.clangd$') or target_path:match('%.json$')

        -- -- 🔍 BACKGROUND INDEXING NETWORK TRACER
        -- local trace_log = vim.fs.joinpath(project_root_dir, 'nvim_pio_boot_trace.log')
        -- local f_trace = io.open(trace_log, 'a')
        -- if f_trace then
        --   local timestamp = os.date('%Y-%m-%d %H:%M:%S')
        --   -- Check if the buffer is currently active/visible to the user's eye
        --   local is_buf_loaded = vim.fn.bufloaded(target_path) == 1
        --
        --   if #result.diagnostics > 0 then
        --     f_trace:write(string.format('[%s] 📡 LSP DIAGNOSTIC PACKET RECEIVED!\n', timestamp))
        --     f_trace:write(string.format('   -> Target File: %s\n', target_path))
        --     f_trace:write(string.format('   -> Is File Open/Loaded in Editor? %s\n', tostring(is_buf_loaded)))
        --
        --     for idx = 1, #result.diagnostics do
        --       local diag = result.diagnostics[idx]
        --       local start_line = diag.range and diag.range.start and diag.range.start.line or -1
        --       local start_col = diag.range and diag.range.start and diag.range.start.character or -1
        --
        --       f_trace:write(string.format('   [%d] Code: [%s] at Row %d, Col %d\n', idx, tostring(diag.code), start_line, start_col))
        --       f_trace:write(string.format('        Msg: %s\n', diag.message or ''))
        --     end
        --   end
        --   f_trace:close()
        -- end

        -- RIGID ROUTING ENGINE
        -- local success, pio_diag = pcall(require, 'nvimpio.clangd.diagnostic')
        -- if success and pio_diag then
        if is_config then
          if pio_diag.clean_project_wide_flags then pio_diag.clean_project_wide_flags(result.diagnostics) end
          return -- Block configuration diagnostics from polluting user view
        else
          if pio_diag.clean_file_path_pipeline then result.diagnostics = pio_diag.clean_file_path_pipeline(result.diagnostics) end
        end
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
  vim.schedule(function()
    local name = 'clangd'
    OS.notify('LSP: Clangd restart.', 'warn')
    --
    local clangConfig = M.getClangdConfig()

    vim.lsp.config(name, clangConfig)
    vim.lsp.enable(name, false)
    vim.lsp.enable(name, true)

    _G.isBusy = false
  end)
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

              OS.notify('Created .clang-format (' .. choice .. ')', 'info')
              M.restart()
              OS.notify('LSP Reloaded: Using ' .. choice .. ' style.')
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

  -- 1. FIND: Grab the first .cpp or .c file in /src
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

    OS.notify('getting unknown arguments for file ' .. check_file)
    --------------------------------------------------------------------------------
    local cmd = { clangdCmd, '--compile-commands-dir=.', '--check=' .. check_file, '--log=error' }
    vim.system(cmd, { text = true }, function(obj)
      vim.schedule(function()
        local output = (obj.stdout or '') .. (obj.stderr or '')
        local args_table = {}
        local seen = {} --  Look-up filter to prevent duplicate flags

        -- Extract anything clangd reports as an 'unknown argument'
        if not string.find(output, '%.clang%-format') then
          for arg in string.gmatch(output, "unknown argument[:%s]+'([^']+)'") do
            -- local clean_flag = string.format('"%s"', arg:gsub('[;%.]$', ''))
            local clean_flag = string.format('%s', arg:gsub('[;%.]$', ''))

            -- ✅ Only save the flag if we haven't encountered it yet on this run
            if not seen[clean_flag] then
              seen[clean_flag] = true
              table.insert(args_table, clean_flag)
              if not diagnosticClangd.removed_flags[clean_flag] then
                diagnosticClangd.removed_flags[clean_flag] = true
              end
            end
          end
        end
        -- 4. UPDATE: Rebuild with the new discovered flags
        -- boilerplate.args = args_table
        -- boilerplate_gen('.clangd', vim.g.platformioRootDir)
        require('nvimpio.clangd.diagnostic').unknownArgs()

        OS.notify(from .. ' Clangd ✅Extracted ' .. #args_table .. ' flags.')
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
    OS.notify('getting unknown arguments for file ' .. check_file)
    --------------------------------------------------------------------------------
    -- gui
    local cmd_str = string.format('%s -E -dM -xc++ %s', _G.metadata.cxx_path, table.concat(_G.metadata.cxx_flags, ' '))
    -- local cmd_str = string.format(
    --   '%s --compile-commands-dir=. --check=%s --query-driver=%s --log=error --enable-config --fallback-style=llvm --compile_args_from=filesystem',
    --   clangdCmd,
    --   check_file,
    --   _G.metadata.query_driver
    -- )
    -- local pio = require('nvimpio.pio.upkeep')
    local parser = require('nvimpio.device.parser')
    local cb = function(status)
      parser.handleClangdCheck(status, function(success, args_table)
        args_table = args_table or {}
        if success then
          boilerplate.args = args_table
          -- boilerplate_gen('.clangd', vim.g.platformioRootDir)
          boilerplate_gen('.clangd')

          OS.notify(from .. ' Clangd ✅Extracted ' .. #args_table .. ' flags.')
          M.restart()
        end
      end)
    end
    parser.run_sequence({ cmnds = { cmd_str }, cb = cb, from = string.format('%s clangdCmd', from) })
  end, 'clangd')
end
--------------------------------------------------------------------------------

--stylua: ignore
--=============================================================================
function M.init(clangd)
  OS.notify('Clangd Control: initialize', "info")

  if clangd.install then require('nvimpio.clangd.config') end

  require('nvimpio.clangd.commands')
  require('nvimpio.clangd.diagnostic')
  require('nvimpio.clangd.attach')

  -- Apply and Enable
  local getClangdConfig = require('nvimpio.clangd.control').getClangdConfig
  if getClangdConfig then
    local clangConfig = M.getClangdConfig()
    vim.lsp.config('clangd', clangConfig)
    vim.lsp.enable('clangd')
  end


  vim.keymap.set('n', 'gll', function()
    vim.cmd.edit(vim.lsp.log.get_filename())
  end, { desc = 'open LSP [l]og' })

end

-- stylua: ignore end

return M
