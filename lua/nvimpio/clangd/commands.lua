local control = require('nvimpio.clangd.control')
--------------------------------------------------------------------------------
-- INFO: ClangdDiagnosticBlock
vim.api.nvim_create_user_command('ClangdFilter', function()
  require('nvimpio.clangd.diagnostic').manage_file_diagnostics_interactive()
end, {})

-- INFO: ClangFormatterPick
vim.api.nvim_create_user_command('ClangdFormatterPick', function()
  control.setFormatStyle()
end, {})

-- INFO: ClangdCheckArgs
vim.api.nvim_create_user_command('ClangdCheckArgs', function()
  control.getUnknownArgsCli('userCommand: ')
end, {})

-- INFO: Clangdrestart
vim.api.nvim_create_user_command('Clangdrestart', function()
  control.restart()
end, {})
