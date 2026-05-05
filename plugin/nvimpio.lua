--
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
-- local function detect_and_load()
--   local cwd = vim.fn.getcwd()
--   local has_ini = vim.fn.filereadable('platformio.ini') == 1
--   local has_pio_dir = vim.fn.isdirectory('.pio') == 1
--
--   -- 1. The "Magic" Activation (The same as your cond logic)
--   if has_ini and has_pio_dir then
--     vim.g.platformioRootDir = cwd
--     require('nvimpio').setup() -- Wakes up the brain
--     return
--   end
--
--   -- 2. The Global "Pioinit" Bootstrap
--   -- This replaces the complex LazyRestore logic with a simple dynamic load
--   vim.api.nvim_create_user_command('Pioinit', function()
--     vim.g.platformioRootDir = vim.fn.getcwd()
--     require('nvimpio.pioInit').pioInit()
--
--     -- Once initialized, trigger the full setup
--     vim.schedule(function()
--       require('nvimpio').setup()
--     end)
--   end, { desc = 'Bootstrap PIO Project' })
-- end
--
-- detect_and_load()
