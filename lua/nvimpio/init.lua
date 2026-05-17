-- stylua: ignore start
require('nvimpio.osInfo')

-- local pio = require('nvimpio.pioCheck')
-- local val = require('nvimpio.validator')
local menu = require('nvimpio.menu')

local M = {}

M.isActivated = false -- Tracks if commands/features are loaded

-- Persistent internal storage for runtime verified properties
M.config = { pio_runtime_dir = nil, pio_storage_dir = nil, }
M.options = nil -- This will hold the complete configuration table safely in memory

-- Minimal primitive defaults to ensure the commands can register safely
M.defaults = require('nvimpio.defConfig')
-- local pioCheck = require('nvimpio.pioCheck')

-- INFO:
---stylua: ignore start
-------------------------------------------------------------------------------
function M.setup(user_opts)
  user_opts = user_opts or {}
  M.options = vim.deepcopy(user_opts)

  ------------------------------------------------------------------------
  -- Activation: Turn on the plugin features
  local function activate()
    if M.isActivated then return end

    M.isActivated = true
    vim.notify('NVIM-PIO: Features Activated', vim.log.levels.INFO)

    -- require("nvimpio.core").initialize_full_options()
    menu.buildUserMenu(M.options)
    require('nvimpio.pio.control').init(M.options.clangd)
  end

  -- INFO: Pioini
  vim.api.nvim_create_user_command('Pioinit', function()
    vim.g.platformioRootDir = vim.uv.cwd()
    -- require("nvimpio.core").execute_init(args)
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
    vim.g.platformioRootDir = vim.uv.cwd()
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
