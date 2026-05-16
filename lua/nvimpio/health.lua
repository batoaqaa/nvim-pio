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
  local pio = require('nvimpio.pioCheck')
  local pio_bin = pio.get_pio_bin_dir()
  if vim.fn.isdirectory(pio_bin) == 1 then
    vim.health.ok('PlatformIO core directory exists: ' .. pio_bin)
  else
    vim.health.warn('PlatformIO core directory not found. Have you run :PioInstall?')
  end

  -- 3. Check Executable and Version
  ----------------------------------------------------------------------------------------
  if vim.fn.executable('pio') == 1 then
    -- Run pio --version synchronously for the health report
    local obj = vim.system({ 'pio', '--version' }, { text = true }):wait()
    if obj.code == 0 then
      vim.health.ok('PlatformIO executable found: ' .. vim.trim(obj.stdout))
    else
      vim.health.error('PlatformIO found but failed to execute: ' .. (obj.stderr or 'Unknown error'))
    end
  else
    vim.health.error("PlatformIO 'pio' command not found in PATH.", {
      'Try running :PioInstall',
      "Ensure your config calls require('pio').setup()",
    })
  end

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
