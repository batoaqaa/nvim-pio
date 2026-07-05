--stylua: ignore start
local M = {}

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
  main.initialize_full_options()
  -- vim.schedule(function()
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
        _G.metadata.core_dir = s
        _G.metadata.penv_dir = r
        -- M.ensure_toolchain_active(function()
        --   OS.notify('PlatformIO Wizard workspace paths updated successfully!')
        -- end)
      end)
    end)
  -- end)
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
      or vim.fs.joinpath(vim.uv.os_homedir(), '.platformio')
  end

  local base_runtime = raw_runtime_dir
  local bin_subfolder = OS.is_win and 'Scripts' or 'bin'
  local target_bin = vim.fs.joinpath(base_runtime, 'penv', bin_subfolder)
  local verified = false

  local local_pio_executable = vim.fs.joinpath(target_bin, (OS.is_win and 'pio.exe' or 'pio'))
  if vim.fn.executable(local_pio_executable) == 1 then
    main.config.pio_runtime_dir = target_bin
    verified = true
  end

  if verified then
    local current_path = vim.env.PATH or ''
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
      if vim.fn.confirm('PlatformIO not found. Install toolchain?', '&Yes\n&No', 1) == 1 then
        M.configure_paths()
        local ok, installer = pcall(require, 'nvimpio.pio.ui.pioInstall')
        if ok then
          installer.pioInstall(base_runtime, function(_)
            -- Once terminal install finishes, run recursion step 1 to register paths cleanly
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

return M
