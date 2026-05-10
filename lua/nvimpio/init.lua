local M = {}

M.config = require('nvimpio.defConfig')
local userConfig = require('nvimpio.userConfig')
local pioCheck = require('nvimpio.pioCheck')

local user_config = {}
-- INFO:
--stylua: ignore
-------------------------------------------------------------------------------
function M.setup(opts)
  vim.g.platformioRootDir = vim.uv.cwd()
  local state = require('nvimpio.pioCheck').state

  -- Activation: Turn on the plugin features
  local function activate()
    if state.isActivated then return end

    state.isActivated = true
    vim.notify('NVIM-PIO: Features Activated', vim.log.levels.INFO)

    local sep = vim.fn.has('win32') == 1 and ';' or ':'
    if M.config.pio.auto_update_path then
      local pio_bin = pioCheck.get_bin_dir()
      if vim.fn.isdirectory(pio_bin) == 1 then vim.env.PATH = pio_bin .. sep .. vim.env.PATH end
    end

    if opts then user_config = opts end
    userConfig.validate(user_config)
    M.config = vim.tbl_deep_extend('force', M.config, user_config or {})
    userConfig.buildUsserMenu(M.config)

    require('nvimpio.pio.control').init(M.config.clangd)
  end

  -- -- INFO: Pioini
  -- vim.api.nvim_create_user_command('Pioinit', function()
  --   pioCheck.pioStatus(function(success)
  --     if success then
  --       vim.pio = require('nvimpio.pio.upkeep')
  --       vim.misc = require('nvimpio.utils.misc')
  --       vim.clangd = require('nvimpio.clangd.control')
  --
  --       require('nvimpio.pio.ui.pioInit').pioInit(function ()
  -- if M.config.clangd.install then
  --   require('nvimpio.clangd.config')
  -- end
  --         require('nvimpio.clangd.control').clangdIntall()
  --         -- vim.clangd.getUnknownArgs()
  --         activate()
  --       end)
  --
  --       -- activate()
  --     end
  --   end, false)
  -- end, {
  --   force = true,
  --   desc = 'Start the PlatformIO guided setup wizard',
  -- })

  -- INFO: Pioini
  vim.api.nvim_create_user_command('Pioinit', function()
    pioCheck.pioStatus(function(success)
      if success then
        if state.isActivated then
          print('isActivated1')
          require('nvimpio.pio.ui.pioInit').pioInit()
        else
          print('isActivated0')
          vim.pio = require('nvimpio.pio.upkeep')
          vim.misc = require('nvimpio.utils.misc')
          vim.clangd = require('nvimpio.clangd.control')

          require('nvimpio.pio.ui.pioInit').pioInit(function ()
          print('isActivated01')
            require('nvimpio.clangd.control').clangdIntall()
            if M.config.clangd.install then
              print('isActivated012')
              require('nvimpio.clangd.config')
            end
            vim.clangd.getUnknownArgs()
            activate()
          end)
        end

        -- activate()
      end
    end, false)
  end, {
    force = true,
    desc = 'Start the PlatformIO guided setup wizard',
  })


  -- The background auto-activation
  if vim.fn.filereadable('platformio.ini') == 1 then
    vim.schedule(function()
      pioCheck.pioStatus(function(success)
        if success then
          if not state.isActivated then
            vim.pio = require('nvimpio.pio.upkeep')
            vim.misc = require('nvimpio.utils.misc')
            vim.clangd = require('nvimpio.clangd.control')

          end
          activate()
        end
      end, true)
    end)
  end
end

return M
