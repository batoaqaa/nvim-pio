-- Vim nargs options
-- 0: No arguments.
-- 1: Exactly one argument.
-- ?: Zero or one argument.
-- *: Any number of arguments (including none).
-- +: At least one argument.
-- -1: Zero or one argument (like ?, explicitly).

-- stylua: ignore
-- INFO: PlatformIO installation
----------------------------------------------------------------
vim.api.nvim_create_user_command('Pioinstall', function()
    require('nvimpio.pio.installer').install()
end, { desc = "Install PlatformIO Core" })

-- Example Keymap (Optional: Plugin authors usually let users define this)
vim.keymap.set('n', '<leader>pi', ':PioInstall<CR>', { desc = 'PlatformIO Install' })


-- stylua: ignore
-- INFO: List ToggleTerminals
------------------------------------------------------
vim.api.nvim_create_user_command('PioTermList',
  function()
    require('nvimpio.pio.ui.pioTermList').pioTermList()
  end,
  {
    force = true,
    desc = 'Start the PlatformIO Terminals list'
  }
)

--INFO: fix paths in compile_commands.json
------------------------------------------------------
vim.api.nvim_create_user_command('Piofixpaths', function()
  vim.pio.compile_commandsFix()
end, {})

------------------------------------------------------
local piolsserial = require('nvimpio.pio.ui.piolsserial')

--INFO: Piorun
------------------------------------------------------
vim.api.nvim_create_user_command('Piorun', function(opts)
  local args = opts.args
  require('nvimpio.commands').piorun({ args })
end, {
  nargs = '?',
  complete = function(_, _, _)
    return { 'upload', 'uploadfs', 'build', 'clean' } -- Autocompletion options
  end,
})

--INFO: Piomon
-- piolsserial.sync_ttylist()
vim.api.nvim_create_user_command('Piomon', function(opts)
  local args = opts.fargs
  require('nvimpio.commands').piomon(args)
end, {
  nargs = '*',

  complete = function(_, cmd_line)
    local parts = vim.split(cmd_line, '%s+')
    local BAUD = { '4800', '9600', '57600', '115200' }
    local ports = {}
    for _, item in ipairs(piolsserial.tty_list) do
      table.insert(ports, item.port)
    end
    if #parts == 2 then
      return BAUD
    end
    if #parts == 3 then
      return ports
    end
    return {}
  end,
})

--INFO: Piolsserial
vim.api.nvim_create_user_command('Piolsserial', function()
  require('nvimpio.pio.ui.piolsserial').print_tty_list()
end, {})

--INFO: Piolib
vim.api.nvim_create_user_command('Piolib', function(opts)
  local args = vim.split(opts.args, ' ')
  require('nvimpio.pio.ui.piolib').piolib(args)
end, {
  nargs = '+',
})

--INFO: Piocmdh    Piocmd horizontal terminal
vim.api.nvim_create_user_command('Piocmdh', function(opts)
  local cmd_table = vim.split(opts.args, ' ')
  require('nvimpio.commands').piocmd(cmd_table, 'horizontal')
end, {
  nargs = '*',
})

--INFO: Piocmdf    Piocmd float terminal
vim.api.nvim_create_user_command('Piocmdf', function(opts)
  local cmd_table = vim.split(opts.args, ' ')
  require('nvimpio.commands').piocmd(cmd_table, 'float')
end, {
  nargs = '*',
})

--INFO: Piodebug
vim.api.nvim_create_user_command('Piodebug', function()
  require('nvimpio.commands').piodebug()
end, {})
