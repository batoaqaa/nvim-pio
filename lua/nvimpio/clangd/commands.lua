local control = require('nvimpio.clangd.control')
--------------------------------------------------------------------------------
-- INFO: ClangFormatterPick
vim.api.nvim_create_user_command('ClangFormatterPick', function()
  control.setFormatStyle()
end, {})

-- INFO: ClangdCheckArgs
vim.api.nvim_create_user_command('ClangdCheckArgs', function()
  -- control.getUnknownArgsGui('userCommand: ')
  control.getUnknownArgsCli('userCommand: ')
end, {})

-- INFO: Clangdrestart
vim.api.nvim_create_user_command('Clangdrestart', function()
  control.restart()
end, {})
