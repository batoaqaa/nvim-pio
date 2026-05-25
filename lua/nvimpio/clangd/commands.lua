local control = require('nvimpio.clangd.control')
--------------------------------------------------------------------------------
-- ClangFormatterPick
vim.api.nvim_create_user_command('ClangFormatterPick', control.setFormatStyle, {})
-- ClangdCheckArgs
vim.api.nvim_create_user_command('ClangdCheckArgs', function(_)
  control.getUnknownArgsGui('userCommand: ')
end, {})
-- Clangdrestart
vim.api.nvim_create_user_command('Clangdrestart', control.restart, {})
-- INFO: ClangdDiagnosticBlock
----------------------------------------------------------------
vim.api.nvim_create_user_command('ClangdDiagnosticBlock', control.block_diagnostic_under_cursor, {})

--------------------------------------------------------------------------------
