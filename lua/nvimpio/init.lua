require('nvimpio.osInfo')

-- local pio = require('nvimpio.pioCheck')
-- local val = require('nvimpio.validator')
local menu = require('nvimpio.menu')

local M = {}

M.isActivated = false -- Tracks if commands/features are loaded

-- Persistent internal storage for runtime verified properties
M.config = {
  pio_runtime_dir = nil, -- Absolute path to python/pio binaries directory
  pio_storage_dir = nil, -- Absolute path to core tracking directory
}

M.options = nil -- This will hold the complete configuration table safely in memory
-- PLUGIN CONFIGURATION DEFAULTS
-- M.defaults = require('nvimpio.defConfig')

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
-- local pioCheck = require('nvimpio.pioCheck')

-- INFO:
---stylua: ignore start
-------------------------------------------------------------------------------
function M.setup(user_opts)
  user_opts = user_opts or {}
  M.options = vim.deepcopy(user_opts)

  -- The global proxy commands are registered instantly with zero startup lag

  ------------------------------------------------------------------------
  -- Activation: Turn on the plugin features
  local function activate()
    if M.isActivated then
      return
    end

    M.isActivated = true
    vim.notify('NVIM-PIO: Features Activated', vim.log.levels.INFO)
    vim.g.platformioRootDir = vim.uv.cwd()

    -- pioCheck.pioPathUpdate()
    -- local sep = vim.fn.has('win32') == 1 and ';' or ':'
    -- if M.config.pio.auto_update_path then
    --   local pio_bin = pioCheck.get_bin_dir()
    --   if vim.fn.isdirectory(pio_bin) == 1 then vim.env.PATH = pio_bin .. sep .. vim.env.PATH end
    -- end

    -- interface.validate(user_config)
    -- M.config = vim.tbl_deep_extend('force', defConfig, user_config or {})
    menu.buildUsserMenu(M.options)

    require('nvimpio.pio.control').init(M.options.clangd)
  end

  -- INFO: Pioini
  vim.api.nvim_create_user_command('Pioinit', function()
    require('nvimpio.core').ensure_toolchain_active(
      -- pioCheck.pioStatus(
      function(success)
        if success then
          vim.g.platformioRootDir = vim.uv.cwd()
          -- pioCheck.pioPathUpdate()
          require('nvimpio.pio.ui.pioInit').pioInit(function(done)
            if done then
              -- vim.clangd.getUnknownArgs()
              -- if M.config.clangd.install then require('nvimpio.clangd.config') end
              activate()
            end
          end)
        else
        end
      end,
      0
    )
    -- end, false)
  end, {
    force = true,
    desc = 'Start the PlatformIO guided setup wizard',
  })

  -- The background auto-activation
  if vim.fn.filereadable('platformio.ini') == 1 then
    vim.schedule(function()
      -- pioCheck.pioStatus(
      require('nvimpio.core').ensure_toolchain_active(function(success)
        if success then
          activate()
        end
      end, 0)
      -- end, true)
    end)
  end
end

return M
