local M = {}

local boilerplate = require('nvimpio.boilerplate')
local boilerplate_gen = boilerplate.boilerplate_gen
local diagnostic = require('nvimpio.clangd.diagnostic')

--- stylua: ignore start
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

  -- 'decode' converts JSON string -> Lua table
  local tok, clangd_config = pcall(vim.json.decode, merged_json)

  if not tok then return nil end

  clangd_config.handlers = {
    -- Override the default diagnostic publishing target route
    ["textDocument/publishDiagnostics"] = diagnostic.diagnostic_handler
  }
  -- clangd_config.handlers = {
  --   ["textDocument/publishDiagnostics"] = function(err, result, ctx, config)
  --     -- Only filter if there are diagnostics present
  --     if not err and result and result.diagnostics then
  --       local success, pio_diag = pcall(require, "nvimpio.clangd.diagnostic")
  --       if success and pio_diag and pio_diag.clean_diagnostics_pipeline then
  --         result.diagnostics = pio_diag.clean_diagnostics_pipeline(result.diagnostics)
  --       end
  --     end
  --     -- Pass to Neovim's default handler
  --     vim.lsp.handlers["textDocument/publishDiagnostics"](err, result, ctx, config)
  --   end
  -- }

  if clangd_config then return clangd_config end
end

-- INFO: clangdRestart()
--------------------------------------------------------------------------------
--- stylua: ignore
function M.restart()
  vim.schedule(function()
    local name = 'clangd'
    OS.notify('LSP: Clangd restart.', 'warn')
    --
    -- for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    --   if vim.api.nvim_buf_is_loaded(bufnr) then
    --     -- Get all active LSP clients explicitly attached to this specific buffer
    --     local active_clients = vim.lsp.get_clients({ bufnr = bufnr, name = name })
    --
    --     -- Only clear the diagnostics if clangd is actively running on this buffer
    --     if #active_clients > 0 then
    --       vim.diagnostic.reset(nil, bufnr)
    --     end
    --   end
    -- end

    local clangConfig = M.getClangdConfig()

    vim.lsp.config(name, clangConfig)
    vim.lsp.enable(name, false)
    vim.lsp.enable(name, true)
    -- vim.defer_fn(function()
    --   local current_buf = vim.api.nvim_get_current_buf()
    --   if vim.api.nvim_buf_is_valid(current_buf) then
    --      vim.cmd('checktime') -- Synch file modifications with the file system safely
    --      vim.cmd('edit!') -- Forces a hard buffer refresh, clearing old errors instantly
    --   end
    -- end, 100)
    -- vim.cmd('checktime')
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

local diagnosticClangd = require('nvimpio.clangd.diagnosticAutoClangd')
---@param from string
function M.blockUnknownArgsCli(from)
  from = (type(from) == 'string' and from ~= '') and from or 'PIO: '

  -- 1. TARGET ACTIVE BUFFER: Run the automation on the file you are currently looking at
  local target_buf = vim.api.nvim_get_current_buf()
  local file_name = vim.api.nvim_buf_get_name(target_buf)

  -- Safety check to ensure we don't run on NvimTree or empty windows
  local norm_name = vim.fs.normalize(file_name):gsub('%s+$', ''):lower()
  if file_name == '' or not (norm_name:match('%.cpp$') or norm_name:match('%.c$') or norm_name:match('%.hpp$') or norm_name:match('%.h$')) then
    OS.notify('Automation aborted: Focus a valid C/C++ source code file first.')
    return
  end

  -- Create a unique namespace for our active automated pipeline group
  local au_group = vim.api.nvim_create_augroup('NvimPioLiveSweepGroup', { clear = true })

  -- 2. Define the structural loop data compiler scraper
  local function run_live_analysis_pass()
    -- Directly inspect the live diagnostics loaded onto your visible workspace screen
    local raw_nodes = vim.diagnostic.get(target_buf)
    local new_discoveries = false

    for _, diag in ipairs(raw_nodes) do
      local msg = diag.message or ''
      local code_name = diag.code

      -- Pass A: Multi-Flag Extractor (Decoupled & colon-immune via %p?)
      for unknown_arg in string.gmatch(msg, 'argument%s*%p?%s*[\'"]?(%-[%w%-]+)[\'"]?') do
        local clean_flag = unknown_arg:gsub('[\'"%?]', ''):gsub('%s+$', '')
        if not diagnosticClangd.removed_flags[clean_flag] then
          diagnosticClangd.removed_flags[clean_flag] = true
          new_discoveries = true
        end
      end

      for unknown_arg in string.gmatch(msg, 'option%s*%p?%s*[\'"]?(%-[%w%-]+)[\'"]?') do
        local clean_flag = unknown_arg:gsub('[\'"%?]', ''):gsub('%s+$', '')
        if not diagnosticClangd.removed_flags[clean_flag] then
          diagnosticClangd.removed_flags[clean_flag] = true
          new_discoveries = true
        end
      end

      -- Pass B: Code Suppression (Pulls codes like pp_file_not_found out of the active engine memory)
      if code_name and type(code_name) == 'string' and code_name ~= '' then
        if not diagnosticClangd.blocked_codes[code_name] then
          diagnosticClangd.blocked_codes[code_name] = true
          new_discoveries = true
        end
      end
    end

    -- 3 & 4. Execution Flow Branching & Transition Shielding
    if new_discoveries then
      OS.notify('Layer discovered! Updating .clangd and cycling compiler targets...')

      -- Save accumulated states directly to .filter.json and rewrite the updated .clangd file
      diagnosticClangd.save_from_cli()

      -- Kill and restart clangd
      M.restart()

      -- Force a hard buffer reload on screen to push the next layer of errors out
      vim.defer_fn(function()
        if vim.api.nvim_buf_is_valid(target_buf) then
          vim.cmd('checktime')
          vim.cmd('edit!')
        end
      end, 150)
    else
      -- Verify if raw_nodes is empty AND make sure we aren't caught in an LSP boot transition.
      local has_active_errors = false
      for _, node in ipairs(raw_nodes) do
        if node.severity == vim.diagnostic.severity.ERROR or node.severity == vim.diagnostic.severity.WARN then
          has_active_errors = true
          break
        end
      end

      -- Only self-destruct the automation group if the file has been processed
      -- AND contains absolutely zero outstanding warnings or error objects.
      if not has_active_errors and #raw_nodes > 0 then
        vim.api.nvim_del_augroup_by_id(au_group)
        OS.notify(from .. ' Clangd Automation ✅ Complete baseline sync done! Remaining errors are raw code typos.')
      elseif #raw_nodes == 0 then
        -- LSP Boot/Reset transition guard: Do nothing and preserve the group to catch incoming server data
        return
      else
        -- Errors remain but no new filter targets extracted (valid user source typos)
        vim.api.nvim_del_augroup_by_id(au_group)
        OS.notify(from .. ' Clangd Automation ✅ Dynamic blocks synchronized. Remaining errors are valid source typos.')
      end
    end
  end

  -- 5. THE DEBOUNCED AUTOMATION HOOK: Run automatically whenever fresh diagnostics land on your screen
  local debounce_timer = nil
  vim.api.nvim_create_autocmd('DiagnosticChanged', {
    group = au_group,
    buffer = target_buf,
    callback = function()
      if debounce_timer then
        vim.uv.timer_stop(debounce_timer)
      end
      debounce_timer = vim.uv.new_timer()
      if debounce_timer then
        debounce_timer:start(
          400,
          0,
          vim.schedule_wrap(function()
            run_live_analysis_pass()
          end)
        )
      end
    end,
  })

  -- Kick off the very first automation loop pass instantly
  OS.notify('Starting live cascading sweep for: ' .. vim.fs.basename(file_name))
  run_live_analysis_pass()
end

-- pio/control 160
-- pio/upkeep 170, 1001, 1178
-- INFO: get_clangd_unknown_args
--------------------------------------------------------------------------------
---@param from string
function M.getUnknownArgsCli(from)
  from = (type(from) == 'string' and from ~= '') and from or 'PIO: '
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
    -- cli
    local cmd = { clangdCmd, '--compile-commands-dir=.', '--check=' .. check_file, '--query-driver=**', '--log=error' }
    -- local cmd = { clangdCmd, '--compile-commands-dir=.', '--check=' .. check_file, '--log=error' }
    vim.system(cmd, { text = true }, function(obj)
      vim.schedule(function()
        local output = (obj.stdout or '') .. (obj.stderr or '')
        local args_table = {}
        local seen = {} -- 🌟 Look-up filter to prevent duplicate flags

        -- Extract anything clangd reports as an 'unknown argument'
        if not string.find(output, '%.clang%-format') then
          for arg in string.gmatch(output, "unknown argument[:%s]+'([^']+)'") do
            local clean_flag = string.format('"%s"', arg:gsub('[;%.]$', ''))

            -- ✅ Only save the flag if we haven't encountered it yet on this run
            if not seen[clean_flag] then
              seen[clean_flag] = true
              table.insert(args_table, clean_flag)
            end
          end
        end
        --------------------------------------------------------------------------------
        -- 4. UPDATE: Integrate into the persistence database layer
        -- The diagnostic script tracks flags as keys to prevent array duplication:
        -- e.g., diagnostic.removed_flags["-mlongcalls"] = true
        diagnostic.removed_flags = {}
        local updated_count = 0
        for arg, _ in pairs(seen) do
          -- Remove quotes if string.gmatch wrapped them, keeping the raw flag
          local raw_flag = arg:gsub('^"', ''):gsub('"$', '')

          if not diagnostic.removed_flags[raw_flag] then
            diagnostic.removed_flags[raw_flag] = true
            updated_count = updated_count + 1
          end
        end

        -- Explicitly call your saving pipeline.
        -- This automatically maps diagnostic.removed_flags to boiler.remove,
        -- writes .filter.json, and generates a perfect .clangd file.
        if updated_count > 0 then
          -- Accessing the local helper via an internal function exposure (See Step 2)
          diagnostic.save_from_cli()
          OS.notify(from .. ' Clangd ✅Integrated ' .. updated_count .. ' new flags globally.')
        else
          OS.notify(from .. ' Clangd ✅No new unique flags detected.')
        end

        M.restart()
        -- -- 4. UPDATE: Rebuild with the new discovered flags
        -- boilerplate.args = args_table
        -- boilerplate_gen('.clangd', vim.g.platformioRootDir)
        --
        -- OS.notify(from .. ' Clangd ✅Extracted ' .. #args_table .. ' flags.')
        -- M.restart()
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
    local cmd_str = string.format(
      '%s --compile-commands-dir=. --check=%s --query-driver=%s --log=error --enable-config --fallback-style=llvm --compile_args_from=filesystem',
      clangdCmd,
      check_file,
      _G.metadata.query_driver
    )
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
    pio.run_sequence({ cmnds = { cmd_str }, cb = cb, from = string.format('%s clangdCmd', from) })
  end, 'clangd')
end
--------------------------------------------------------------------------------

--stylua: ignore
--=============================================================================
function M.init(clangd)
  OS.notify('Clangd Control: initialize', "info")

  if clangd.install then require('nvimpio.clangd.config') end
  require('nvimpio.clangd.attach')

  -- Apply and Enable
  local getClangdConfig = require('nvimpio.clangd.control').getClangdConfig
  if getClangdConfig then
    vim.lsp.config('clangd', getClangdConfig())
    vim.lsp.enable('clangd')
  end

  require('nvimpio.clangd.commands')
  require('nvimpio.clangd.diagnostic')

  vim.keymap.set('n', 'gll', function()
    vim.cmd.edit(vim.lsp.log.get_filename())
  end, { desc = 'open LSP [l]og' })

end

-- stylua: ignore end

return M
