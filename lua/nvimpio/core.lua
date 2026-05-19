local M = {}

local pio_term = nil

-- Verifies tracking paths and triggers the background installer loop if unpopulated
--------------------------------------------------------------------------------
-- UTILITY LAYERS: Safe Path Normalization & Data Strippers
--------------------------------------------------------------------------------

-- Resolves user strings (~/), strips spacing errors, and standardizes sytem paths
-- stylua: ignore
function M.resolve_user_path(raw_path)
  if not raw_path or raw_path == "" then return nil end
  local trimmed = vim.trim(raw_path)
  local expanded = vim.fn.expand(trimmed)
  -- If expansion fails or tracks an invalid pattern, protect string integrity
  if expanded == "" or expanded:match("^~") then
    expanded = trimmed
  end
  return vim.fs.normalize(expanded)
end

-- Checks toolchain existence and resolves paths without parsing heavy structures
-- stylua: ignore
function M.ensure_toolchain_active(on_success_callback, retry_counter)
  local main = require("nvimpio")
  retry_counter = retry_counter or 0

  -- JIT Path Gateway: Safely parses configuration choices at invocation runtime
  local current_pio_opts = (main.options and main.options.pio) or (main.defaults and main.defaults.pio) or {}
  local raw_runtime_dir = M.resolve_user_path(current_pio_opts.pio_runtime_dir)

  -- Execute fallback checks only if options parameters are missing or completely blank strings
  if not raw_runtime_dir or raw_runtime_dir == "" then
    raw_runtime_dir = OS.is_win and vim.fs.normalize(vim.env.USERPROFILE .. '/.platformio')
      or vim.fs.normalize(vim.uv.os_homedir() .. '/.platformio')
  end

  local base_runtime = raw_runtime_dir
  local bin_subfolder = OS.is_win and 'Scripts' or 'bin'
  local target_bin = vim.fs.normalize(base_runtime .. '/penv/' .. bin_subfolder)
  local verified = false

  local local_pio_executable = vim.fs.normalize(target_bin .. '/' .. (OS.is_win and 'pio.exe' or 'pio'))
  if vim.fn.executable(local_pio_executable) == 1 then
    main.config.pio_runtime_dir = target_bin
    verified = true
  end

  if verified then
    local current_path = vim.env.PATH or ''
    -- Clean cross-platform separator and token validation
    local target_clean = vim.fs.normalize(main.config.pio_runtime_dir)
    if OS.is_win then target_clean = target_clean:lower() end

    local active_paths = vim.split(current_path, OS.path_sep, { trimempty = true })
    local found_in_path = false

    for _, segment in ipairs(active_paths) do
      local seg_clean = vim.fs.normalize(segment)
      if OS.is_win then seg_clean = seg_clean:lower() end
      if seg_clean == target_clean then
        found_in_path = true
        break
      end
    end

    if not found_in_path then
      vim.env.PATH = main.config.pio_runtime_dir .. OS.path_sep .. current_path
    end

    local raw_storage_dir = M.resolve_user_path(current_pio_opts.pio_storage_dir) or vim.env.PLATFORMIO_CORE_DIR or base_runtime
    if raw_storage_dir and vim.fn.isdirectory(raw_storage_dir) == 0 then
      vim.fn.mkdir(raw_storage_dir, 'p')
    end

    -- vim.env.PLATFORMIO_CORE_DIR = raw_storage_dir
    main.config.pio_storage_dir = raw_storage_dir

    if type(on_success_callback) == 'function' then
      on_success_callback(true)
      if retry_counter == 0 then OS.notify('PIO already installed and verified') end
    end
  else
    if retry_counter >= 1 then
      return vim.schedule(function()
        OS.notify("PlatformIO path resolution failed. Target missing.", 'error')
      end)
    end
    vim.schedule(function()
      if vim.fn.confirm('PlatformIO not found. Install toolchain?', '&Yes\n&No', 1) == 1 then
        local ok, installer = pcall(require, 'nvimpio.pio.ui.pioInstall')
        if ok then
          installer.pioInstall(base_runtime, function(_)
            M.ensure_toolchain_active(on_success_callback, retry_counter + 1)
          end)
        else
          OS.notify('Installer module missing', 'error')
          if type(on_success_callback) == 'function' then on_success_callback(false) end
        end
      else
        OS.notify('Execution aborted: Toolchain missing.', 'warn')
        if type(on_success_callback) == 'function' then on_success_callback(false) end
      end
    end)
  end
end

function M.execute_cmd_clean(target_command)
  local main = require('nvimpio')
  local pio = require('nvimpio.pioCheck')
  main.initialize_full_options()

  local status, ToggleTerm = pcall(require, 'toggleterm.terminal')
  if not status then
    return OS.notify('ToggleTerm is required but missing.', 'error')
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
  local main = require('nvimpio')
  main.initialize_full_options()
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
          OS.notify('PlatformIO Wizard workspace paths updated successfully!')
        end)
      end)
    end)
  end)
end

return M
