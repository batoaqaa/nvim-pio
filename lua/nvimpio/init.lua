local M = {}

M.config = require('nvimpio.defConfig')
local userConfig = require('nvimpio.userConfig')
local pioCheck = require('nvimpio.pioCheck')

-- INFO: Pioini
vim.api.nvim_create_user_command('Pioinit', function()
  pioCheck.isInstalled(function(success)
    if success then
      vim.g.platformioRootDir = vim.uv.cwd()
      vim.pio = require('nvimpio.pio.upkeep')
      vim.misc = require('nvimpio.utils.misc')
      vim.clangd = require('nvimpio.clangd.control')
      require('nvimpio.pio.ui.pioInit').pioInit()
    end
  end)
end, {
  force = true,
  desc = 'Start the PlatformIO guided setup wizard',
})

local user_config = {}
-- INFO:
--stylua: ignore
-------------------------------------------------------------------------------
function M.setup(opts)
  if opts then user_config = opts end
  userConfig.validate(user_config)
  -- M.config = vim.tbl_deep_extend('force', M.config, user_config or {})
  --
  -- menu.buildMenu(M.config)

  -- stylua: ignore
  -- stylua: ignore
  local function startPluginInternals(success)
    local sep = vim.fn.has('win32') == 1 and ';' or ':'
    if success then
      vim.g.platformioRootDir = vim.fn.getcwd()

      vim.pio = require('nvimpio.pio.upkeep')
      vim.misc = require('nvimpio.utils.misc')
      vim.clangd = require('nvimpio.clangd.control')
      if M.config.pio.auto_update_path then
        local pio_bin = pioCheck.get_bin_dir()
        if vim.fn.isdirectory(pio_bin) == 1 then vim.env.PATH = pio_bin .. sep .. vim.env.PATH end
      end
      M.config = vim.tbl_deep_extend('force', M.config, user_config or {})
      userConfig.buildUsserMenu(M.config)
      require('nvimpio.pio.control').init(M.config.clangd)
    end
  end
  M.pioCheck(startPluginInternals)
end

return M
