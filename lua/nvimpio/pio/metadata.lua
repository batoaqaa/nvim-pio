local M = {}

_G.isBusy = false
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
  envs = {},
  active_env = '',
  default_envs = {},
  penv_dir = require('nvimpio').config.pio_runtime_dir,
  core_dir = require('nvimpio').config.pio_storage_dir,
  packages_dir = '',
  platforms_dir = '',
  query_driver = '**',
  includes_build = {},
  includes_compatlib = {},
  includes_toolchain = {},
  includes_libdeps = {},
  cc_path = '',
  cc_flags = {},
  cc_defines = {},
  cxx_path = '',
  cxx_flags = {},
  cxx_defines = {},
  gdb_path = '',
  pio_defines = {},
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
    -- vim.schedule(function()
      -- M.save_project_config(true)
      -------------------------------------------------------------------------------
      if key == 'toolchain_root' then
        local from = 'Meta PATH env: '
        local binPath = value .. '/bin'

        local oldPath = oldValue .. '/bin'
        removeFromPath(oldPath)
        removeFromPath(OS.project_dir)
        -- local end_time = vim.loop.hrtime()
        -- local duration = (end_time - start_time) / 1e6
        -- OS.notify(string.format('%s %s removed from path in %.2fms', from, oldPath, duration), 'info')
        OS.notify(string.format('%s %s removed from path', from, oldPath), 'info')

        vim.env.PATH = binPath .. OS.path_sep .. vim.env.PATH
        vim.env.PATH = OS.project_dir .. OS.path_sep .. vim.env.PATH
        OS.notify(string.format('%s %s added to path',from, binPath), 'info')

        -- ----------------------------- Trace ----------------------------------------
        -- -- 1. Grab the current execution stack call trace
        -- local trace = debug.traceback()
        --
        -- -- 2. Format a highly detailed visual report string
        -- local log_msg = string.format(
        --   "\n=================== PIO TRACE: isBusy changed ===================\n" ..
        --   "Time: %s\n" ..
        --   "Mutation: %s -> %s\n" ..
        --   "Call Stack:\n%s\n" ..
        --   "===============================================================\n",
        --   os.date("%Y-%m-%d %H:%M:%S"),
        --   tostring(oldValue),
        --   tostring(value),
        --   trace
        -- )
        --
        -- -- 3. CHOOSE AN OUTPUT TARGET:
        --
        -- -- Option A: Print directly to Neovim's system logs (Read via typing :messages)
        -- vim.schedule(function() print(log_msg) end)
        --
        -- -- Option B: Write to a dedicated file in your project directory (Recommended!)
        -- -- local log_file_path = vim.fn.stdpath("data") .. "/pio_isBusy_trace.log"
        -- -- local file = io.open(log_file_path, "a")
        -- -- if file then
        -- --   file:write(log_msg)
        -- --   file:close()
        -- -- end
        -- -------------------------------------------------------------------------------
      -------------------------------------------------------------------------------
      elseif key == 'active_env' then
        local from = 'Meta active_env change: '

        OS.notify("in active_env change")
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

        vim.schedule(function()
          _G.isBusy = true
          local pio_refresh = require('nvimpio.pio.upkeep').pio_refresh
          pio_refresh(function(suscess)
            if (suscess) then
              do end
              -- require('nvimpio.clangd.control').getUnknownArgsCli(from)
            end
            _G.isBusy = false
          end, from)
          vim.cmd('redrawstatus')
        end)
      -- elseif key == 'last_projectChecksum' then
      end
    -- end)
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
          -- _G.metadata[k] = v
          -- _pio_metadata[k] = v
          if k == 'toolchain_root' then _G.metadata[k] = v
          else _pio_metadata[k] = v end
        end
        last_saved_hash = vim.fn.sha256(json_data)
        -- return
      end
    end
  end
  -- else
  local active_env, metadata = M.get_active_env('meta load: ')
  if active_env and active_env ~= '' then
    OS.notify("load_project_config" .. active_env)
    metadata = metadata or {}
    _pio_metadata.core_dir = metadata.core_dir
    _pio_metadata.packages_dir = metadata.packages_dir
    _pio_metadata.platforms_dir = metadata.platforms_dir
    _pio_metadata.default_envs = metadata.default_envs
    _pio_metadata.envs = metadata.envs
    if _pio_metadata.active_env ~= active_env then
      _G.metadata.active_env = active_env
    end
  end
  -- end

  -- If no file, initialize hash with defaults
  last_saved_hash = vim.fn.sha256(misc.jsonFormat(_pio_metadata))
end

-- ///////////////////// get_active_env /////////////////////

-- 1. Helper: Converts raw string properties to numbers, string arrays, or defaults
local function normalize_value(key, value)
  if not value or value == "" then
    -- FIX 1: Enforce clean matching on 'envs$' without the rigid leading underscore crash blocker
    if key:match("envs$") or key:match("_deps$") or key:match("_scripts$") or key:match("_filters$") or key:match("flags$") then
      return {}
    end
    return ""
  end

  local str_val = tostring(value)
  local clean_text = str_val:gsub("^%s*", "")

  -- =========================================================================
  -- RULE 1: COMPILER FLAGS MATRIX ENGINE
  -- =========================================================================
  local is_flag_key = key:match("flags$") or key:match("options$")
  local has_flag_prefix = clean_text:match("^%-[DIOw]") ~= nil

  if is_flag_key or has_flag_prefix then
    local working_str = str_val:gsub("\\%s*\n", " ")
    local tokens = {}
    local current_token = {}
    local in_quotes = false
    local quote_char = nil

    for i = 1, #working_str do
      local char = working_str:sub(i, i)
      if (char == '"' or char == "'") then
        if not in_quotes then in_quotes = true; quote_char = char
        elseif char == quote_char then in_quotes = false; quote_char = nil end
        table.insert(current_token, char)
      elseif (char == ' ' or char == '\t' or char == '\n' or char == '\r') and not in_quotes then
        if #current_token > 0 then
          local t_str = table.concat(current_token)
          if t_str ~= "" and not t_str:match("^[;#]") then table.insert(tokens, t_str) end
          current_token = {}
        end
      else
        table.insert(current_token, char)
      end
    end
    if #current_token > 0 then
      local t_str = table.concat(current_token)
      if t_str ~= "" and not t_str:match("^[;#]") then table.insert(tokens, t_str) end
    end
    return tokens
  end

  -- =========================================================================
  -- RULE 2: LIST ARCHITECTURE ENGINE
  -- =========================================================================
  -- FIX 2: Corrected matching pattern to capture default_envs perfectly
  local is_list_key = key:match("envs$") or key:match("_deps$") or key:match("_scripts$") or key:match("_filters$")
  local is_multiline = str_val:find("\n") ~= nil

  if is_list_key or is_multiline then
    local separators = is_multiline and "[\r\n]+" or "[%s,]+"
    return vim.split(str_val, separators, { trimempty = true })
  end

  -- =========================================================================
  -- RULE 3: SCALAR FALLBACK (Numbers or basic strings)
  -- =========================================================================
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

-- 3. Pure Data Pipeline (Multiline & Indentation Aware)
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

  local pio_vars = {}
  local base_env = {}
  local raw_envs = {}
  local ordered_sections = {} -- FIX 1: Initialized local tracker array cleanly
  local current_sec = nil
  local last_key = nil

  -- Parse configuration line-by-line cleanly
  for line in vim.gsplit(content, '\n') do
    line = line:gsub('\r$', '') -- Strip carriage returns

    -- 1. Check if the line is purely a comment line BEFORE doing anything else
    local is_pure_comment = line:match("^%s*[;#]") ~= nil

    -- Filter out trailing inline comments safely
    local comment_start = line:find('%s*[;#]')
    if comment_start then
      line = line:sub(1, comment_start - 1)
    end

    local trimmed = line:match('^%s*(.-)%s*$') or ""
    local sec = trimmed:match('^%[(.+)%]$')

    if sec then
      current_sec = sec:gsub("%s", "") -- Normalize section name spaces
      last_key = nil
      local env_name = current_sec:match('^env:(.+)$')
      if env_name then
        raw_envs[env_name] = raw_envs[env_name] or {}
        -- Safely append the environment section name preserving sequence order
        if not vim.tbl_contains(ordered_sections, env_name) then
          table.insert(ordered_sections, env_name)
        end

      end

    -- 2. If it's a pure comment line, skip it completely but DO NOT clear last_key!
    -- This keeps the multiline bridge open for the build flags beneath it.
    elseif not is_pure_comment and current_sec and trimmed ~= '' then

      local k, v = trimmed:match('^([%w_%-%.]+)%s*=%s*(.*)$')

      -- Enforce key rules: Keys cannot start with minus signs or numbers
      if k and k:match('^%a[%w_%-%.]*$') then
        last_key = k
        v = vim.trim(v)
        if current_sec == 'platformio' then pio_vars[k] = v
        elseif current_sec == 'env' then base_env[k] = v
        elseif current_sec:match('^env:') then
          local env_name = current_sec:match('^env:(.+)$')
          if env_name then raw_envs[env_name][k] = v end
        end

      -- 3. If it's a value block with no key match, map it to the active multi-line stack
      elseif last_key then
        local current_val = ""
        if current_sec == 'platformio' then current_val = pio_vars[last_key] or ""
        elseif current_sec == 'env' then current_val = base_env[last_key] or ""
        elseif current_sec:match('^env:') then
          local env_name = current_sec:match('^env:(.+)$')
          current_val = env_name and raw_envs[env_name] and raw_envs[env_name][last_key] or ""
        end

        local sep = (current_val == "") and "" or "\n"
        local updated_val = current_val .. sep .. trimmed

        if current_sec == 'platformio' then pio_vars[last_key] = updated_val
        elseif current_sec == 'env' then base_env[last_key] = updated_val
        elseif current_sec:match('^env:') then
          local env_name = current_sec:match('^env:(.+)$')
          if env_name then raw_envs[env_name][last_key] = updated_val end
        end
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

  pio_vars.core_dir = pcall(function()
    return interpolate(pio_vars.core_dir or storage_fallback, nil, pio_vars, base_env, raw_envs)
  end) and interpolate(pio_vars.core_dir or storage_fallback, nil, pio_vars, base_env, raw_envs) or storage_fallback

  require('nvimpio').config.pio_storage_dir = pio_vars.core_dir

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

  -- =========================================================================
  -- DETERMINISTIC TARGET RESOLUTION ENGINE
  -- =========================================================================
  local target = nil
  local def_envs = metadata.default_envs

  -- RULE 1: Check live User Preference FIRST for LSP context consistency
  if _G.metadata and _G.metadata.active_env and _G.metadata.active_env ~= "" then
    local clean_active = vim.trim(tostring(_G.metadata.active_env)):gsub('\r$', '')
    if metadata.envs[clean_active] then
      target = clean_active
    end
  end

  -- RULE 2: Fall back to default_envs line SECOND if the user hasn't forced a selection
  if not target then
    -- 1. If default_envs is a table list, clean each string and look for an exact match
    if type(def_envs) == 'table' then
      for _, name in ipairs(def_envs) do
        local clean_name = vim.trim(tostring(name)):gsub('\r$', '')
        if metadata.envs[clean_name] then
          target = clean_name
          break
        end
      end
    -- 2. If default_envs broke out as a raw single string, check it directly
    elseif type(def_envs) == 'string' then
      local clean_name = vim.trim(def_envs):gsub('\r$', '')
      if metadata.envs[clean_name] then
        target = clean_name
      end
    end
  end

  -- 3. If all else fails, read the absolute first environment found in the file order array
  if not target and #ordered_sections > 0 then
    target = ordered_sections[1]
  end
  -- =========================================================================

  return target, metadata
end
-- ///////////////////// get_active_env /////////////////////

--========================================================================================
--INFO:
-- 4. Initialization
-------------------------------------------------------------------------------
M.load_project_config()

return M
