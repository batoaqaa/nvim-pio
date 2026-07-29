local M = {}

function M.check()
  vim.health.start('nvimpio Check')

  -- INFO: main.hpp
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
  local is_ready = OS.pioReady('pio', true) -- force check for health report
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

  -- if vim.fn.executable('pio') == 1 then
  --   -- Run pio --version synchronously for the health report
  --   local obj = vim.system({ 'pio', '--version' }, { text = true }):wait()
  --   if obj.code == 0 then
  --     vim.health.ok('PlatformIO executable found: ' .. vim.trim(obj.stdout))
  --   else
  --     vim.health.error('PlatformIO found but failed to execute: ' .. (obj.stderr or 'Unknown error'))
  --   end
  -- else
  --   vim.health.error("PlatformIO 'pio' command not found in PATH.", {
  --     'Try running :PioInstall',
  --   })
  -- end

  -- 4. Check clangd installation
  ----------------------------------------------------------------------------------------
  if vim.fn.executable('clangd') == 1 then
    -- Run clangd --version synchronously for the health report
    local full_path = vim.fn.exepath('clangd')
    local obj = vim.system({ full_path, '--version' }, { text = true }):wait()
    if obj.code == 0 then
      vim.health.ok('clangd executable found: ' .. vim.trim(obj.stdout:match('[^\n]+'):match('^(.-)%s*%(')))
      vim.health.ok('clangd executable directory: ' .. vim.fn.fnamemodify(full_path, ':h'))
    else
      vim.health.error('clangd found but failed to execute: ' .. (obj.stderr or 'Unknown error'))
    end
  else
    vim.health.error("Clangd 'clangd' command not found in PATH.", {
      'Try running :Mason',
      "Ensure your config calls require('nvimpio').setup()",
    })
  end
end

return M
