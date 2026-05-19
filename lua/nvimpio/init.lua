-- stylua: ignore start
require('nvimpio.osInfo')
require('nvimpio.statusline')

-- local pio = require('nvimpio.pioCheck')
-- local val = require('nvimpio.validator')

local M = {}

M.isActivated = false -- Tracks if commands/features are loaded

-- Persistent internal storage for runtime verified properties
M.config = { pio_runtime_dir = nil, pio_storage_dir = nil, }
M.options = nil -- This will hold the complete configuration table safely in memory

-- Minimal primitive defaults to ensure the commands can register safely
M.defaults = require('nvimpio.defConfig')
-- local pioCheck = require('nvimpio.pioCheck')

-- Private Helper: Merges user configurations with full plugin default values once triggered
-- stylua: ignore
function M.initialize_full_options()
  local menu = require('nvimpio.menu')
  local val = require('nvimpio.validator')

  if M.options and M.options.menu_bindings then return end

  -- 1. Create a clean deep copy of all factory defaults
  local primitive_defaults = vim.deepcopy(M.defaults)

  -- 2. Strip out the menu bindings array so tbl_deep_extend doesn't wipe it out!
  primitive_defaults.menu_bindings = nil

  -- 3. Isolate the user's custom layout overrides
  local user_bindings = M.options and M.options.menu_bindings
  if M.options then M.options.menu_bindings = nil end

  -- 4. Safely merge primitives on top of your public factory baseline template
  local full_defaults = vim.tbl_deep_extend('force', primitive_defaults, M.options or {})
  M.options = full_defaults

  -- 5. Route list array combining safely through our custom merge engine
  M.options.menu_bindings = user_bindings and menu.merge_menu_tree(M.defaults.menu_bindings, user_bindings, 'menu_bindings')
    or vim.deepcopy(M.defaults.menu_bindings)

  -- 6. Pass everything through the data type constraints validation layer
  local ok, err = val.validate_all_options(M.options)
  if not ok then
    error('PlatformIO Configuration Error:\n' .. err, 0)
  end
end

------------------------------------------------------------------------
-- Activation: Turn on the plugin features
function M.activate()
  if M.isActivated then return end

  M.isActivated = true
  -- vim.schedule(function ()
    vim.notify('NVIM-PIO: Features Activated', vim.log.levels.INFO)
    M.initialize_full_options()
    local menu = require('nvimpio.menu')
    menu.buildUserMenu(M.options)
    require('nvimpio.pio.control').init(M.options.clangd)
  -- end)
end

-- INFO:
---stylua: ignore start
-------------------------------------------------------------------------------
function M.setup(user_opts)
  user_opts = user_opts or {}
  M.options = vim.deepcopy(user_opts)

  -- INFO: Pioini
  vim.api.nvim_create_user_command('Pioinit', function()
    vim.g.platformioRootDir = vim.uv.cwd()
    -- require("nvimpio.core").execute_init(args)
    require('nvimpio.core').ensure_toolchain_active(
      -- pioCheck.pioStatus(
      function(success)
        if success then
          vim.g.platformioRootDir = vim.uv.cwd()
          -- pioCheck.pioPathUpdate()
          require('nvimpio.pio.ui.pioInit').pioInit(function(done)
            if done then
              -- vim.clangd.getUnknownArgs()
              -- if M.config.clangd.install then require('nvimpio.clangd.config') end
              M.activate()
            end
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
    vim.g.platformioRootDir = vim.uv.cwd()
    vim.schedule(function()
      -- pioCheck.pioStatus(
      require('nvimpio.core').ensure_toolchain_active(function(success)
        if success then
          M.activate()
        end
      end, 0)
      -- end, true)
    end)
  end
end

return M
