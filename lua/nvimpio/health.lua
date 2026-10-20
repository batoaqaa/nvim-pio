local M = {}

function M.check()
  vim.health.start('nvimpio Check')

  --- stylua: ignore
  -- 1. Check Python installation
  ----------------------------------------------------------------------------------------
  local python = OS.is_win and 'python' or 'python3'
  if vim.fn.executable(python) == 1 then
    vim.health.ok('Python is available: ' .. python)
  else
    vim.health.error('Python is not found. PlatformIO requires Python.')
  end

  -- 2. Check PIO Binary Path
  ----------------------------------------------------------------------------------------
  local pio_bin = require('nvimpio').config.pio_runtime_dir
  local target_penv = vim.fs.normalize(vim.fs.joinpath(pio_bin, 'penv'))
  if vim.fn.isdirectory(target_penv) == 1 then
    vim.health.ok('PlatformIO PENV directory exists: ' .. target_penv)
  else
    vim.health.warn('PlatformIO PENV directory not found. Have you run :PioInstall?')
  end

  -- 3. Check Executable and Version
  ----------------------------------------------------------------------------------------
  local is_ready = OS.pioReady('pio', false) -- force check for health report
  if is_ready then
    vim.health.ok('PlatformIO is ready and working: ' .. (OS.pio_version() or ''))
  else
    if vim.fn.executable('pio') ~= 1 then
      vim.health.error("PlatformIO 'pio' command not found in PATH.", {
        'Try running :PioInstall',
        'Or install PlatformIO Core: https://docs.platformio.org/en/latest/core/installation.html',
      })
    else
      vim.health.error('PlatformIO executable found but not working properly.', {
        'Try running :PioInstall to reinstall',
        'Check if PlatformIO core is corrupted',
      })
    end
  end

  -- 4. Check clangd installation
  ----------------------------------------------------------------------------------------
  if vim.fn.executable('clangd') == 1 then
    -- Normalize path separators dynamically (converts Windows backslashes to clean forward slashes)
    local full_path = vim.fs.normalize(vim.fn.exepath('clangd'))
    vim.health.ok('clangd executable found: ' .. full_path)

    -- LAYER 1: Verify runtime activation using modern Neovim 0.11+ core wrappers
    -- -- In Nvim 0.11+, vim.lsp.is_enabled('name') safely audits global activation state natively
    -- local is_enabled = false
    -- if type(vim.lsp.is_enabled) == 'function' then
    --   is_enabled = vim.lsp.is_enabled('clangd')
    -- end
    --
    -- if is_enabled then
    --   vim.health.ok('LSP Core: clangd is active and successfully initialized via `vim.lsp.enable()`.')
    -- else
    --   vim.health.info("LSP Core: clangd configuration is registered but dormant. (Invoke `vim.lsp.enable('clangd')` to wake it).")
    -- end

    -- LAYER 2: Safely extract compilation version via strict timeout-defended sandbox
    -- An 800ms limit ensures a frozen background Windows indexer or a locked binary will never freeze the main editor UI thread
    local exec_ok, result = pcall(function()
      return vim.system({ full_path, '--version' }, { text = true, timeout = 800 }):wait()
    end)

    if exec_ok and result and result.code == 0 and result.stdout then
      -- FIXED CROSS-PLATFORM STRIP: Swapping to standard %c matches all control characters (newlines/carriage returns)
      -- This entirely avoids regex bracket escape bugs while handling Windows and Unix identically.
      local clean_version = result.stdout:gsub('%c', ' '):gsub('%s+', ' ')
      vim.health.ok('clangd runtime version: ' .. vim.trim(clean_version))
    else
      vim.health.warn('clangd executable found but failed to respond or return a version string within 800ms.')
    end

    -- LAYER 3: Delegate workspace attachments to the native core diagnostic manager
    -- Enforces clean separation of concerns without writing high-maintenance metatable loops
    -- vim.health.info('LSP Engine: For deep telemetry on active buffer logs and server capabilities, run: `:checkhealth vim.lsp`')
  else
    -- Multi-OS feedback suggestion array for missing system binaries
    local suggestions = { 'Install clangd via your operating system package manager or :Mason' }
    if OS.is_win then
      table.insert(suggestions, 'On Windows, make sure to add the clangd binary folder to your System Environment Variables PATH.')
    end

    vim.health.error("Clangd 'clangd' command not found in PATH.", suggestions)
  end
  -- if vim.fn.executable('clangd') == 1 then
  --   -- Run clangd --version synchronously for the health report
  --   local full_path = vim.fn.exepath('clangd')
  --   local obj = vim.system({ full_path, '--version' }, { text = true }):wait()
  --   if obj.code == 0 then
  --     vim.health.ok('clangd executable found: ' .. vim.trim(obj.stdout:match('[^\n]+'):match('^(.-)%s*%(')))
  --     vim.health.ok('clangd executable directory: ' .. vim.fn.fnamemodify(full_path, ':h'))
  --   else
  --     vim.health.error('clangd found but failed to execute: ' .. (obj.stderr or 'Unknown error'))
  --   end
  -- else
  --   vim.health.error("Clangd 'clangd' command not found in PATH.", {
  --     'Try running :Mason',
  --     "Ensure your config calls require('nvimpio').setup()",
  --   })
  -- end
end

return M
