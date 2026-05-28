local M = {}

local boilerplate = require('nvimpio.boilerplate')
local boilerplate_gen = boilerplate.boilerplate_gen

-- stylua: ignore start
----------------------------------------------------------------------------------------
-- INFO: configure clangd lsp server
--stylua: ignore
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
        callback(mason_exe)
        return
      end

      -- 2. TRIGGER: Not installed and NOT installing? Start the install.
      if not pkg:is_installed() and not pkg:is_installing() then
        vim.notify('Mason: Auto-installing ' .. package_name .. ' ...', vim.log.levels.INFO)
        pkg:install()
        -- After triggering install, we continue to poll to wait for completion
      end

      -- 3. WAIT: If we haven't timed out, check again in 1 second
      if check_count < max_checks then
        check_count = check_count + 1
        -- Visual feedback for long installs
        if check_count % 5 == 0 then
          vim.schedule(function()
            vim.cmd('echo "Mason: Waiting for ' .. package_name .. ' installation... ' .. check_count .. 's"')
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
-- stylua: ignore
function M.getClangdConfig()
  local new_root_dir = vim.uv.cwd() or '.'
  if not new_root_dir then return end

  -- Safe defaults (Standard clangd behavior)
  local q_driver, merged_json = '**', ''
  -- local f_flags = [["-std=c++17", "-xc++"]]

  -- Run your toolchain detection
  if _G.metadata and _G.metadata.cc_path and _G.metadata.cc_path ~= '' then
    if _G.metadata.triplet and _G.metadata.triplet ~= '' then
      -- local include_flags = table.concat(vim.tbl_map(function(item)
      --   return '"' .. item .. '"'
      -- end, _G.metadata.fallbackFlags), ", ")

      -- local includes_toolchain = table.concat(vim.tbl_map(function(item)
      --   return '"' .. item .. '"'
      -- end, _G.metadata.includes_toolchain), ", ")

      -- f_flags = string.format([["-std=gnu++17", "-xc++", "-D__cplusplus=201703L", "--target=%s", "--sysroot=%s", %s, %s]], _G.metadata.triplet, _G.metadata.sysroot, includes_toolchain, include_flags)

      q_driver = _G.metadata.query_driver --.. ',C:/PROGRA~1/LLVM/bin/*'          -- use with "--query-driver=%s"
    end
  end

  -- Format your template string
  local json_config = boilerplate_gen([[.clangd_config.json]], vim.g.platformioRootDir)
  if not json_config then return nil end

  local _, count = json_config:gsub('%%s', '')
  -- Only use string.format if there is one or less %s
  if count <= 1 then merged_json = string.format(json_config or '', q_driver) end
  -- local formatted_str = string.format(table_config or '', q_driver, f_flags, misc.normalizePath(new_root_dir))

  -- 'decode' converts JSON string -> Lua table
  local tok, clangd_config = pcall(vim.json.decode, merged_json)

  if not tok then return nil end

  if clangd_config then return clangd_config end
end

-- INFO: clangdRestart()
--------------------------------------------------------------------------------
--- stylua: ignore
function M.restart()
  vim.schedule(function()
    local name = 'clangd'
    OS.notify('LSP: Clangd restart.', 'warn')


    for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_is_loaded(bufnr) then
        -- Get all active LSP clients explicitly attached to this specific buffer
        local active_clients = vim.lsp.get_clients({ bufnr = bufnr, name = name })

        -- Only clear the diagnostics if clangd is actively running on this buffer
        if #active_clients > 0 then
          vim.diagnostic.reset(nil, bufnr)
        end
      end
    end





    local clangConfig = M.getClangdConfig()

    vim.lsp.config(name, clangConfig)
    vim.lsp.enable(name, false)
    vim.lsp.enable(name, true)
    vim.cmd('checktime')
    _G.metadata.isBusy = false
  end)
end

-- INFO: set_clang_format_style()
--------------------------------------------------------------------------------
-- stylua: ignore
function M.setFormatStyle()
  local styles = { 'LLVM', 'Google', 'Chromium', 'Mozilla', 'WebKit', 'Microsoft', 'GNU' }

  vim.ui.select(styles, {
    prompt = 'Select Clang-Format base style:',
  }, function(choice)
    if not choice then return end

    -- Define the command as a table for cleaner execution
    -- We use cmd /c only because of the '>' redirect

    M.clangdIntall(function(clangdCmd)
      -- using toggleterm for setting clang-format style
      local cmd = string.format('%s --style=%s --dump-config > .clang-format', clangdCmd, choice:lower())
      local pio = require('nvimpio.pio.upkeep')
      pio.run_sequence({
        cmnds = { cmd },
        cb = pio.clangFormat,
        from = 'clangdIntall',
      })

      -- using hidden system command for setting clang-format style
      -- local cmd = { clangdCmd, string.format('--style=%s --dump-config > .clang-format', choice:lower()) }
      -- Execute asynchronously
      -- vim.system(cmd, { text = true }, function(obj)
      --   -- This callback runs when the process finishes
      --   -- Use vim.schedule to perform UI tasks/API calls on the main thread
      --   vim.schedule(function()
      --     if obj.code == 0 then
      --       OS.notify('Created .clang-format (' .. choice .. ')', "info")
      --
      --       -- Restart clangd to apply the new rules
      --       M.restart()
      --       print('LSP Reloaded: Using ' .. choice .. ' style.')
      --     else
      --       OS.notify('Failed to generate .clang-format. Error: ' .. (obj.stderr or "Unknown"), "error")
      --     end
      --   end)
      -- end)
    end, 'clang-format')
  end)
end


-- pio/control 160
-- pio/upkeep 170, 1001, 1178
-- INFO: get_clangd_unknown_args
--------------------------------------------------------------------------------
---@param from string
function M.getUnknownArgsCli(from)
  from = (type(from)=='string' and from ~= '') and from or 'PIO: '
  -- 1. RESET: Clear flags and rebuild .clangd (removes old 'Remove' block)
  boilerplate.args = {}

  -- Strip out any previous dynamic blocks to prevent endless growing
  boilerplate_gen('.clangd', vim.g.platformioRootDir) -- read user '.clangd'

  -- 2. FIND: Grab the first .cpp or .c file in /src
  local check_file = vim.fs.find(function(name)
    return name:match('%.cpp$') or name:match('%.c$')
  end, { limit = 1, path = vim.uv.cwd() .. '/src' })[1]

  if not check_file then
    boilerplate_gen([[main.cpp]], vim.uv.cwd() .. '/src')
    boilerplate_gen([[main.hpp]], vim.uv.cwd() .. '/include')
    check_file = vim.uv.cwd() .. '/src/main.cpp'
  end

  -- 3. SCAN: Run clangd (it will see all errors because .clangd is now empty)
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
    -- cli
    local cmd = { clangdCmd, '--compile-commands-dir=.', '--check=' .. check_file, '--query-driver=**', '--log=error' }
    -- local cmd = { clangdCmd, '--compile-commands-dir=.', '--check=' .. check_file, '--log=error' }
    vim.system(cmd, { text = true }, function(obj)
      vim.schedule(function()
        local output = (obj.stdout or '') .. (obj.stderr or '')
        local args_table = {}
        local seen = {} -- 🌟 Look-up filter to prevent duplicate flags

        -- Extract anything clangd reports as an 'unknown argument'
        if not string.find(output, "%.clang%-format") then
          for arg in string.gmatch(output, "unknown argument[:%s]+'([^']+)'") do
            local clean_flag = string.format('"%s"', arg:gsub('[;%.]$', ''))

            -- ✅ Only save the flag if we haven't encountered it yet on this run
            if not seen[clean_flag] then
              seen[clean_flag] = true
              table.insert(args_table, clean_flag)
            end
          end
        end
        -- 4. UPDATE: Rebuild with the new discovered flags
        boilerplate.args = args_table
        boilerplate_gen('.clangd', vim.g.platformioRootDir)

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
  from = (type(from)=='string' and from ~= '') and from or 'PIO: '
  -- 1. RESET: Clear flags and rebuild .clangd (removes old 'Remove' block)
  boilerplate.args = {}

  -- Strip out any previous dynamic blocks to prevent endless growing
  boilerplate_gen('.clangd', vim.g.platformioRootDir) -- read user '.clangd'

  -- 2. FIND: Grab the first .cpp or .c file in /src
  local check_file = vim.fs.find(function(name)
    return name:match('%.cpp$') or name:match('%.c$')
  end, { limit = 1, path = vim.uv.cwd() .. '/src' })[1]

  if not check_file then
    boilerplate_gen([[main.cpp]], vim.uv.cwd() .. '/src')
    boilerplate_gen([[main.hpp]], vim.uv.cwd() .. '/include')
    check_file = vim.uv.cwd() .. '/src/main.cpp'
  end

  -- 3. SCAN: Run clangd (it will see all errors because .clangd is now empty)
  M.clangdIntall(function(clangdCmd)
    OS.notify('getting unknown arguments for file ' .. check_file)
    --------------------------------------------------------------------------------
    -- gui
    local cmd_str = string.format('%s --compile-commands-dir=. --check=%s --query-driver=%s --log=error --enable-config --fallback-style=llvm --compile_args_from=filesystem', clangdCmd, check_file, _G.metadata.query_driver)
    local pio = require('nvimpio.pio.upkeep')
    local cb = function(status)
      pio.handleClangdCheck(status, function(success, args_table)
        args_table = args_table or {}
        if success then
          boilerplate.args = args_table
          boilerplate_gen('.clangd', vim.g.platformioRootDir)

          OS.notify(from .. ' Clangd ✅Extracted ' .. #args_table .. ' flags.')
          M.restart()
        end
      end)
    end
    pio.run_sequence({ cmnds = { cmd_str }, cb = cb, from = string.format('%s clangdCmd' , from) })
  end, 'clangd')
end
--------------------------------------------------------------------------------

--stylua: ignore
--=============================================================================
function M.init(clangd)
  OS.notify('Clangd Control: initialize', "info")

  -- working good snack
  -- local original_diagnostic_handler = vim.lsp.handlers["textDocument/publishDiagnostics"]
  -- vim.lsp.handlers["textDocument/publishDiagnostics"] = function(err, result, ctx, config)
  --   local client = vim.lsp.get_client_by_id(ctx.client_id)
  --
  --   if client and client.name == "clangd" then
  --     if result and result.diagnostics then
  --       -- 🌟 THE NATIVE BRIDGE: Pass diagnostics through your plugin module's memory filter
  --       local success, pio_diag = pcall(require, "nvimpio.clangd.diagnostic")
  --       if success and pio_diag and pio_diag.clean_diagnostics_pipeline then
  --         result.diagnostics = pio_diag.clean_diagnostics_pipeline(result.diagnostics)
  --       end
  --     end
  --   end
  --   original_diagnostic_handler(err, result, ctx, config)
  -- end

-- Save the core native LSP text handler
local original_diagnostic_handler = vim.lsp.handlers["textDocument/publishDiagnostics"]
vim.lsp.handlers["textDocument/publishDiagnostics"] = function(err, result, ctx, config)
  -- 1. Ultra-fast boundary checks: exit immediately if it's not clangd data
  local client_id = ctx and ctx.client_id
  local client = client_id and vim.lsp.get_client_by_id(client_id)
  if not client or client.name ~= "clangd" then
    return original_diagnostic_handler(err, result, ctx, config)
  end

  -- 2. Clangd exclusive payload processing zone
  if not err and result and result.diagnostics then
    local success, pio_diag = pcall(require, "nvimpio.clangd.diagnostic")
    if success and pio_diag and pio_diag.clean_diagnostics_pipeline then
      result.diagnostics = pio_diag.clean_diagnostics_pipeline(result.diagnostics)
    end
  end
  -- Hand off the validated and stripped data array down to the UI renderer
  original_diagnostic_handler(err, result, ctx, config)
end

  require('nvimpio.clangd.commands')

  require('nvimpio.clangd.diagnostic')
  vim.keymap.set('n', 'gll', function()
    vim.cmd.edit(vim.lsp.log.get_filename())
  end, { desc = 'open LSP [l]og' })

  if clangd.install then require('nvimpio.clangd.config') end
end

-- stylua: ignore end

return M
