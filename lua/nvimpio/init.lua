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
  -- Activation: Turn on the plugin features
  local function activate()
    local state = require('nvimpio.pioCheck').state
    if state.is_activated then return end

    state.is_activated = true
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

  -- INFO: Pioini
  vim.api.nvim_create_user_command('Pioinit', function()
    pioCheck.pioStatus(function(success)
      if success then
        vim.pio = require('nvimpio.pio.upkeep')
        vim.misc = require('nvimpio.utils.misc')

        require('nvimpio.pio.ui.pioInit').pioInit(activate)

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
        if success then activate() end
      end, true)
    end)
  end
  -- pioCheck.pioStatus(function(success)
  --   if success then
  --     activate()
  --   end
  -- end, true)

end

return M
