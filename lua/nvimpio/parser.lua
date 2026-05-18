local M = {}

-- Helper: Safely splits string parameters by comma delimiters into clean arrays
local function split_comma_array(str)
  if not str or str == '' then
    return {}
  end
  local res = {}
  for item in str:gmatch('([^%s,]+)') do
    table.insert(res, item)
  end
  return res
end

-- Helper: Converts value strings into proper data types (Numbers, Lists, or Strings)
local function normalize_value(key, val)
  val = vim.trim(val)
  if val == '' then
    return {}
  end

  -- Parse numeric strings to actual numbers
  local num = tonumber(val)
  if num then
    return num
  end

  -- PlatformIO properties that are inherently array configurations
  if key == 'framework' or key == 'extra_scripts' or key == 'default_envs' then
    return split_comma_array(val)
  end

  return val
end

-- Helper: Replaces ${platformio.core_dir} syntax with its actual absolute value string
local function interpolate_string(val, platformio_lookup)
  if type(val) ~= 'string' then
    return val
  end

  return val:gsub('%${platformio%.([%w_]+)}', function(matched_key)
    local replacement = platformio_lookup[matched_key] or ''
    -- Ensure Windows path backslash formatting alignment matches your desired output
    if vim.fn.has('win32') == 1 then
      replacement = replacement:gsub('/', '\\')
    end
    return replacement
  end)
end

-- The Main INI Compiler Orchestrator
function M.parse_platformio_ini()
  local sep = vim.fn.has('win32') == 1 and '\\' or '/'
  local target_path = vim.uv.cwd() .. sep .. 'platformio.ini'

  if vim.fn.filereadable(target_path) == 0 then
    return nil
  end

  local f = io.open(target_path, 'r')
  if not f then
    return nil
  end

  local sections_ordered = {}
  local current_section = nil
  local global_env_defaults = {} -- Remembers pairs extracted from [env]
  local platformio_var_lookup = {} -- Remembers pairs extracted from [platformio]

  -- ─── STEP 1: PARSE RAW SEQUENTIAL STRINGS FROM FILE ───
  for line in f:lines() do
    line = vim.trim(line):gsub('%s*[;#].*$', '') -- Wipe comments instantly

    if line ~= '' then
      local section_name = line:match('^%[(.+)%]$')
      if section_name then
        -- Spawn a new ordered section container
        current_section = { section_name, {} }
        table.insert(sections_ordered, current_section)
      elseif current_section then
        local key, val = line:match('^%s*([%w_%-]+)%s*=%s*(.-)%s*$')
        if key and val then
          -- Save values temporarily for downstream interpolation passes
          if current_section[1] == 'platformio' then
            platformio_var_lookup[key] = vim.trim(val)
          elseif current_section[1] == 'env' then
            global_env_defaults[key] = vim.trim(val)
          end

          table.insert(current_section[2], { key, val })
        end
      end
    end
  end
  f:close()

  -- ─── STEP 2: APPLY GLOBAL INHERITANCE, INTERPOLATION & TYPING ───
  local final_matrix = {}

  for _, sec in ipairs(sections_ordered) do
    local s_name = sec[1]
    local pairs_array = sec[2]
    local complete_pairs = {}
    local keys_already_seen = {}

    -- Handle board profiles [env:***] inheriting from the global [env] block base
    if s_name:match('^env:') then
      for g_key, g_val in pairs(global_env_defaults) do
        local typed_val = normalize_value(g_key, g_val)
        table.insert(complete_pairs, { g_key, typed_val })
        keys_already_seen[g_key] = #complete_pairs -- Save reference position index
      end
    end

    -- Process existing properties for the active section node block
    for _, kv in ipairs(pairs_array) do
      local k, v = kv[1], kv[2]
      local typed_val = normalize_value(k, v)

      if keys_already_seen[k] then
        -- Override rule: A specific board option replaces the global inherited value
        complete_pairs[keys_already_seen[k]][2] = typed_val
      else
        table.insert(complete_pairs, { k, typed_val })
        keys_already_seen[k] = #complete_pairs
      end
    end

    -- Perform variable string interpolation expansions pass
    for _, kv in ipairs(complete_pairs) do
      local k, v = kv[1], kv[2]
      if type(v) == 'string' then
        kv[2] = interpolate_string(v, platformio_var_lookup)
      elseif type(v) == 'table' then
        for idx, item in ipairs(v) do
          v[idx] = interpolate_string(item, platformio_var_lookup)
        end
      end
    end

    -- Also process global [env] independently into its own formatted output
    if s_name == 'env' then
      local env_standalone_pairs = {}
      for g_key, g_val in pairs(global_env_defaults) do
        table.insert(env_standalone_pairs, { g_key, normalize_value(g_key, g_val) })
      end
      complete_pairs = env_standalone_pairs
    end

    table.insert(final_matrix, { s_name, complete_pairs })
  end

  return final_matrix
end

return M
