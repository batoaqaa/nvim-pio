local M = {}

-------------------------------------------------------------------------------------------------------
local last_saved_hash = ''

--INFO:
-- stylua: ignore start
-------------------------------------------------------------------------------
local function removeFromPath(path_to_remove)
  if not path_to_remove or path_to_remove == '' then return end

  -- 1. Standardize the path we want to delete using Neovim's built-in normalizer
  local target_clean = vim.fs.normalize(path_to_remove)
  if OS.is_win then target_clean = target_clean:lower() end

  -- 2. Split the active system PATH string into a clean list array
  local active_paths = vim.split(vim.env.PATH or '', OS.path_sep, { trimempty = true })

  -- 3. Filter the array using normalized cross-platform validations
  local preserved_paths = vim.tbl_filter(function(path_segment)
    -- Normalize the current segment we are checking from the system array
    local segment_clean = vim.fs.normalize(path_segment)

    -- Windows paths are completely case-insensitive; force lowercase to prevent
    -- 'C:\' vs 'c:\' drive letter mismatch bugs from bypassing the filter!
    if OS.is_win then segment_clean = segment_clean:lower() end

    -- Return true ONLY if this system path does NOT match our target path
    return segment_clean ~= target_clean
  end, active_paths)

  -- 4. Rejoin the array and update Neovim's active process environment context instantly
  vim.env.PATH = table.concat(preserved_paths, OS.path_sep)
end

--INFO:
-------------------------------------------------------------------------------
--[[
-- Usage:
-- 1. Internal State & Defaults
---@class PioGlobalMetadata
---@field active_env string|nil The currently running target board configuration environment
---@field isBusy boolean Flag indicating if background processes are executing commands
---@field cc_path string Path mapping to the current active C compiler binary executable
---@field cxx_path string Path mapping to the active C++ compiler binary executable
---@field gdb_path string Path mapping to the target hardware debugger binary executable
---@field last_projectChecksum string|nil The unique build signature hash string from PlatformIO

-- Initialize the global object cleanly without overwriting if it exists
---@type PioGlobalMetadata
]]

local _pio_metadata = {
  isBusy = false,
  envs = {},
  active_env = '',
  default_envs = {},
  penv_dir = require('nvimpio').config.pio_runtime_dir,
  core_dir = require('nvimpio').config.pio_storage_dir,
  packages_dir = '',
  platforms_dir = '',
  query_driver = '**',
  -- cc_compiler = '',
  -- libsource_dirs = {},
  includes_build = {},
  includes_compatlib = {},
  includes_toolchain = {},
  auto_defines = {},
  cc_path = '',
  cc_flags = {},
  cxx_path = '',
  cxx_flags = {},
  gdb_path = '',
  defines = {},
  triplet = '',
  toolchain_root = '',
  sysroot = '',
  -- fallbackFlags = {},
  originalPath = vim.env.PATH,
  last_projectChecksum = '', -- Used to track changes
  port_parameters = {},
}
-- 2. The Reactive Proxy Wrapper
-- Any write to _G.metadata.key = val triggers this logic
_G.metadata = setmetatable({}, {
  __index = _pio_metadata,
  __newindex = function(_, key, value)
    -- Guard: Skip execution if the new value is identical to the current state
    if _pio_metadata[key] == value then return end -- Performance check
    -- print('Newindex attempt for: ' .. tostring(key)) -- DEBUG LINE
    local oldValue = _pio_metadata[key]
    _pio_metadata[key] = value

    -- Trigger background actions
    vim.schedule(function()
      -- M.save_project_config(true)
      -------------------------------------------------------------------------------
      if key == 'toolchain_root' then
        local from = 'Meta PATH env: '
        local binPath = value .. '/bin'

        local oldPath = oldValue .. '/bin'
        local start_time = vim.loop.hrtime()
        -- remove_nearby_front(oldPath)
        removeFromPath(oldPath)
        local end_time = vim.loop.hrtime()
        local duration = (end_time - start_time) / 1e6
        OS.notify(string.format('%s %s removed from path in %.2fms', from, oldPath, duration), 'info')

        vim.env.PATH = binPath .. OS.path_sep .. vim.env.PATH
        -- vim.env.PATH = binPath .. sep .. _G.metadata.originalPath
        OS.notify(string.format('%s %s added to path',from, binPath), 'info')

      -------------------------------------------------------------------------------
      elseif key == 'active_env' then
        local from = 'Meta active_env change: '
        _G.metadata.isBusy = true

        -- local pio = require('nvimpio.pio.upkeep')
        local active_env, metadata = M.get_active_env(from)
        if active_env and active_env ~= '' then
          metadata = metadata or {}
          _pio_metadata.core_dir = metadata.core_dir
          _pio_metadata.packages_dir = metadata.packages_dir
          _pio_metadata.platforms_dir = metadata.platforms_dir
          _pio_metadata.default_envs = metadata.default_envs
          _pio_metadata.envs = metadata.envs
        end

        local pio_refresh = require('nvimpio.pio.upkeep').pio_refresh
        pio_refresh(function(_)
          -- if (suscess) then require('nvimpio.clangd.control').getUnknownArgs(from) end
          if _G.metadata then _G.metadata.isBusy = false end
        end, from)
        vim.cmd('redrawstatus')
      -- elseif key == 'last_projectChecksum' then
      end
    end)
  end,
})

local project_root = vim.g.platformioRootDir or vim.uv.cwd() or '.'
project_root = vim.fs.normalize(project_root)
local config_path = OS.project_config  --vim.fs.joinpath(project_root, '.nvimpio', '.project_config.json')

--INFO:
-- 2. Save Logic (Uses sha256 for stability)
-------------------------------------------------------------------------------
function M.save_project_config(from)
  local misc = require('nvimpio.utils.misc')
  -- 1. Generate the formatted string directly, jsonFormat already returns a string!
  local ok, pretty_json = pcall(misc.jsonFormat, _G.metadata)

  if not ok or not pretty_json then
    OS.notify('Error formatting metadata', 'error')
    return
  end

  local current_hash = vim.fn.sha256(pretty_json)

  -- 2. Only write if the content actually changed
  if current_hash ~= last_saved_hash then
    local status, err = misc.writeFile(config_path, pretty_json, {})
    if status then
      last_saved_hash = current_hash
      OS.notify(from .. 'config save success', 'info')
    else
      OS.notify(from .. 'config save failed==> ' .. (err or 'unknown error'), 'error')
    end
  end
end

--INFO:
-- 3. Load Logic (Populates proxy safely)
-------------------------------------------------------------------------------
function M.load_project_config()
  local misc = require('nvimpio.utils.misc')
  if vim.fn.filereadable(config_path) == 1 then
    local _, json_data = misc.readFile(config_path)
    if json_data then
      local ok, table_data = pcall(vim.json.decode, json_data)
      if ok and type(table_data) == 'table' then
        for k, v in pairs(table_data) do
          _G.metadata[k] = v
          -- _pio_metadata[k] = v
          -- if k == 'toolchain_root' then _G.metadata[k] = v
          -- else _pio_metadata[k] = v end
        end
        last_saved_hash = vim.fn.sha256(json_data)
        return
      end
    end
  else
    local active_env, metadata = M.get_active_env('meta load: ')
    if active_env and active_env ~= '' then
      OS.notify(active_env)
      metadata = metadata or {}
      _pio_metadata.core_dir = metadata.core_dir
      _pio_metadata.packages_dir = metadata.packages_dir
      _pio_metadata.platforms_dir = metadata.platforms_dir
      _pio_metadata.default_envs = metadata.default_envs
      _pio_metadata.envs = metadata.envs
      _G.metadata.active_env = active_env
    end
  end

  -- If no file, initialize hash with defaults
  last_saved_hash = vim.fn.sha256(misc.jsonFormat(_pio_metadata))
end

-- ///////////////////// get_active_env /////////////////////
-- stylua: ignore start
-- 1. Helper: Converts raw string properties to numbers, string arrays, or defaults
local function normalize_value(key, value)
  if not value or value == "" then
    return (key == "extra_scripts" or key == "default_envs") and {} or ""
  end
  if key == "default_envs" or key == "extra_scripts" then
    return vim.split(value, "[%s,]+", { trimempty = true })
  end
  return tonumber(value) or value
end

-- 2. Helper: Recursively interpolates ${platformio.core_dir} or ${this.board} tokens
local function interpolate(text, current_env, pio_vars, base_env, raw_envs)
  if type(text) ~= "string" or not text:match("%$%{.-%}") then return text end

  local resolved = (text:gsub("%$%{([^}]+)%}", function(token)
    if token:match("^platformio%.") then
      return pio_vars[token:gsub("^platformio%.", "")] or ""
    end
    if token:match("^this%.") and current_env and raw_envs[current_env] then
      local key = token:gsub("^this%.", "")
      return raw_envs[current_env][key] or base_env[key] or ""
    end
    return "${" .. token .. "}"
  end))

  return (resolved ~= text) and interpolate(resolved, current_env, pio_vars, base_env, raw_envs) or resolved
end

-- 3. Pure Data Pipeline (No Global Side-Effects)
function M.get_active_env(from)
  from = (type(from) == 'string' and from ~= '') and from or 'PIO: '
  local path = vim.fs.joinpath(vim.uv.cwd(), 'platformio.ini')

  if vim.fn.filereadable(path) == 0 then
    OS.notify(from .. 'platformio.ini not found in workspace.', 'error')
    return nil, {}
  end
  local misc = require('nvimpio.utils.misc')
  local ok, content = misc.readFile(path)
  if not ok or not content then
    OS.notify(from .. 'Could not read platformio.ini at ' .. path, 'warn')
    return nil, {}
  end

  local pio_vars, base_env, raw_envs, current_sec = {}, {}, {}, nil

  -- Parse configuration line-by-line without collapsing spaces
  for line in vim.gsplit(content, '\n') do
    line = line:gsub('\r$', ''):gsub('^%s+', ''):gsub('%s+$', ''):gsub('%s*[;#].*$', '')
    local sec = line:match('^%[(.+)%]$')

    if sec then
      current_sec = sec
      local env_name = sec:match('^env:(.+)$')
      if env_name then raw_envs[env_name] = raw_envs[env_name] or {} end
    elseif current_sec and line ~= '' then
      local k, v = line:match('^%s*([%w_%-]+)%s*=%s*(.-)%s*$')
      if k and v then
        if current_sec == 'platformio' then pio_vars[k] = vim.trim(v)
        elseif current_sec == 'env' then base_env[k] = vim.trim(v)
        elseif current_sec:match('^env:') then raw_envs[current_sec:match('^env:(.+)$')][k] = vim.trim(v) end
      end
    end
  end

  if not next(raw_envs) then
    OS.notify(from .. 'No active environments found in platformio.ini', 'warn')
    return nil, {}
  end

  -- =========================================================================
  -- Pre-calculate core_dir directly inside pio_vars
  -- =========================================================================
  local storage_fallback = require('nvimpio').config.pio_storage_dir or "~/.platformio"

  -- Resolve core_dir first so it exists inside pio_vars for packages/platforms loops
  pio_vars.core_dir = pcall(function()
    return interpolate(pio_vars.core_dir or storage_fallback, nil, pio_vars, base_env, raw_envs)
  end) and interpolate(pio_vars.core_dir or storage_fallback, nil, pio_vars, base_env, raw_envs) or storage_fallback

  -- Update your plugin core config storage layer synchronously
  require('nvimpio').config.pio_storage_dir = pio_vars.core_dir

  -- Construct final metadata response schema cleanly using pre-seeded variables
  local metadata = {
    core_dir = pio_vars.core_dir,
    packages_dir = interpolate(pio_vars.packages_dir or "${platformio.core_dir}/packages", nil, pio_vars, base_env, raw_envs),
    platforms_dir = interpolate(pio_vars.platforms_dir or "${platformio.core_dir}/platforms", nil, pio_vars, base_env, raw_envs),
    default_envs = normalize_value('default_envs', pio_vars.default_envs),
    envs = {}
  }
  -- =========================================================================

  -- Merge [env] defaults down into each specific profile block
  for env, locals in pairs(raw_envs) do
    metadata.envs[env] = vim.tbl_deep_extend("force", base_env, locals)
    for k, v in pairs(metadata.envs[env]) do
      metadata.envs[env][k] = normalize_value(k, interpolate(v, env, pio_vars, base_env, raw_envs))
    end
    metadata.envs[env].extra_scripts = metadata.envs[env].extra_scripts or {}
  end

  -- Determine active environment order target (INI Default -> First Valid)
  local target = nil
  local def_envs = metadata.default_envs -- Extract to a local variable

  if type(def_envs) == 'table' then
    for _, env_name in ipairs(def_envs) do -- LSP knows 'def_envs' is safely a table here
      if metadata.envs[env_name] then target = env_name break
      end
    end
  end

  target = target or (metadata.envs[_G.metadata.active_env] and _G.metadata.active_env) or next(metadata.envs)

  return target, metadata
end
-- stylua: ignore end
-- ///////////////////// get_active_env /////////////////////

--========================================================================================
--INFO:
-- 4. Initialization
-------------------------------------------------------------------------------
M.load_project_config()

return M
