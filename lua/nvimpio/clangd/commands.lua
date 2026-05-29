local control = require('nvimpio.clangd.control')
--------------------------------------------------------------------------------
-- INFO: ClangFormatterPick
vim.api.nvim_create_user_command('ClangFormatterPick', control.setFormatStyle, {})

-- INFO: ClangdCheckArgs
vim.api.nvim_create_user_command('ClangdCheckArgs', function(_)
  control.getUnknownArgsGui('userCommand: ')
end, {})

-- INFO: Clangdrestart
vim.api.nvim_create_user_command('Clangdrestart', control.restart, {})

-- INFO: ClangdDiagnosticBlock
vim.api.nvim_create_user_command('ClangdDiagnosticBlock', require('nvimpio.clangd.diagnostic').manage_file_diagnostics_interactive, {})

-- -- INFO: ClangdDiagnosticUnblock
-- vim.api.nvim_create_user_command('ClangdDiagnosticUnblock', require('nvimpio.clangd.diagnostic').review_and_clear_filters_interactive, {})
