-- ftdetect/pio.lua
vim.api.nvim_create_autocmd({ 'BufRead', 'BufNewFile' }, {
  pattern = 'platformio.ini',
  callback = function()
    -- This sets a custom filetype
    vim.bo.filetype = 'platformio'
    -- This tells lazy.nvim to load the plugin NOW
    require('lazy').load({ plugins = { 'nvim-pio' } })
  end,
})
