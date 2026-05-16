local pio = require('nvimpio.pioCheck')
local val = require('nvimpio.validator')
local menu = require('nvimpio.menu')
local main = require('nvimpio') -- Reference our parent init module safely

local M = {}

-- Private Helper: Merges user configurations with full plugin default values once triggered
local function initialize_full_options()
  -- If options were already processed, don't repeat the loop
  if main.options and main.options.menu_bindings then
    return
  end

  -- Complete hardware/menu default tracking list registry map
  local full_defaults = vim.tbl_deep_extend('force', main.defaults, {
    clangd = { support = false, install = false },
    debug = false,
    menu_bindings = {
      { node = 'item', desc = '[I]nitiate project', shortcut = 'i', command = 'Pioinit' },
      -- [Your remaining default items list array blocks go here...]
    },
  })

  local user_bindings = main.options and main.options.menu_bindings
  if main.options then
    main.options.menu_bindings = nil
  end

  -- Perform strict default array configuration blending pass
  main.options = vim.tbl_deep_extend('force', full_defaults, main.options or {})
  main.options.menu_bindings = user_bindings and menu.merge_menu_tree(full_defaults.menu_bindings, user_bindings, 'menu_bindings')
    or vim.deepcopy(full_defaults.menu_bindings)

  -- Validate configuration type constraints immediately
  local ok, err = val.validate_all_options(main.options)
  if not ok then
    error('PlatformIO Configuration Error:\n' .. err, 0)
  end
end

-- Verifies tracking paths and triggers the background installer loop if unpopulated
function M.ensure_toolchain_active(on_success_callback, retry_counter)
  local success = false
  retry_counter = retry_counter or 0
  initialize_full_options()

  local base_runtime = pio.clean(main.options.pio.pio_runtime_dir)
  local target_bin = base_runtime .. OS.folder_sep .. 'penv' .. OS.folder_sep .. OS.bin_dir
  local verified = false

  if vim.fn.isdirectory(target_bin) == 1 then
    main.config.pio_runtime_dir = target_bin
    verified = true
  elseif vim.fn.executable('pio') == 1 then
    main.config.pio_runtime_dir = vim.fs.dirname(vim.fn.exepath('pio'))
    verified = true
  end

  -- local function finalize()
  --   M.ensure_toolchain_active(on_success_callback, retry_counter + 1)
  --   if type(on_success_callback) == 'function' then
  --     pcall(on_success_callback, success)
  --   end
  -- end

  if verified then
    local current_path = vim.env.PATH or ''
    local escaped_bin = main.config.pio_runtime_dir:gsub('([^%w])', '%%%1')
    if not current_path:find(escaped_bin, 1, true) then
      vim.env.PATH = main.config.pio_runtime_dir .. OS.path_sep .. current_path
    end

    local final_storage = pio.clean(pio.check_ini_override() or main.options.pio.pio_storage_dir or vim.env.PLATFORMIO_CORE_DIR or OS.platformio_dir)
    if final_storage and vim.fn.isdirectory(final_storage) == 0 then
      vim.fn.mkdir(final_storage, 'p')
    end
    vim.env.PLATFORMIO_CORE_DIR = final_storage
    main.config.pio_storage_dir = final_storage

    if type(on_success_callback) == 'function' then
      on_success_callback(success)
    end
  else
    if retry_counter >= 1 then
      return vim.schedule(function()
        vim.notify("PlatformIO installation completed but the 'pio' executable remains missing. Check your system logs.", vim.log.levels.ERROR)
      end)
    end
    vim.schedule(function()
      if vim.fn.confirm('PlatformIO not found. Install?', '&Yes\n&No', 1) == 1 then
        local ok, installer = pcall(require, 'nvimpio.pio.ui.pioInstall')
        if ok then
          -- M.pioPathUpdate()
          installer.pioInstall(function(succ)
            success = succ
            M.ensure_toolchain_active(on_success_callback, retry_counter + 1)
            -- finalize()
          end)
        else
          OS.notify('Installer missing', 'error')
          if type(on_success_callback) == 'function' then
            on_success_callback(false)
          end
          -- finalize(false)
        end
      else
        -- finalize(false)
        if type(on_success_callback) == 'function' then
          on_success_callback(false)
        end
      end
      -- vim.ui.select({ 'Yes, install now', 'No, cancel setup' }, {
      --   prompt = 'PlatformIO Core missing. Would you like to install it automatically?',
      -- }, function(choice)
      --   if choice == 'Yes, install now' then
      --     install.install_core(base_runtime, function()
      --       M.ensure_toolchain_active(on_success_callback)
      --     end)
      --   else
      --     vim.notify('PlatformIO execution aborted: Missing required toolchains.', vim.log.levels.WARN)
      --   end
      -- end)
    end)
  end
end

-- Core runtime wrapper entry point invoked by :Pioinit command hook
function M.execute_init(args)
  M.ensure_toolchain_active(function()
    vim.notify('Executing project initialization sequence...', vim.log.levels.INFO)
    -- Your background process code execution goes here:
    -- vim.system({"pio", "project", "init", unpack(args.fargs)})
  end)
end

function M.configure_paths()
  initialize_full_options()
  vim.schedule(function()
    vim.ui.input({ prompt = 'Set pio_runtime_dir path: ', default = main.options.pio.pio_runtime_dir, completion = 'dir' }, function(r)
      if not r or r == '' then
        return
      end
      vim.ui.input({ prompt = 'Set pio_storage_dir path: ', default = main.options.pio.pio_storage_dir, completion = 'dir' }, function(s)
        if not s or s == '' then
          return
        end
        main.options.pio.pio_runtime_dir = r
        main.options.pio.pio_storage_dir = s
        M.ensure_toolchain_active()
      end)
    end)
  end)
end

return M
