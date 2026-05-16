require('nvimpio.osInfo')

local pio = require('nvimpio.pioCheck')
local val = require('nvimpio.validator')
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
M.defaults = require('nvimpio.defConfig')

local pioCheck = require('nvimpio.pioCheck')

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
    menu.buildUsserMenu(M.config)

    require('nvimpio.pio.control').init(M.config.clangd)
  end

  -- INFO: Pioini
  vim.api.nvim_create_user_command('Pioinit', function()
    require('platformio.core').ensure_toolchain_active(
      -- pioCheck.pioStatus(
      function(success)
        if success then
          if M.isActivated then
            require('nvimpio.pio.ui.pioInit').pioInit()
          else
            vim.g.platformioRootDir = vim.uv.cwd()
            -- pioCheck.pioPathUpdate()
            require('nvimpio.pio.ui.pioInit').pioInit(function(done)
              if done then
                -- vim.clangd.getUnknownArgs()
                -- if M.config.clangd.install then require('nvimpio.clangd.config') end
                activate()
              end
            end)
          end
        else
        end
      end,
      false
    )
  end, {
    force = true,
    desc = 'Start the PlatformIO guided setup wizard',
  })

  -- The background auto-activation
  if vim.fn.filereadable('platformio.ini') == 1 then
    vim.schedule(function()
      pioCheck.pioStatus(function(success)
        if success then
          activate()
        end
      end, true)
    end)
  end
end

return M
