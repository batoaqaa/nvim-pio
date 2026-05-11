local control = require('nvimpio.clangd.control')
--------------------------------------------------------------------------------
-- ClangFormatterPick
vim.api.nvim_create_user_command('ClangFormatterPick', control.setFormatStyle, {})
-- ClangdCheckArgs
vim.api.nvim_create_user_command('ClangdCheckArgs', control.getUnknownArgs, {})
-- Clangdrestart
vim.api.nvim_create_user_command('Clangdrestart', control.restart, {})
--------------------------------------------------------------------------------
