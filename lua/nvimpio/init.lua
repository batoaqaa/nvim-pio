require('nvimpio.osInfo')

local pio = require('nvimpio.pioCheck')
local val = require('nvimpio.validator')
local menu = require('nvimpio.menu')

local M = {}

M.isActivated = false -- Tracks if commands/features are loaded

-- Persistent internal storage for runtime verified properties
M.config = {
  pio_runtime_dir = nil, -- Absolute path to python/pio binaries directory
  pio_storage_dir = nil, -- Absolute path to core tracking directory
}

M.options = nil -- This will hold the complete configuration table safely in memory
-- PLUGIN CONFIGURATION DEFAULTS
M.defaults = require('nvimpio.defConfig')

local pioCheck = require('nvimpio.pioCheck')

-- stylua: ignore
function M.configure_paths()
  vim.schedule(function()
    vim.ui.input({ prompt = 'Set pio_runtime_dir path: ', default = M.options.pio.pio_runtime_dir, completion = 'dir' }, function(runtime)
      if not runtime or runtime == '' then return end
      vim.ui.input({ prompt = 'Set pio_storage_dir path: ', default = M.options.pio.pio_storage_dir, completion = 'dir' }, function(storage)
        if not storage or storage == '' then return end

        M.options.pio.pio_runtime_dir = runtime
        M.options.pio.pio_storage_dir = storage

        M.apply_toolchain()
      end)
    end)
  end)
end

function M.apply_toolchain()
  local base_runtime = pio.clean(M.options.pio.pio_runtime_dir)
  local target_bin = base_runtime .. OS.folder_sep .. 'penv' .. OS.folder_sep .. OS.bin_dir
  local verified = false

  if vim.fn.isdirectory(target_bin) == 1 then
    M.config.pio_runtime_dir = target_bin
    verified = true
  elseif vim.fn.executable('pio') == 1 then
    M.config.pio_runtime_dir = vim.fs.dirname(vim.fn.exepath('pio'))
    verified = true
  end

  if not verified then
    vim.schedule(function()
      vim.notify('PlatformIO Core executable not found! Run :PioSetupPaths to fix this configuration path setup.', vim.log.levels.WARN)
    end)
    return false
  end

  local escaped_bin = M.config.pio_runtime_dir:gsub('([^%w])', '%%%1')
  if not (vim.env.PATH or ''):find(escaped_bin, 1, true) then
    vim.env.PATH = M.config.pio_runtime_dir .. pio.path_sep .. (vim.env.PATH or '')
  end

  local final_storage = pio.clean(pio.check_ini_override() or M.options.pio.pio_storage_dir or base_runtime)
  if final_storage and vim.fn.isdirectory(final_storage) == 0 then
    vim.fn.mkdir(final_storage, 'p')
  end

  print(final_storage)
  vim.env.PLATFORMIO_CORE_DIR = final_storage
  M.config.pio_storage_dir = final_storage

  vim.schedule(function()
    vim.notify('PlatformIO toolchain linked successfully!', vim.log.levels.INFO)
  end)
  return true
end

-- INFO:
---stylua: ignore start
-------------------------------------------------------------------------------
function M.setup(user_opts)
  user_opts = user_opts or {}
  local user_bindings = user_opts.menu_bindings
  user_opts.menu_bindings = nil

  M.options = vim.tbl_deep_extend('force', M.defaults, user_opts)
  M.options.menu_bindings = user_bindings and menu.merge_menu_tree(M.defaults.menu_bindings, user_bindings, 'menu_bindings')
    or vim.deepcopy(M.defaults.menu_bindings)

  local ok, err = val.validate_all_options(M.options)
  if not ok then
    return vim.schedule(function()
      vim.notify('PIO Configuration Error:\n' .. err, 4)
    end)
  end
  for i, root in ipairs(M.options.menu_bindings) do
    if type(root) == 'table' then
      val.validate_node(root, string.format('menu_bindings[%d]', i))
    end
  end

  vim.api.nvim_create_user_command('PioSetupPaths', function()
    M.configure_paths()
  end, {})

  M.apply_toolchain()

  ------------------------------------------------------------------------
  -- Activation: Turn on the plugin features
  local function activate()
    if M.isActivated then
      return
    end

    M.isActivated = true
    vim.notify('NVIM-PIO: Features Activated', vim.log.levels.INFO)
    vim.g.platformioRootDir = vim.uv.cwd()

    -- pioCheck.pioPathUpdate()
    -- local sep = vim.fn.has('win32') == 1 and ';' or ':'
    -- if M.config.pio.auto_update_path then
    --   local pio_bin = pioCheck.get_bin_dir()
    --   if vim.fn.isdirectory(pio_bin) == 1 then vim.env.PATH = pio_bin .. sep .. vim.env.PATH end
    -- end

    -- interface.validate(user_config)
    -- M.config = vim.tbl_deep_extend('force', defConfig, user_config or {})
    menu.buildUsserMenu(M.config)

    require('nvimpio.pio.control').init(M.config.clangd)
  end

  -- INFO: Pioini
  vim.api.nvim_create_user_command('Pioinit', function()
    pioCheck.pioStatus(function(success)
      if success then
        if M.isActivated then
          require('nvimpio.pio.ui.pioInit').pioInit()
        else
          vim.g.platformioRootDir = vim.uv.cwd()
          -- pioCheck.pioPathUpdate()
          require('nvimpio.pio.ui.pioInit').pioInit(function(done)
            if done then
              -- vim.clangd.getUnknownArgs()
              -- if M.config.clangd.install then require('nvimpio.clangd.config') end
              activate()
            end
          end)
        end
      else
      end
    end, false)
  end, {
    force = true,
    desc = 'Start the PlatformIO guided setup wizard',
  })

  -- The background auto-activation
  if vim.fn.filereadable('platformio.ini') == 1 then
    vim.schedule(function()
      pioCheck.pioStatus(function(success)
        if success then
          activate()
        end
      end, true)
    end)
  end
end

return M
