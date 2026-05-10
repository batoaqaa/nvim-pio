local M = {}

local boilerplate = require('nvimpio.boilerplate')
local boilerplate_gen = boilerplate.boilerplate_gen

----------------------------------------------------------------------------------------
-- INFO: configure clangd lsp server
-----------------------------------------------------------------------------------------
---stylua: ignore
function M.clangdIntall(package_name, retry_count)
  package_name = package_name or 'clangd'
  retry_count = retry_count or 0
  local max_retries = 2
  local registry = require('mason-registry')

  registry.refresh(function()
    if not registry.has_package(package_name) then
      vim.notify('Mason: Package ' .. package_name .. ' not found in registry.', vim.log.levels.ERROR)
      return
    end

    local pkg = registry.get_package(package_name)

    -- 1. Success: Enable and exit
    if pkg:is_installed() then
      vim.schedule(function()
        -- vim.lsp.enable(package_name)
        M.restarti()
      end)
      return
    end

    -- 2. Already Installing: Hook into existing handle
    if pkg:is_installing() then
      vim.notify('Mason: Waiting for existing ' .. package_name .. ' install...', vim.log.levels.ERROR)

      vim.defer_fn(function()
        M.clangdIntall(package_name, retry_count)
      end, 5000)
      return
    end

    -- 3. INSTALL: Start fresh attempt
    vim.cmd('redraw')
    vim.notify(string.format('Mason: Installing %s (Attempt %d/%d)...', package_name, retry_count + 1, max_retries + 1), vim.log.levels.INFO)

    local handle = pkg:install()

    handle:once('closed', function()
      vim.schedule(function()
        if pkg:is_installed() then
          vim.cmd('redraw')
          vim.notify('Mason: ' .. package_name .. ' installed successfully!', vim.log.levels.INFO)
          M.restarti()
          -- vim.lsp.enable(package_name)
        else
          -- Failure/Incomplete Logic
          if retry_count < max_retries then
            vim.cmd('redraw')
            vim.notify(string.format('Mason: Install failed. Retrying in 2s... (%d/%d)', retry_count + 1, max_retries + 1), vim.log.levels.WARN)

            -- Wait 2 seconds before retrying to avoid spamming a broken connection
            vim.defer_fn(function()
              M.clangdIntall(package_name, retry_count + 1)
            end, 2000)
          else
            vim.cmd('redraw')
            vim.notify('Mason: All install attempts failed for ' .. package_name, vim.log.levels.ERROR)
          end
        end
      end)
    end)
  end)
end

-- Start the process
-- M.restart('clangd')

----------------------------------------------------------------------------------------
-- INFO: configure clangd lsp server
-----------------------------------------------------------------------------------------
--stylua: ignore
function M.getClangdConfig()
  local new_root_dir = vim.uv.cwd() or '.'
  if not new_root_dir then return end

  -- 1. Safe defaults (Standard clangd behavior)
  local q_driver, merged_json = '**', ''
  -- local f_flags = [["-std=c++17", "-xc++"]]

  -- 2. Run your toolchain detection
  if _G.metadata and _G.metadata.cc_compiler and _G.metadata.cc_compiler ~= '' then
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
  -- local formatted_str = string.format(table_config or '', q_driver, f_flags, vim.misc.normalizePath(new_root_dir))

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
  -- vim.schedule_wrap(function()
  vim.misc.notify('LSP: Clangd restart.', 'warn')

  local clangConfig = M.getClangdConfig()
  -- print(vim.inspect(clangConfig))
  vim.lsp.config(name, clangConfig)
  vim.lsp.enable(name, false)
  vim.lsp.enable(name, true)
  vim.cmd('checktime')
  _G.metadata.isBusy = false
  -- end)
end


-- INFO: set_clang_format_style()
--------------------------------------------------------------------------------
-- stylua: ignore
function M.setFormatStyle()
  local styles = { 'LLVM', 'Google', 'Chromium', 'Mozilla', 'WebKit', 'Microsoft', 'Linux' }

  vim.ui.select(styles, {
    prompt = 'Select Clang-Format base style:',
  }, function(choice)
    if not choice then return end

    -- 1. Generate the command (Windows compatible)
    local cmd = string.format('cmd /c "clang-format -style=%s -dump-config > .clang-format"', choice:lower())

    -- 2. Execute and check result
    local success = os.execute(cmd)

    if success then
      vim.misc.notify('Created .clang-format (' .. choice .. ')', "info")

      -- 3. Restart clangd to apply the new formatting rules
      -- Slight delay to ensure file is written before LSP restarts
      vim.defer_fn(function()
        M.restart()
        print('LSP Reloaded: Using ' .. choice .. ' style.')
      end, 100)
    else
      vim.misc.notify('Failed to generate .clang-format. Is clang-format in your PATH?', "error")
    end
  end)
end

-- stylua: ignore
local function get_clangd_cmd()
  -- 1. Try Mason Path first
  local mason_bin = vim.fs.joinpath(vim.fn.stdpath('data'), 'mason', 'bin')
  local clangd_mason = vim.fs.joinpath(mason_bin, 'clangd')

  if vim.fn.has('win32') == 1 then clangd_mason = clangd_mason .. '.cmd' end

  if vim.uv.fs_stat(clangd_mason) then return clangd_mason end

  -- This will work if clangd is in your system's LLVM/bin folder
  return 'clangd'
end
-- INFO: get_clangd_unknown_args()
--------------------------------------------------------------------------------
-- stylua: ignore
function M.getUnknownArgs()
  -- 1. RESET: Clear flags and rebuild .clangd (removes old 'Remove' block)
  boilerplate.args = {}
  boilerplate_gen('.clangd', vim.g.platformioRootDir)

  -- 2. FIND: Grab the first .cpp or .c file in /src
  local check_file = vim.fs.find(function(name)
    return name:match('%.cpp$') or name:match('%.c$')
  end, { limit = 1, path = vim.fn.getcwd() .. '/src' })[1]

  if not check_file then
    print('No source file found to check.')
    return
  end

  -- 3. SCAN: Run clangd (it will see all errors because .clangd is now empty)
  -- local cmd = { 'clangd', '--compile-commands-dir=.', '--check=' .. check_file, '--log=error' }
  local cmd = { get_clangd_cmd(), '--compile-commands-dir=.', '--check=' .. check_file, '--log=error' }

  vim.system(cmd, { text = true }, function(obj)
    vim.schedule(function()
      local output = (obj.stdout or '') .. (obj.stderr or '')
      local args_table = {}

      -- Extract anything clangd reports as an 'unknown argument'
      for arg in string.gmatch(output, "unknown argument[:%s]+'([^']+)'") do
        table.insert(args_table, string.format('"%s"', arg:gsub('[;%.]$', '')))
      end

      -- 4. UPDATE: Rebuild with the new discovered flags
      boilerplate.args = args_table
      boilerplate_gen('.clangd', vim.g.platformioRootDir)

      vim.misc.notify('Clangd: ✅Extracted ' .. #args_table .. ' flags.')
      M.restart()
    end)
  end)
end
--------------------------------------------------------------------------------

--stylua: ignore
--=============================================================================
function M.init(clangd)
  vim.misc.notify('Clangd: initialize', "info")

  require('nvimpio.clangd.commands')

  if clangd.install then
    require('nvimpio.clangd.config')
  end
end

return M
