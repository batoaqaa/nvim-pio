--stylua: ignore start
local M = {}

local function clear_subdirectories(target_dir)
  -- 1. Scan the target directory for entries
  local handle = vim.uv.fs_scandir(target_dir)
  if not handle then
    return vim.notify("Could not read directory: " .. target_dir, vim.log.levels.ERROR)
  end

  -- 2. Loop through every item inside the folder
  while true do
    local name, type = vim.uv.fs_scandir_next(handle)
    if not name then break end -- No more files/folders left to check

    -- 3. Isolate folders and delete them recursively
    if type == "directory" then
      local full_path = target_dir .. "/" .. name

      -- Native recursive folder deletion
      local success, err = vim.uv.fs_rmdir(full_path)

      -- If the directory isn't empty, fallback to a recursive removal
      if not success and err and err:match("ENOTEMPTY") then
        -- This deletes the folder and all its contents cleanly
        vim.fn.delete(full_path, "rf")
      end
    end
  end
end

---Defensively isolates and locks the correct active python path boundaries into Neovim's environment
function M.enforce_virtualenv_isolation()
  -- 1. Read the environment path strings safely from active system variables
  local active_venv = vim.env.VIRTUAL_ENV
  if not active_venv or active_venv == '' then return end

  -- 2. Fully self-contained platform detection (removes reliance on external global tables)
  local bin_folder = OS.is_win and 'Scripts' or 'bin'

  -- Force forward slashes inside Neovim for clean parsing, or stick to native system layouts
  -- 3. Enforce clean forward slashes for the venv target path
  local venv_bin_path = vim.fs.normalize(active_venv .. '/' .. bin_folder)
  local current_path_registry = vim.env.PATH or ''

  -- 4. Normalize the entire PATH string to forward slashes just for the comparison check.
  -- This ensures matching succeeds even if Windows mixed the slash styles up!
  local normalized_registry = vim.fs.normalize(current_path_registry)

  -- 5. Perform the raw text search on the matched slash types
  local is_already_in_path = string.find(normalized_registry, venv_bin_path, 1, true) ~= nil

  if not is_already_in_path then
    -- Prepend using your system's original string format to maintain stability
    vim.env.PATH = venv_bin_path .. OS.path_sep .. current_path_registry
  end
end

function M.clean(raw_path)
  if not raw_path or raw_path == '' then
    return nil
  end
  local normalized = vim.fs.normalize(vim.fn.expand(raw_path))
  -- return OS.is_win and normalized:gsub('/', '\\') or normalized
  return normalized
end
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

function M.configure_paths()
  local main = require('nvimpio')
  vim.ui.input({ prompt = 'Set pio_runtime_dir path: ', default = main.options.pio.pio_runtime_dir, completion = 'dir' }, function(r)
    if not r or r == '' then return end
    vim.ui.input({ prompt = 'Set pio_storage_dir path: ', default = main.options.pio.pio_storage_dir, completion = 'dir' }, function(s)
      if not s or s == '' then return end
      local resolved_runtime_dir  = M.resolve_user_path(r)
      main.options.pio.pio_runtime_dir = resolved_runtime_dir
      main.options.pio.pio_storage_dir = M.resolve_user_path(s)
    end)
  end)
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
  local raw_runtime_dir = M.resolve_user_path(current_pio_opts.pio_runtime_dir)

  -- Execute fallback checks only if options parameters are missing or completely blank strings
  if not raw_runtime_dir or raw_runtime_dir == "" then
    raw_runtime_dir = OS.is_win and vim.fs.joinpath(vim.env.USERPROFILE, '.platformio')
      or vim.fs.joinpath(OS.home, '.platformio')
  end

  local base_runtime = raw_runtime_dir
  local bin_subfolder = OS.is_win and 'Scripts' or 'bin'
  local target_bin = vim.fs.joinpath(base_runtime, 'penv', bin_subfolder)
  local verified = false

  local local_pio_executable = vim.fs.joinpath(target_bin, (OS.is_win and 'pio.exe' or 'pio'))
  if vim.fn.executable(local_pio_executable) == 1 then
    -- main.config.pio_runtime_dir = target_bin
    main.config.pio_runtime_dir = raw_runtime_dir
    verified = true
  end

  if verified then
    print('verified')
    local current_path = vim.env.PATH or ''
    -- local target_clean = vim.fs.normalize(main.config.pio_runtime_dir)
    local target_clean = vim.fs.normalize(target_bin)
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
      vim.env.PATH = target_clean .. OS.path_sep .. current_path
      OS.notify("penv bin path added to PATH")
    end

    local raw_storage_dir = M.resolve_user_path(current_pio_opts.pio_storage_dir) or vim.env.PLATFORMIO_CORE_DIR or base_runtime
    if raw_storage_dir and vim.fn.isdirectory(raw_storage_dir) == 0 then
      vim.uv.fs_mkdir(raw_storage_dir, 493)
    end

    main.config.pio_storage_dir = raw_storage_dir

    -- CRITICAL LOGIC ROUTING: Only fire execution callback downstream if toolchain is active!
    if type(on_success_callback) == 'function' then
      if retry_counter == 0 then OS.notify('PlatformIO verified and active.') end
      on_success_callback(true)
    end
  else
    -- Toolchain missing and installation failed on retry pass boundary
    if retry_counter >= 1 then
      return vim.schedule(function()
        OS.notify("PlatformIO path resolution failed. Target missing.", 'error')
        if type(on_success_callback) == 'function' then on_success_callback(false) end
      end)
    end

    -- BLOCKING GATEWAY: Wrap prompt setup and FORCE return to stop the caller thread from continuing!


    vim.schedule(function()
    print('not verified')
      if vim.fn.confirm('PlatformIO not found. Install toolchain?', '&Yes\n&No', 1) == 1 then
        vim.ui.input({
          prompt = 'Set pio_runtime_dir path: ', default = main.options.pio.pio_runtime_dir, completion = 'dir'
        }, function(runtim_dir)
          if runtim_dir == nil then
            OS.notify('Execution aborted.', 'warn')
            if type(on_success_callback) == 'function' then on_success_callback(false) end
            return
          end -- Escaped
          if runtim_dir == "" then
            OS.notify('ath cannot be empty.', 'warn')
            if type(on_success_callback) == 'function' then on_success_callback(false) end
            return
          end
          local resolved_runtime_dir = M.resolve_user_path(runtim_dir)

          if not resolved_runtime_dir or resolved_runtime_dir == "" then
            if type(on_success_callback) == 'function' then on_success_callback(false) end
            return vim.notify("Could not resolve path", vim.log.levels.ERROR)
          end
          -- Check if the directory exists using libuv


          -- local bin_subfolder = OS.is_win and 'Scripts' or 'bin'
          target_bin = vim.fs.joinpath(resolved_runtime_dir, 'penv', bin_subfolder)
          print(target_bin)
          local_pio_executable = vim.fs.joinpath(target_bin, (OS.is_win and 'pio.exe' or 'pio'))

          local stat = vim.uv.fs_stat(resolved_runtime_dir)
          local exists = stat and (stat.type == "directory") and (vim.fn.executable(local_pio_executable) == 1)

          if exists then
            -- Directory exists! Prompt user for a decision
            vim.ui.select({ 'Reinstall', 'Rename' }, {
              prompt = 'Directory already exists! Choose an action:',
            }, function(choice)
              if choice == nil then -- Escaped the selection menu, take no action 
                OS.notify('Execution aborted.', 'warn')
                if type(on_success_callback) == 'function' then on_success_callback(false) end
                return
              end
              vim.ui.input({ prompt = 'Set pio_storage_dir path: ', default = main.options.pio.pio_storage_dir, completion = 'dir' }, function(storage_dir)
                if not storage_dir or storage_dir == '' then
                  OS.notify('Execution aborted.', 'warn')
                  if type(on_success_callback) == 'function' then on_success_callback(false) end
                  return
                end
                main.options.pio.pio_runtime_dir = resolved_runtime_dir
                main.options.pio.pio_storage_dir = M.resolve_user_path(storage_dir)
                -------------------------------------------------------------
                if choice == 'Reinstall' then
                  local ok, installer = pcall(require, 'nvimpio.pio.ui.pioInstall')
                  if ok then
                    installer.pioInstall(main.options.pio.pio_runtime_dir, function(_)
                    -- installer.pioInstall(base_runtime, function(_)
                      -- Once terminal install finishes, run recursion step 1 to register paths cleanly
                      clear_subdirectories(OS.nvimpio_config_dir)
                      M.ensure_toolchain_active(on_success_callback, retry_counter + 1)
                    end)
                  else
                    OS.notify('Installer module missing', 'error')
                    if type(on_success_callback) == 'function' then on_success_callback(false) end
                  end
                -------------------------------------------------------------
                elseif choice == 'Rename' then
                  clear_subdirectories(OS.nvimpio_config_dir)
                  M.ensure_toolchain_active(on_success_callback, retry_counter + 1)
                end
              end)
            end)
          else
            vim.ui.input({ prompt = 'Set pio_storage_dir path: ', default = main.options.pio.pio_storage_dir, completion = 'dir' }, function(storage_dir)
              if not storage_dir or storage_dir == '' then
                OS.notify('Execution aborted.', 'warn')
                if type(on_success_callback) == 'function' then on_success_callback(false) end
                return
              end
              main.options.pio.pio_runtime_dir = resolved_runtime_dir
              main.options.pio.pio_storage_dir = M.resolve_user_path(storage_dir)
              local ok, installer = pcall(require, 'nvimpio.pio.ui.pioInstall')
              if ok then
                installer.pioInstall(main.options.pio.pio_runtime_dir, function(_)
                -- installer.pioInstall(base_runtime, function(_)
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
      else
        OS.notify('Execution aborted: Toolchain missing.', 'warn')
        if type(on_success_callback) == 'function' then on_success_callback(false) end
      end
    end)

    -- vim.schedule(function()
    --   if vim.fn.confirm('PlatformIO not found. Install toolchain?', '&Yes\n&No', 1) == 1 then
    --     if (M.configure_paths()) then
    --       print('here')
    --       local ok, installer = pcall(require, 'nvimpio.pio.ui.pioInstall')
    --       if ok then
    --         installer.pioInstall(main.options.pio.pio_runtime_dir, function(_)
    --         -- installer.pioInstall(base_runtime, function(_)
    --           -- Once terminal install finishes, run recursion step 1 to register paths cleanly
    --           M.ensure_toolchain_active(on_success_callback, retry_counter + 1)
    --         end)
    --       else
    --         OS.notify('Installer module missing', 'error')
    --         if type(on_success_callback) == 'function' then on_success_callback(false) end
    --       end
    --     end
    --   else
    --     OS.notify('Execution aborted: Toolchain missing.', 'warn')
    --     if type(on_success_callback) == 'function' then on_success_callback(false) end
    --   end
    -- end)
  end
end

return M
