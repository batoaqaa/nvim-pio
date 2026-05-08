--
-- stylua: ignore
-- INFO: Pioini
vim.api.nvim_create_user_command('Pioinit',
  function()
    require('nvimpio.pio.ui.pioInit').pioInit()
  end,
  {
    force = true,
    desc = 'Start the PlatformIO guided setup wizard'
  }
)
