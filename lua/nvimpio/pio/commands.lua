-- stylua: ignore start
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


-- Create a distinct, isolated namespace for your plugin
local group = vim.api.nvim_create_augroup("PioFrameworkBufferShield", { clear = true })
vim.api.nvim_create_autocmd({ "BufReadPre", "BufNewFile" }, {
  group = group,
  -- Pattern matches both Unix forward-slash and Windows back-slash variants of .platformio
  pattern = { "*/.platformio*/**", "*\\.platformio*\\**" },
  callback = function(_)
    -- 1. Eliminate the locking mechanism entirely for framework/SDK files
    vim.opt_local.swapfile = false
    -- 2. Enforce safety: ensure users don't accidentally mutate core Zephyr/SDK code
    vim.opt_local.readonly = true
    -- 3. Optimization: Automatically clean the buffer from memory once closed
    vim.opt_local.bufhidden = "unload"
  end,
})
-- Fail-safe handler: In case an active background thread (like clangd) forces 
-- an early jump before BufReadPre strips the swap option.
vim.api.nvim_create_autocmd("SwapExists", {
  group = group,
  callback = function()
    local current_file = vim.fn.expand("%:p")
    -- If the path matches the internal platformio ecosystem, silently bypass the prompt
    if current_file:match("%.platformio") then
      vim.v.swapchoice = "o" -- Gracefully auto-select "Open Read-Only"
    end
  end,
})



vim.api.nvim_create_autocmd('VimLeavePre', {
  callback = function()
    --------------------------------------------------------------------------------
    local userClangd = OS.clangd_user_file
    local clangdFiles = {
      { key = 'userGlob', file = userClangd, content = function (ref) return require('nvimpio.boilerplate').readContent(ref) end,
        cache_id = string.sub(vim.fn.sha256(_G.metadata.packages_dir), 1, 16),
        block = function () return '' end, start_marker = '', end_marker = '', delete = false,
      },
      { key = 'userProj', file = userClangd, content = function (ref) return require('nvimpio.boilerplate').readContent(ref) end,
        cache_id = string.sub(vim.fn.sha256(OS.project_dir), 1, 16),
        block = function () return '' end, start_marker = '', end_marker = '', delete = true,
      },
    }
    ------------------------------------------------------------------------------
    local misc = require('nvimpio.utils.misc')
    for _, tbl in ipairs(clangdFiles) do
      if tbl and tbl.delete then
        require('nvimpio.boilerplate').readContent(tbl)
        misc.writeFile(tbl.file, tbl:content(), {})
      end
    end
  end,
})

-- INFO: set PlatformIO paths
cmd('PioPathSet', function ()
  require('nvimpio.core').configure_paths()
end, {desc = 'set PlatformIO paths'})

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
cmd('PioInstall', function()
  local ok_main, main = pcall(require, "nvimpio")
  if not ok_main then return end

  local current_pio_opts = (main.options and main.options.pio) or (main.defaults and main.defaults.pio) or {}
  local raw_runtime_dir = require('nvimpio.core').resolve_user_path(current_pio_opts.pio_runtime_dir)

  if not raw_runtime_dir or raw_runtime_dir == "" then
    raw_runtime_dir = OS.is_win and vim.fs.joinpath(vim.env.USERPROFILE, '.platformio')
      or vim.fs.joinpath(OS.home, '.platformio')
  end

  local base_runtime = raw_runtime_dir
  local bin_subfolder = OS.is_win and 'Scripts' or 'bin'
  local target_bin = vim.fs.joinpath(base_runtime, 'penv', bin_subfolder)

  local function install()
    require('nvimpio.pio.ui.pioInstall').pioInstall(base_runtime, function (status)
      if(status) then OS.notify("PIO installed successfully") end
    end)
  end
  local local_pio_executable = vim.fs.joinpath(target_bin, (OS.is_win and 'pio.exe' or 'pio'))
  if vim.fn.executable(local_pio_executable) == 1 then
    if vim.fn.confirm('PlatformIO already Installed, reinstall?', '&Yes\n&No', 1) == 1 then install() end
  else install() end
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

------------------------------------------------------

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
--INFO: fix paths in compile_commands.json
cmd('PioDbFixPaths', function() upkeep.compile_commandsFix() end, {})
cmd('PioDevList', function() local cmd_table = {'device', 'list'} require('nvimpio.pio.cli').piocli(cmd_table) end, {})
cmd('Piolib', function(opts) local args = vim.split(opts.args, ' ') require('nvimpio.pio.ui.piolib').piolib(args) end, { nargs = '+', })
cmd('Piocli', function(opts) local cmd_table = vim.split(opts.args, ' ') require('nvimpio.pio.cli').piocli(cmd_table) end, { nargs = '*', })
cmd('Piodebug', function() require('nvimpio.pio.cli').piodebug() end, {})

-- stylua: ignore end
