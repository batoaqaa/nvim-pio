
-- stylua: ignore
-- INFO: Pioini
vim.api.nvim_create_user_command('Pioinit',
  function()
    vim.misc = require('nvimpio.utils.misc')
    vim.pio = require('nvimpio.pio.upkeep')
    vim.clangd = require('nvimpio.clangd.control')
    require('nvimpio.pioInit').pioInit()
  end,
  {
    force = true,
    desc = 'Start the PlatformIO guided setup wizard'
  }
)
--
-- if vim.fn.filereadable('platformio.ini') == 1 then
--   -- If the file is there, wake up the plugin immediately
--   require('nvimpio').setup()
-- else
--   -- If not, set a one-time listener to wake up if the file appears later
--   vim.api.nvim_create_autocmd({ 'BufReadPost', 'BufNewFile' }, {
--     group = vim.api.nvim_create_augroup('PioActivation', { clear = true }),
--     pattern = 'platformio.ini',
--     callback = function()
--       require('nvimpio').setup()
--       return true -- Delete this listener once triggered
--     end,
--   })
-- end
