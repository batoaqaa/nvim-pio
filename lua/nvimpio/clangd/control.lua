local M = {}

local boilerplate = require('nvimpio.boilerplate')
local boilerplate_gen = boilerplate.boilerplate_gen

-- INFO: clangdRestart()
--------------------------------------------------------------------------------
--- stylua: ignore
function M.restart()
  local name = 'clangd'
  -- vim.schedule_wrap(function()
  vim.notify('LSP: Clangd restart.', vim.log.levels.WARN)

  local clangConfig = _G.getClangdConfig()
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
      vim.notify('Created .clang-format (' .. choice .. ')', vim.log.levels.INFO)

      -- 3. Restart clangd to apply the new formatting rules
      -- Slight delay to ensure file is written before LSP restarts
      vim.defer_fn(function()
        M.restart()
        print('LSP Reloaded: Using ' .. choice .. ' style.')
      end, 100)
    else
      vim.notify('Failed to generate .clang-format. Is clang-format in your PATH?', vim.log.levels.ERROR)
    end
  end)
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
  local cmd = { 'clangd', '--compile-commands-dir=.', '--check=' .. check_file, '--log=error' }

  vim.system(cmd, { text = true }, function(obj)
    local output = (obj.stdout or '') .. (obj.stderr or '')
    local args_table = {}

    -- Extract anything clangd reports as an 'unknown argument'
    for arg in string.gmatch(output, "unknown argument[:%s]+'([^']+)'") do
      table.insert(args_table, string.format('"%s"', arg:gsub('[;%.]$', '')))
    end

    -- 4. UPDATE: Rebuild with the new discovered flags
    vim.schedule(function()
      boilerplate.args = args_table
      boilerplate_gen('.clangd', vim.g.platformioRootDir)

      M.restart()
      print('✅ Done: Extracted ' .. #args_table .. ' flags.')
    end)
  end)
end
--------------------------------------------------------------------------------

--stylua: ignore
--=============================================================================
function M.init()
  vim.notify('Clangd LSP: initialize', vim.log.levels.INFO, { title = 'nvim-pio' })

  require('nvimpio.clangd.config')
  local config = require('nvimpio').config
  if config.lspClangd.attach.enabled then
    require('nvimpio.clangd.attach')
  end
  require('nvimpio.clangd.commands')
end

return M
