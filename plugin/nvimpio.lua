--
-- -- stylua: ignore
-- -- INFO: Pioini
-- vim.api.nvim_create_user_command('Pioinit',
--   function()
--     require('nvimpio.pio.ui.pioInit').pioInit()
--   end,
--   {
--     force = true,
--     desc = 'Start the PlatformIO guided setup wizard'
--   }
-- )
-- INFO: Pioini
vim.api.nvim_create_user_command('Pioinit', function()
  local pioCheck = require('nvimpio.pioCheck')
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
