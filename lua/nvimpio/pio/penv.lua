----------------------------------------------------------------------------------------
-- INFO: set up python nvim venv (virtual environment 'nenv'), activaten.
local platformio_core_dir, pynvim_env, pynvim_python, pynvim_lib, pynvim_bin, pynvim_activate
platformio_core_dir = vim.misc.joinPath(vim.env.HOME, '.platformio', vim.misc.pluginName)

if vim.missc.isWindows then
  platformio_core_dir = vim.env.HOME .. '/.platformio/nvim-pio'
  pynvim_env = platformio_core_dir .. '/penv'
  pynvim_bin = pynvim_env .. '/Scripts'
  pynvim_python = pynvim_bin .. '/python.exe'
  pynvim_activate = pynvim_bin .. '/Activate.ps1'
else
  platformio_core_dir = vim.env.HOME .. '/.platformio'
  pynvim_env = platformio_core_dir .. '/penv'
  pynvim_bin = pynvim_env .. '/bin'
  pynvim_python = pynvim_bin .. '/python3'
  pynvim_activate = pynvim_bin .. '/activate'
end

--Toolchain inclusion forced in Global Environment
-- vim.uv.os_setenv('PLATFORMIO_SETTING_COMPILATIONDB_INCLUDE_TOOLCHAIN', 'true')
vim.uv.os_setenv('PLATFORMIO_CORE_DIR', platformio_core_dir)
vim.g.python_host_prog = pynvim_python
vim.g.python3_host_prog = pynvim_python

local sep = (vim.fn.has('win32') == 1 and ';' or ':')
vim.env.PATH = pynvim_bin .. sep .. vim.env.PATH
vim.env.VIRTUAL_ENV = pynvim_env

if vim.fn.isdirectory(platformio_core_dir) == 0 then
  vim.fn.mkdir(platformio_core_dir, 'p')
  -- vim.fn.system({
  --   "wget",
  --   "https://raw.githubusercontent.com/platformio/platformio-core-installer/master/get-platformio.py",
  -- })
  -- vim.fn.system({ "python", "get-platformio.py" })
  -- os.execute((isWindows and "del " or "rm -f ") .. "get-platformio.py*")
end

local output, win_id
-- local expand_dir = vim.fn.expand(pynvim_env)
if not vim.uv.fs_stat(pynvim_env) then
  win_id = vim.misc.showMessage('************ PlatfromIO python env setup ************')
  if not vim.misc.isWindows then
    output = vim.fn.system({ 'python3', '-m', 'venv', pynvim_env })
    print(output)
    vim.fn.system({ 'chmod', '755', '-R', pynvim_bin })
    vim.fn.system('source ' .. pynvim_activate)
  else
    vim.fn.system({ 'python', '-m', 'venv', pynvim_env })
    vim.fn.system(pynvim_activate)
  end

  --------------------------------------------------------------------------------------
  -- INFO: install platformio and nvim required packages.
  output = vim.fn.system({ pynvim_python, '-m', 'pip', 'install', '-U', 'pip' })
  print(output)
  output = vim.fn.system({ pynvim_python, '-m', 'pip', 'install', 'pynvim' })
  print(output)
  vim.fn.system({ pynvim_python, '-m', 'pip', 'install', 'neovim' })
  vim.fn.system({ pynvim_python, '-m', 'pip', 'install', 'debugpy' })
  vim.fn.system({ pynvim_python, '-m', 'pip', 'install', 'isort' })
  vim.fn.system({ pynvim_python, '-m', 'pip', 'install', 'scons' })
  vim.fn.system({ pynvim_python, '-m', 'pip', 'install', 'sconscrip' })
  vim.fn.system({ pynvim_python, '-m', 'pip', 'install', 'yamllint' })
  vim.fn.system({ pynvim_python, '-m', 'pip', 'install', '-U', 'platformio' })
  -- vim.fn.system({ 'pip', 'install', '-U', 'platformio' })
  if win_id then
    vim.misc.closeMessage(win_id)
  end
end
