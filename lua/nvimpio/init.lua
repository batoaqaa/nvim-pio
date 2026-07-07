-- -- =========================================================================
-- -- GLOBAL LEAK SNIFFER HOOK: Place this at Line 1 of lua/nvimpio/init.lua
-- -- =========================================================================
-- local original_require = _G.require
-- _G.require = function(modname)
--   -- Intercept right when the metadata background runner is pulled into memory
--   -- if modname == 'nvimpio.pio.metadata' or modname == 'nvimpio.pio.upkeep' then
--   -- if modname == 'nvimpio.pio.metadata' or modname == 'nvimpio.pio.metadata' then
--   if modname == 'nvimpio.statusline' or modname == 'nvimpio.statusline' then
--     print('\n[CRITICAL HOOK] DETECTED WHO REQUIRED: ' .. modname)
--     print(debug.traceback())
--     print('==================================================\n')
--   end
--   return original_require(modname)
-- end
-- -- =========================================================================

-- stylua: ignore start
require('nvimpio.osInfo')

---@class NvimPio
local M = {}

local isActivated = false -- Tracks if commands/features are loaded

-- Persistent internal storage for runtime verified properties
M.config = { pio_runtime_dir = nil, pio_storage_dir = nil, debug = true}
M.options = nil -- This will hold the complete configuration table safely in memory

-- Minimal primitive defaults to ensure the commands can register safely
M.defaults = require('nvimpio.defConfig')
-- local pioCheck = require('nvimpio.pioCheck')

-- Private Helper: Merges user configurations with full plugin default values once triggered
-- stylua: ignore
function M.initialize_full_options()
  local menu = require('nvimpio.menu')
  local val = require('nvimpio.validator')

  -- 1. Grab user choices from M.options (set by M.setup)
  local user_opts = M.options or {}
  local user_bindings = user_opts.menu_bindings

  -- 2. Create clean copies of scalar options by filtering out menu_bindings
  local clean_defaults = vim.tbl_extend('force', {}, M.defaults)
  clean_defaults.menu_bindings = nil

  local clean_user_opts = vim.tbl_extend('force', {}, user_opts)
  clean_user_opts.menu_bindings = nil

  -- 3. Merge scalar values safely (tbl_deep_extend won't break on missing arrays now)
  local final_options = vim.tbl_deep_extend('force', clean_defaults, clean_user_opts)

  -- 4. Safely handle the array tree merge without mutating anything out-of-scope
  if user_bindings and #user_bindings > 0 then
    final_options.menu_bindings = menu.merge_menu_tree(M.defaults.menu_bindings, user_bindings, 'menu_bindings')
  else
    final_options.menu_bindings = vim.deepcopy(M.defaults.menu_bindings)
  end

  -- 5. Validate the final generated configuration result
  local ok, err = val.validate_all_options(final_options)
  if not ok then
    error('PlatformIO Configuration Error:\n' .. err, 0)
  end

  -- 6. Save back to M.options only when validation completely passes
  M.options = final_options
end


------------------------------------------------------------------------
-- Activation: Turn on the plugin features
function M.activate()
  if isActivated then return end

  -- =========================================================================
  -- HARD LOCK SHIELD: Block automatic activation if paths are missing
  -- =========================================================================
  -- This acts as a complete gate, ensuring your background refresh timers 
  -- and tracking hooks never boot if the binary is absent or compiling!
  local pio_bin = M.config.pio_runtime_dir
  local pio_exe = OS.is_win and "pio.exe" or "pio"
  local check_path = pio_bin and vim.fs.joinpath(pio_bin, pio_exe) or ""

  if vim.fn.executable(check_path) ~= 1 and vim.fn.executable("pio") ~= 1 and vim.fn.executable("pio.exe") ~= 1 then
    return -- SAFELY HALTS ENTIRE BACKGROUND REFRESH SYSTEM
  end
  -- =========================================================================

  -- vim.schedule(function ()
  vim.notify('NVIM-PIO: Features Activated', vim.log.levels.INFO)

  -- Force PlatformIO to output full absolute paths for the toolchain binaries
  vim.fn.setenv("COMPILATIONDB_INCLUDE_TOOLCHAIN", "True")

  -- CRITICAL PATH REPAIR: Force Python environment isolation before options are parsed or commands register
  -- require('nvimpio.core').enforce_virtualenv_isolation()
  M.initialize_full_options()

  -- Load statusline ONLY after verification passes!
  require('nvimpio.statusline')

  local menu = require('nvimpio.menu')
  menu.buildUserMenu(M.options)
  require('nvimpio.pio.control').init(M.options.clangd)
  isActivated = true
  -- end)
end

-- INFO:
---stylua: ignore start
-------------------------------------------------------------------------------
function M.setup(user_opts)
  user_opts = user_opts or {}
  M.options = vim.deepcopy(user_opts)

  -- M.initialize_full_options()

  -- INFO: Pioini
  vim.api.nvim_create_user_command('Pioinit', function()
    require('nvimpio.core').ensure_toolchain_active(
      function(success)
        if success then
          require('nvimpio.pio.ui.pioInit').pioInit(function(done)
            if done then M.activate() end
          end)
        else
        end
      end,
      0
    )
    -- end, false)
  end, {
    force = true,
    desc = 'Start the PlatformIO guided setup wizard',
  })

  -- The background auto-activation
  if vim.fn.filereadable('platformio.ini') == 1 then
    local metadata = require('nvimpio.pio.metadata').load_project_config()

    if metadata and metadata.penv_dir then
      M.options.pio.pio_runtime_dir = metadata.penv_dir
      if metadata and metadata.core_dir then
        M.options.pio.pio_storage_dir = metadata.core_dir
      end
    end

    vim.schedule(function()
      require('nvimpio.core').ensure_toolchain_active(function(success)
        if success then
          _G.metadata.penv_dir = M.options.pio.pio_runtime_dir
          _G.metadata.core_dir = M.options.pio.pio_storage_dir
          M.activate()
        end
      end, 0)
      -- end, true)
    end)
  end
end

return M
