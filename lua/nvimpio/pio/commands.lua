-- Vim nargs options
-- 0: No arguments.
-- 1: Exactly one argument.
-- ?: Zero or one argument.
-- *: Any number of arguments (including none).
-- +: At least one argument.
-- -1: Zero or one argument (like ?, explicitly).

-- stylua: ignore start
local upkeep = require('nvimpio.pio.upkeep')
local cmd = vim.api.nvim_create_user_command



-- INFO: Refresh PIO Data
cmd('PioRefreshData', function ()
   _G.isBusy = true
   local pio_refresh = upkeep.pio_refresh
   pio_refresh(function(success)
     if success then do end end
     _G.isBusy = false
   end, 'PIO refresh command: ')
end, {desc = 'Refresh PIO metadata'})


-- INFO: PlatformIO installation
----------------------------------------------------------------
-- cmd('PioInstall', function()
--     require('nvimpio.pio.ui.pioInstall').pioInstall()
-- end, { desc = "Install PlatformIO Core" })
--
cmd('PioInstall', function()
  vim.g.platformioRootDir = vim.uv.cwd()
  require('nvimpio.core').ensure_toolchain_active(
    function(success)
      if success then
        ---@type NvimPio
        local nvimpio = require('nvimpio')
        nvimpio.activate()
      else
      end
    end,
    0
  )
end, {
  force = true,
  desc = 'Start the PlatformIO guided install wizard',
})


-- INFO: manage gitignore
------------------------------------------------------
cmd('PioGitIgnore', function() require('nvimpio.pio.ui.pioGitIgnore').pioGitIgnore()
  end, { force = true, desc = 'add/remove files/folder to/from gitignore' })

-- -- INFO: List ToggleTerminals
-- ------------------------------------------------------
-- cmd('PioTermList',
--   function()
--     require('nvimpio.pio.ui.pioTermList').pioTermList()
--   end,
--   {
--     force = true,
--     desc = 'Start the PlatformIO Terminals list'
--   }
-- )

--INFO: fix paths in compile_commands.json
------------------------------------------------------

--INFO: Piorun
------------------------------------------------------
cmd('Piorun', function(opts) local args = opts.args require('nvimpio.pio.cli').piorun({ args })
end, { nargs = '?', complete = function(_, _, _) return { 'upload', 'uploadfs', 'build', 'clean' } end, })

-- Add this command registry string helper directly to your setup hooks
cmd('Piomon', function(opts) local args = opts.fargs require('nvimpio.pio.cli').piomon(args)
end, {
  nargs = '*',
  complete = function(_, cmd_line)
    local ports = upkeep.get_connected_ports()
    local parts = vim.split(cmd_line, '%s+')
    local BAUD = { '4800', '9600', '57600', '115200' }
    if #parts == 2 then return BAUD end
    if #parts == 3 then return ports end
    return {}
  end,
})

cmd('PioCompileDB', function() require('nvimpio.pio.ui.pioCompileDB').pioCompileDB() end, { desc = "Install PlatformIO Core" })
cmd('PioPickEnv', function() require('nvimpio.pio.ui.activeEnvPicker').select_env_picker() end, { desc = 'Switch [E]nvironment' })
cmd('PioRepair', function() require('nvimpio.pio.ui.pioRepair').pioRepair() end, { desc = "repair PlatformIO Core" })
cmd('PioUpgrade', function() local cmd_table = {'upgrade'} require('nvimpio.pio.cli').piocli(cmd_table) end, {})
cmd('PioSelectPort', function() upkeep.configure_hardware_parameters() end, { force = true })
cmd('PioDbFixPaths', function() upkeep.compile_commandsFix() end, {})
cmd('PioDevList', function() local cmd_table = {'device', 'list'} require('nvimpio.pio.cli').piocli(cmd_table) end, {})
cmd('Piolib', function(opts) local args = vim.split(opts.args, ' ') require('nvimpio.pio.ui.piolib').piolib(args) end, { nargs = '+', })
cmd('Piocli', function(opts) local cmd_table = vim.split(opts.args, ' ') require('nvimpio.pio.cli').piocli(cmd_table) end, { nargs = '*', })
cmd('Piodebug', function() require('nvimpio.pio.cli').piodebug() end, {})

-- stylua: ignore end
