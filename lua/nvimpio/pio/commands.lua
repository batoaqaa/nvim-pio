-- Vim nargs options
-- 0: No arguments.
-- 1: Exactly one argument.
-- ?: Zero or one argument.
-- *: Any number of arguments (including none).
-- +: At least one argument.
-- -1: Zero or one argument (like ?, explicitly).

-- stylua: ignore start
local pio_mon = require('nvimpio.device.terminal').mon
local pio_cli = require('nvimpio.device.terminal').cli
local function sendCmnd(command)
  -- Directly pull the raw pointer reference from the table object.
  -- 0% CPU cycles wasted running window layout functions! [INDEX]

  -- The custom internal Lazy-Spawn Guard takes care of everything!
  -- If it's closed, it opens it. If it's open, it pipes it straight down! [INDEX]
  pio_cli:show()
  pio_cli:send(command)
end

-- INFO: update/generate compileDB
----------------------------------------------------------------
vim.api.nvim_create_user_command('PioCompileDB', function()
  -- require('nvimpio.pio.upkeep.cli').buildCompileDB(':PioCompileDB', _G.metadata.active_env)
  require('nvimpio.pio.ui.pioCompileDB').pioCompileDB()
end, { desc = "Install PlatformIO Core" })


-- INFO: Switch Environment
vim.api.nvim_create_user_command('PioPickEnv', function()
  require('nvimpio.pio.ui.activeEnvPicker').select_env_picker()
end, { desc = 'Switch [E]nvironment' })

-- INFO: PlatformIO installation
----------------------------------------------------------------
vim.api.nvim_create_user_command('PioUpgrade', function()
    require('nvimpio.pio.ui.pioUpgrade').pioUpgrade()
end, { desc = "upgrade PlatformIO Core" })


-- INFO: PlatformIO installation
----------------------------------------------------------------
-- vim.api.nvim_create_user_command('PioInstall', function()
--     require('nvimpio.pio.ui.pioInstall').pioInstall()
-- end, { desc = "Install PlatformIO Core" })
--
vim.api.nvim_create_user_command('PioInstall', function()
  vim.g.platformioRootDir = vim.uv.cwd()
  -- require("nvimpio.core").execute_init(args)
  require('nvimpio.core').ensure_toolchain_active(
    -- pioCheck.pioStatus(
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
  -- end, false)
end, {
  force = true,
  desc = 'Start the PlatformIO guided install wizard',
})


-- INFO: manage gitignore
------------------------------------------------------
vim.api.nvim_create_user_command('PioGitIgnore',
  function()
    require('nvimpio.pio.ui.pioGitIgnore').pioGitIgnore()
  end,
  {
    force = true,
    desc = 'add/remove files/folder to/from gitignore'
  }
)

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
vim.api.nvim_create_user_command('PioDbFixPaths', function()
  require('nvimpio.pio.upkeep').compile_commandsFix()
end, {})

--INFO: Piorun
------------------------------------------------------
vim.api.nvim_create_user_command('Piorun', function(opts)
  local args = opts.args
  require('nvimpio.pio.cli').piorun({ args })
end, {
  nargs = '?',
  -- Autocompletion options
  complete = function(_, _, _) return { 'upload', 'uploadfs', 'build', 'clean' } end,
})


-- Add this command registry string helper directly to your setup hooks
vim.api.nvim_create_user_command('PioSelectPort', function()
  -- Adjust path string reference below to point to wherever you saved the wrapper function
  require('nvimpio.pio.upkeep').configure_hardware_parameters()
end, { force = true })


--INFO: Piomon    Piomon monitor terminal
-- piolsserial.sync_ttylist()
vim.api.nvim_create_user_command('Piomon', function(opts)
  local args = opts.fargs
  pio_mon:show()
  pio_mon:send(args)
end, {
  nargs = '*',
  complete = function(_, cmd_line)
    local ports = require('nvimpio.pio.upkeep').get_connected_ports()
    local parts = vim.split(cmd_line, '%s+')
    local BAUD = { '4800', '9600', '57600', '115200' }
    if #parts == 2 then return BAUD end
    if #parts == 3 then return ports end
    return {}
  end,
})

--INFO: Piolsserial
vim.api.nvim_create_user_command('PioDevList', function()
  local cmd_table = {'device', 'list'}
  sendCmnd(cmd_table)
  -- require('nvimpio.pio.cli').piocmd(cmd_table)
  -- print(vim.inspect(require('nvimpio.pio.upkeep').get_connected_ports()))
end, {})

--INFO: Piolib
vim.api.nvim_create_user_command('Piolib', function(opts)
  local args = vim.split(opts.args, ' ')
  require('nvimpio.pio.ui.piolib').piolib(args)
end, {
  nargs = '+',
})

--INFO: Piocli    Piocli cli terminal
vim.api.nvim_create_user_command('Piocli', function(opts)
  local cmd_table = vim.split(opts.args, ' ')
  sendCmnd(cmd_table)
  -- require('nvimpio.pio.cli').piocli(cmd_table)
end, {
  nargs = '*',
})

--INFO: Piodebug
vim.api.nvim_create_user_command('Piodebug', function()
  require('nvimpio.pio.cli').piodebug()
end, {})

-- stylua: ignore end
