--stylua: ignore start
local M = {}

local function clear_subdirectories(target_dir)
  -- delete .pio folder
  -- if vim.uv.fs_stat(OS.pio_config_dir) then vim.fs.rm(OS.pio_config_dir, { recursive = true }) end

  for name, type in vim.fs.dir(target_dir) do
    if type == "directory" then
      local full_path = vim.fs.normalize(vim.fs.joinpath(target_dir, name))
      vim.fn.delete(full_path, "rf") -- Directly force delete subfolders safely
    end
  end
end

local setPenvBinPath = function (target)
  local penv_bin = vim.fs.normalize(vim.fs.joinpath(target, (OS.is_win and 'penv/Scripts' or 'penv/bin')))
  local current_path = vim.env.PATH or ''

  local check_target = OS.is_win and penv_bin:lower() or penv_bin
  local active_paths = vim.split(current_path, OS.path_sep, { trimempty = true })
  local found_in_path = false

  for _, segment in ipairs(active_paths) do
    local seg_clean = vim.fs.normalize(segment)
    if OS.is_win then seg_clean = seg_clean:lower() end
    if seg_clean == check_target then
      found_in_path = true
      break
    end
  end
  if not found_in_path then
    vim.env.PATH = penv_bin .. OS.path_sep .. current_path
    OS.notify(string.format("penv-bin: %s  added to PATH", penv_bin))
  end
end

-- ---Defensively isolates and locks the correct active python path boundaries into Neovim's environment
-- function M.enforce_virtualenv_isolation()
--   -- 1. Read the environment path strings safely from active system variables
--   local active_venv = vim.env.VIRTUAL_ENV
--   if not active_venv or active_venv == '' then return end
--
--   -- 2. Enforce clean forward slashes for the venv target path
--   local pio_path = vim.fs.normalize(vim.fs.dirname(active_venv))
--   setPenvBinPath(pio_path)
-- end

function M.clean(raw_path)
  if not raw_path or raw_path == '' then
    return nil
  end
  local normalized = vim.fs.normalize(vim.fn.expand(raw_path))
  -- return OS.is_win and normalized:gsub('/', '\\') or normalized
  return normalized
end

-- Resolves user strings (~/), strips spacing errors, and standardizes sytem paths
-- stylua: ignore
function M.resolve_user_path(raw_path)
  if not raw_path or raw_path == "" then return nil end

  -- If path is already absolute (e.g. starts with C: or /), return it immediately
  if raw_path:match("^%a:") or raw_path:match("^/") then
    return vim.fs.normalize(raw_path)
  end

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
  retry_counter = retry_counter or 0

  -- 1. DECOUPLED LOADING: Read defaults statically first to prevent circular module initialization loops
  local ok_main, main = pcall(require, "nvimpio")
  if not ok_main then
    if type(on_success_callback) == 'function' then on_success_callback(false) end
    return
  end

  -- JIT Path Gateway: Safely parses configuration choices at invocation runtime
  local current_pio_opts = (main.options and main.options.pio) or (main.defaults and main.defaults.pio) or {}
  local resolved_runtime_dir = M.resolve_user_path(current_pio_opts.pio_runtime_dir)

  -- Execute fallback checks only if options parameters are missing or completely blank strings
  if not resolved_runtime_dir or resolved_runtime_dir == "" then
    resolved_runtime_dir = vim.fs.normalize(vim.fs.joinpath(OS.home, '.platformio'))
  end

  local target_penv = vim.fs.normalize(vim.fs.joinpath(resolved_runtime_dir, 'penv'))
  local verified = false

  local local_pio_executable = vim.fs.normalize(vim.fs.joinpath(resolved_runtime_dir, (OS.is_win and 'penv/Scripts/pio.exe' or 'penv/bin/pio')))
  if vim.fn.executable(local_pio_executable) == 1 then verified = true end

  local resolved_storage_dir = M.resolve_user_path(current_pio_opts.pio_storage_dir) or vim.fs.normalize(vim.env.PLATFORMIO_CORE_DIR) or resolved_runtime_dir
  if verified then
    main.config.pio_runtime_dir = resolved_runtime_dir
    main.config.pio_storage_dir = resolved_storage_dir

    if resolved_storage_dir and vim.fn.isdirectory(resolved_storage_dir) == 0 then vim.fn.mkdir(resolved_storage_dir, "p") end
    setPenvBinPath(resolved_runtime_dir)

    vim.env.PLATFORMIO_CORE_DIR = resolved_storage_dir
    vim.env.PLATFORMIO_PENV_DIR = target_penv
    vim.env.VIRTUAL_ENV = target_penv

    -- CRITICAL LOGIC ROUTING: Only fire execution callback downstream if toolchain is active!
    if type(on_success_callback) == 'function' then
      OS.notify('PlatformIO verified.')
      on_success_callback(true)
    end

  else -- Toolchain missing and installation failed on retry pass boundary
    if retry_counter >= 1 then
      return vim.schedule(function()
        OS.notify("PlatformIO path resolution failed. Target missing.", 'error')
        if type(on_success_callback) == 'function' then on_success_callback(false) end
      end)
    end

    -- BLOCKING GATEWAY: Wrap prompt setup and FORCE return to stop the caller thread from continuing!
    vim.schedule(function()
      if vim.fn.confirm('PlatformIO not found. Install toolchain?', '&Yes\n&No', 1) == 1 then
        vim.ui.input({
          prompt = 'Set pio_runtime_dir path: ', default = (main.options.pio and main.options.pio.pio_runtime_dir) or '', completion = 'dir'
        }, function(runtime_dir)
          if runtime_dir == nil or runtime_dir == "" then
            OS.notify('Execution aborted. Could not resolve path', 'warn')
            if type(on_success_callback) == 'function' then on_success_callback(false) end
            return
          end

          resolved_runtime_dir = M.resolve_user_path(runtime_dir)
          if not resolved_runtime_dir or resolved_runtime_dir == "" then
            if type(on_success_callback) == 'function' then on_success_callback(false) end
            return vim.notify("Could not resolve path", vim.log.levels.ERROR)
          end

          target_penv = vim.fs.normalize(vim.fs.joinpath(resolved_runtime_dir, 'penv'))

          local prepareFolders = function (storage)
            main.options.pio = main.options.pio or {}
            main.options.pio.pio_runtime_dir = resolved_runtime_dir
            main.options.pio.pio_storage_dir = storage
            vim.env.PLATFORMIO_CORE_DIR = storage
            vim.env.PLATFORMIO_PENV_DIR = target_penv
            vim.env.VIRTUAL_ENV = target_penv
            clear_subdirectories(OS.nvimpio_config_dir)
            setPenvBinPath(resolved_runtime_dir)
            require('nvimpio.device.terminal').reopen()
          end

          local_pio_executable = vim.fs.normalize(vim.fs.joinpath(resolved_runtime_dir, (OS.is_win and 'penv/Scripts/pio.exe' or 'penv/bin/pio')))
          local stat = vim.uv.fs_stat(resolved_runtime_dir)
          -- Check if the directory exists using libuv and pio executable
          local exists = stat and (stat.type == "directory") and (vim.fn.executable(local_pio_executable) == 1)
          if exists then
            if vim.fn.confirm('Directory already exists!, Use it?', '&Yes\n&No', 1) == 1 then
              vim.ui.input({ prompt = 'Set pio_storage_dir path: ', default = (main.options.pio and main.options.pio.pio_storage_dir) or '', completion = 'dir' }, function(storage_dir)
                if not storage_dir or storage_dir == '' then
                  OS.notify('Execution aborted. Could not resolve path', 'warn')
                  if type(on_success_callback) == 'function' then on_success_callback(false) end
                  return
                end
                resolved_storage_dir = M.resolve_user_path(storage_dir) or ''
                if not resolved_storage_dir or resolved_runtime_dir == "" then
                  if type(on_success_callback) == 'function' then on_success_callback(false) end
                  return vim.notify("Could not resolve path", vim.log.levels.ERROR)
                end
                -------------------------------------------------------------
                prepareFolders(resolved_storage_dir)
                require('nvimpio.pio.ui.pioRepair').pioRepair()
                M.ensure_toolchain_active(on_success_callback, retry_counter + 1)
              end)
            end --)
          else  -- Not exists
            vim.ui.input({ prompt = 'Set pio_storage_dir path: ', default = (main.options.pio and main.options.pio.pio_storage_dir) or '', completion = 'dir' }, function(storage_dir)
              if not storage_dir or storage_dir == '' then
                OS.notify('Execution aborted. Could not resolve path', 'warn')
                if type(on_success_callback) == 'function' then on_success_callback(false) end
                return
              end
              resolved_storage_dir = M.resolve_user_path(storage_dir) or ''
              if not resolved_storage_dir or resolved_runtime_dir == "" then
                if type(on_success_callback) == 'function' then on_success_callback(false) end
                return vim.notify("Could not resolve path", vim.log.levels.ERROR)
              end
              local ok, installer = pcall(require, 'nvimpio.pio.ui.pioInstall')
              if ok then
                prepareFolders(resolved_storage_dir)
                if vim.uv.fs_stat(target_penv) then vim.fs.rm(target_penv, { recursive = true }) end
                installer.pioInstall(main.options.pio.pio_runtime_dir, function(_)
                  -- Once terminal install finishes, run recursion step 1 to register paths cleanly
                  M.ensure_toolchain_active(on_success_callback, retry_counter + 1)
                end)
              else
                OS.notify('Installer module missing', 'error')
                if type(on_success_callback) == 'function' then on_success_callback(false) end
              end
            end)
          end
        end)
      else -- No, Escape
        OS.notify('Execution aborted: Toolchain missing.', 'warn')
        if type(on_success_callback) == 'function' then on_success_callback(false) end
      end
    end)
  end
end

return M
