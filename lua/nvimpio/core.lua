local pio = require('nvimpio.pioCheck')
local val = require('nvimpio.validator')
local menu = require('nvimpio.menu')
local main = require('nvimpio') -- Reference our parent init module safely

local M = {}

local pio_term = nil

-- Private Helper: Merges user configurations with full plugin default values once triggered
-- stylua: ignore
local function initialize_full_options()
  if main.options and main.options.menu_bindings then return end

  -- 1. Create a clean deep copy of all factory defaults
  local primitive_defaults = vim.deepcopy(main.defaults)

  -- 2. Strip out the menu bindings array so tbl_deep_extend doesn't wipe it out!
  primitive_defaults.menu_bindings = nil

  -- 3. Isolate the user's custom layout overrides
  local user_bindings = main.options and main.options.menu_bindings
  if main.options then main.options.menu_bindings = nil end

  -- 4. Safely merge primitives on top of your public factory baseline template
  local full_defaults = vim.tbl_deep_extend('force', primitive_defaults, main.options or {})
  main.options = full_defaults

  -- 5. Route list array combining safely through our custom merge engine
  main.options.menu_bindings = user_bindings and menu.merge_menu_tree(main.defaults.menu_bindings, user_bindings, 'menu_bindings')
    or vim.deepcopy(main.defaults.menu_bindings)

  -- 6. Pass everything through the data type constraints validation layer
  local ok, err = val.validate_all_options(main.options)
  if not ok then
    error('PlatformIO Configuration Error:\n' .. err, 0)
  end
end

-- Verifies tracking paths and triggers the background installer loop if unpopulated
-- stylua: ignore
function M.ensure_toolchain_active(on_success_callback, retry_counter)
  retry_counter = retry_counter or 0

  -- 1. THE LIGHTWEIGHT BOOTSTRAP GATEWAY
  -- We extract only the critical target paths using a fast, non-breaking fallback sequence.
  -- This makes the path verifier 100% safe to run even if main.setup() hasn't executed yet!
  local current_pio_opts = (main.options and main.options.pio) or (main.defaults and main.defaults.pio) or {}
  local raw_runtime_dir = current_pio_opts.pio_runtime_dir
    or (OS.is_win and (os.getenv('USERPROFILE') .. '\\.platformio') or (vim.uv.os_homedir() .. '/.platformio'))
  local raw_storage_dir = current_pio_opts.pio_storage_dir or raw_runtime_dir

  local base_runtime = pio.clean(raw_runtime_dir)
  local target_bin = pio.clean(base_runtime .. OS.folder_sep .. 'penv' .. OS.folder_sep .. OS.bin_dir)
  local verified = false

  local local_pio_executable = target_bin .. OS.folder_sep .. (OS.is_win and 'pio.exe' or 'pio')
  if vim.fn.executable(local_pio_executable) == 1 then
    main.config.pio_runtime_dir = target_bin
    verified = true
  end

  if verified then
    local current_path = vim.env.PATH or ''
    local escaped_bin = main.config.pio_runtime_dir:gsub('([^%w])', '%%%1')
    if not current_path:find(escaped_bin, 1, true) then
      local stripped_path = current_path:gsub('^' .. OS.path_sep, ''):gsub(OS.path_sep .. '$', '')
      vim.env.PATH = main.config.pio_runtime_dir .. OS.path_sep .. stripped_path
    end

    local final_storage = pio.clean(pio.check_ini_override() or raw_storage_dir or vim.env.PLATFORMIO_CORE_DIR or base_runtime)
    if final_storage and vim.fn.isdirectory(final_storage) == 0 then
      vim.fn.mkdir(final_storage, 'p')
    end
    vim.env.PLATFORMIO_CORE_DIR = final_storage
    main.config.pio_storage_dir = final_storage

    if type(on_success_callback) == 'function' then
      initialize_full_options()
      on_success_callback(true)
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
          installer.pioInstall(base_runtime, function(_)
            M.ensure_toolchain_active(on_success_callback, retry_counter + 1)
          end)
        else
          OS.notify('Installer missing', 'error')
          if type(on_success_callback) == 'function' then
            on_success_callback(false)
          end
        end
      else
        OS.notify('PlatformIO execution aborted: Missing required toolchains.', 'warn')
        if type(on_success_callback) == 'function' then
          on_success_callback(false)
        end
      end
    end)
  end

  -- retry_counter = retry_counter or 0
  -- initialize_full_options()
  --
  -- local base_runtime = pio.clean(main.options.pio.pio_runtime_dir)
  -- local target_bin = pio.clean(base_runtime .. OS.folder_sep .. 'penv' .. OS.folder_sep .. OS.bin_dir)
  -- local verified = false
  --
  -- local local_pio_executable = target_bin .. OS.folder_sep .. (OS.is_win and 'pio.exe' or 'pio')
  -- if vim.fn.executable(local_pio_executable) == 1 then
  --   main.config.pio_runtime_dir = target_bin
  --   verified = true
  -- end
  --
  -- if verified then
  --   local current_path = vim.env.PATH or ''
  --   local escaped_bin = main.config.pio_runtime_dir:gsub('([^%w])', '%%%1')
  --   if not current_path:find(escaped_bin, 1, true) then
  --     local stripped_path = current_path:gsub("^" .. OS.path_sep, ""):gsub(OS.path_sep .. "$", "")
  --     vim.env.PATH = main.config.pio_runtime_dir .. OS.path_sep .. stripped_path
  --   end
  --
  --   local final_storage = pio.clean(pio.check_ini_override() or main.options.pio.pio_storage_dir or vim.env.PLATFORMIO_CORE_DIR or base_runtime)
  --   if final_storage and vim.fn.isdirectory(final_storage) == 0 then vim.fn.mkdir(final_storage, 'p') end
  --   vim.env.PLATFORMIO_CORE_DIR = final_storage
  --   main.config.pio_storage_dir = final_storage
  --
  --   if type(on_success_callback) == 'function' then on_success_callback(true) end
  -- else
  --   if retry_counter >= 1 then
  --     return vim.schedule(function()
  --       vim.notify("PlatformIO installation completed but the 'pio' executable remains missing. Check your system logs.", vim.log.levels.ERROR)
  --     end)
  --   end
  --   vim.schedule(function()
  --     if vim.fn.confirm('PlatformIO not found. Install?', '&Yes\n&No', 1) == 1 then
  --       local ok, installer = pcall(require, 'nvimpio.pio.ui.pioInstall')
  --       if ok then
  --         -- M.pioPathUpdate()
  --         installer.pioInstall(base_runtime, function(_)
  --           M.ensure_toolchain_active(on_success_callback, retry_counter + 1)
  --         end)
  --       else
  --         OS.notify('Installer missing', 'error')
  --         if type(on_success_callback) == 'function' then on_success_callback(false) end
  --       end
  --     else
  --       OS.notify('PlatformIO execution aborted: Missing required toolchains.', 'warn')
  --       if type(on_success_callback) == 'function' then on_success_callback(false) end
  --     end
  --   end)
  -- end
end

function M.execute_cmd_clean(target_command)
  initialize_full_options()

  local status, ToggleTerm = pcall(require, 'toggleterm.terminal')
  if not status then
    return vim.notify('ToggleTerm is required but missing.', 4)
  end

  local pio_bin = main.config.pio_bin_dir or (pio.clean(main.options.pio.pio_runtime_dir) .. OS.folder_sep .. 'penv' .. OS.folder_sep .. OS.bin_dir)

  if pio_term then
    pio_term:shutdown()
  end

  pio_term = ToggleTerm.Terminal:new({
    id = 99,
    cmd = target_command,
    direction = 'float',
    float_opts = { border = 'rounded' },
    close_on_exit = false,
    env = {
      PATH = pio_bin .. OS.folder_sep .. (vim.env.PATH or ''),
    },
  })
  pio_term:open()
end

function M.execute_init(args)
  M.ensure_toolchain_active(function()
    local full_cmd = 'pio project init'
    if args and args.fargs and #args.fargs > 0 then
      full_cmd = full_cmd .. ' ' .. table.concat(args.fargs, ' ')
    end
    M.execute_cmd_clean(full_cmd)
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
        M.ensure_toolchain_active(function()
          vim.notify('PlatformIO Wizard workspace paths updated successfully!', 2)
        end)
      end)
    end)
  end)
end

return M
