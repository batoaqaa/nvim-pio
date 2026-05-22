local M = {}

local boilerplate = require('nvimpio.boilerplate')
local boilerplate_gen = boilerplate.boilerplate_gen

----------------------------------------------------------------------------------------
-- INFO: configure clangd lsp server
--stylua: ignore
-----------------------------------------------------------------------------------------
function M.clangdIntall(callback, package_name)
  package_name = package_name or 'clangd'

  -- Modern Neovim 0.11+ way to ensure Mason binaries are found
  local bin_name = vim.fn.has('win32') == 1 and package_name .. '.cmd' or package_name
  local mason_bin = vim.fs.joinpath(OS.data_dir, 'mason', 'bin')
  local mason_exe = vim.fs.joinpath(mason_bin, bin_name)

  -- no need by default mason do prepend
  -- vim.env.PATH = mason_bin .. (vim.fn.has('win32') == 1 and ';' or ':') .. vim.env.PATH

  -- local mok, mason = pcall(require, 'mason')
  -- if mok then mason.setup({}) end

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
-- stylua: ignore
function M.getClangdConfig()
  local new_root_dir = vim.uv.cwd() or '.'
  if not new_root_dir then return end

  -- 1. Safe defaults (Standard clangd behavior)
  local q_driver, merged_json = '**', ''
  -- local f_flags = [["-std=c++17", "-xc++"]]

  -- 2. Run your toolchain detection
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

  -- 3. Format your template string
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
  local name = 'clangd'
  OS.notify('LSP: Clangd restart.', 'warn')

  local clangConfig = M.getClangdConfig()

  vim.lsp.config(name, clangConfig)
  vim.lsp.enable(name, false)
  vim.lsp.enable(name, true)
  vim.cmd('checktime')
  _G.metadata.isBusy = false
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

--------------------------------------------------------------------------------
-- INFO: get_clangd_unknown_args
-- stylua: ignore
--------------------------------------------------------------------------------
---@param from string
function M.getUnknownArgs(from)
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
    -- OS.notify(from .. ' No source file found to check.', 'info')
    boilerplate_gen([[main.cpp]], vim.uv.cwd() .. '/src')
    boilerplate_gen([[main.hpp]], vim.uv.cwd() .. '/include')
    check_file = vim.uv.cwd() .. '/src/main.cpp'
    -- return
  else
    -- OS.notify(string.format('%s %s found to check.',from, check_file), 'info')
  end

  -- 3. SCAN: Run clangd (it will see all errors because .clangd is now empty)
  M.clangdIntall(function(clangdCmd)

    local cmd_str = string.format("%s --compile-commands-dir=. --check=%s --log=error", clangdCmd, check_file)
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

    -- local cmd = { clangdCmd, '--compile-commands-dir=.', '--check=' .. check_file, '--log=error' }
    -- vim.system(cmd, { text = true }, function(obj)
    --   vim.schedule(function()
    --     local output = (obj.stdout or '') .. (obj.stderr or '')
    --     local args_table = {}
    --
    --     -- Extract anything clangd reports as an 'unknown argument'
    --     if not string.find(output, "%.clang%-format") then
    --       for arg in string.gmatch(output, "unknown argument[:%s]+'([^']+)'") do
    --         table.insert(args_table, string.format('"%s"', arg:gsub('[;%.]$', '')))
    --       end
    --     end
    --
    --     -- 4. UPDATE: Rebuild with the new discovered flags
    --     boilerplate.args = args_table
    --     boilerplate_gen('.clangd', vim.g.platformioRootDir)
    --
    --     OS.notify(from .. ' Clangd ✅Extracted ' .. #args_table .. ' flags.')
    --     M.restart()
    --   end)
    -- end)
  end, 'clangd')
end
--------------------------------------------------------------------------------

--stylua: ignore
--=============================================================================
function M.init(clangd)
  OS.notify('Clangd Control: initialize', "info")

  require('nvimpio.clangd.commands')

  if clangd.install then
    require('nvimpio.clangd.config')
  end
end

return M
