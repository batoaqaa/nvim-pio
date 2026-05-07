local M = {}

function M.check()
  vim.health.start('PlatformIO Check')

  -- 1. Check Python installation
  local python = vim.fn.has('win32') == 1 and 'python' or 'python3'
  if vim.fn.executable(python) == 1 then
    vim.health.ok('Python is available: ' .. python)
  else
    vim.health.error('Python is not found. PlatformIO requires Python.')
  end

  -- 2. Check Binary Path
  local installer = require('nvimpio.pio.installer')
  local pio_bin = installer.get_pio_bin_dir()
  if vim.fn.isdirectory(pio_bin) == 1 then
    vim.health.ok('PlatformIO core directory exists: ' .. pio_bin)
  else
    vim.health.warn('PlatformIO core directory not found. Have you run :PioInstall?')
  end

  -- 3. Check Executable and Version
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
end

return M
