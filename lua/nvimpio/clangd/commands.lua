local control = require('nvimpio.clangd.control')
--------------------------------------------------------------------------------
-- INFO: ClangFormatterPick
vim.api.nvim_create_user_command('ClangFormatterPick', control.setFormatStyle, {})

-- INFO: ClangdCheckArgs
vim.api.nvim_create_user_command('ClangdCheckArgs', function(_)
  -- control.getUnknownArgsGui('userCommand: ')
  control.getUnknownArgsCli('userCommand: ')
end, {})

-- INFO: Clangdrestart
vim.api.nvim_create_user_command('Clangdrestart', control.restart, {})
