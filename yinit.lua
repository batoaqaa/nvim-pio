local M = {}

M.config = { pio_bin_dir = nil, pio_storage_dir = nil }
M.options = nil

-- Minimal primitive defaults to ensure the commands can register safely
M.defaults = {
  pio = {
    pio_runtime_dir = (vim.fn.has('win32') == 1 and os.getenv('USERPROFILE') or vim.uv.os_homedir() or '/root')
      .. (vim.fn.has('win32') == 1 and '\\.platformio' or '/.platformio'),
    pio_storage_dir = (vim.fn.has('win32') == 1 and os.getenv('USERPROFILE') or vim.uv.os_homedir() or '/root')
      .. (vim.fn.has('win32') == 1 and '\\.platformio' or '/.platformio'),
  },
  menu_key = '<leader>\\',
  menu_name = 'PlatformIO',
}

-- The absolute first-pass boot setup hook (Runs on editor startup)
function M.setup(user_opts)
  user_opts = user_opts or {}

  -- Lock down the user's configuration parameters in global module memory instantly
  M.options = vim.deepcopy(user_opts)

  -- Register global proxy commands so they are ALWAYS available in any empty folder
  vim.api.nvim_create_user_command('Pioinit', function(args)
    -- DYNAMIC LAZY-LOAD TRIGGER:
    -- Only require the core execution workspace engine when the command is run!
    require('platformio.core').execute_init(args)
  end, { nargs = '*' })

  vim.api.nvim_create_user_command('PioSetupPaths', function()
    require('platformio.core').configure_paths()
  end, {})
end

return M
