local function install_platformio_in_venv()
  -- 1. Create a safe path for the venv inside Neovim's standard data directory
  local data_dir = vim.fn.stdpath('data')
  local venv_path = vim.fs.normalize(data_dir .. '/pio_venv')

  -- 2. Detect OS to map the correct Python binary location
  local is_win = vim.uv.os_uname().sysname:find('Windows') ~= nil
  local python_bin = is_win and venv_path .. '/Scripts/python.exe' or venv_path .. '/bin/python3'
  local pip_bin = is_win and venv_path .. '/Scripts/pip.exe' or venv_path .. '/bin/pip'

  print('Starting PlatformIO installation in isolated venv...')

  -- 3. Phase A: Create the virtual environment if it doesn't exist
  if vim.fn.isdirectory(venv_path) == 0 then
    print('Creating Python virtual environment...')
    vim.system({ 'python3', '-m', 'venv', venv_path }):wait()
  end

  -- 4. Phase B: Upgrade pip inside the venv to avoid warning logs
  print('Upgrading pip...')
  vim.system({ python_bin, '-m', 'pip', 'install', '-U', 'pip' }):wait()

  -- 5. Phase C: Run the core platformio installation synchronously
  print('Installing PlatformIO core packages...')
  local obj = vim.system({ pip_bin, 'install', '-U', 'platformio' }):wait()

  -- 6. Verify result
  if obj.code == 0 then
    print('PlatformIO successfully installed inside Neovim venv!')
    print('Binary path: ' .. python_bin)
  else
    print('PlatformIO setup failed with exit code: ' .. obj.code)
    if obj.stderr then
      print('Error details: ' .. obj.stderr)
    end
  end
end

return {
  pioUpgrade = install_platformio_in_venv,
}
-- Create a user command so you can trigger it via `:InstallPIO`
-- vim.api.nvim_create_user_command("InstallPIO", install_platformio_in_venv, {})
