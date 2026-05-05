vim.misc = require('nvimpio.utils.misc')
vim.pio = require('nvimpio.pio.upkeep')
vim.clangd = require('nvimpio.clangd.control')

-- stylua: ignore
-- INFO: Pioini
vim.api.nvim_create_user_command('Pioinit',
  function()
  require('nvimpio.pioInit').pioInit()
  end,
  { force = true,
    desc = 'Start the PlatformIO guided setup wizard'
  }
)
