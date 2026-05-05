local M = {}

-------------------------------------------------------------------------------------------------------
local last_saved_hash = ''

-- local function remove_nearby_front(target_path)
--   local start_time = vim.loop.hrtime()
--   local sep = vim.fn.has('win32') == 1 and ';' or ':'
--   local path = vim.env.PATH
--
--   -- Escape special characters in the path for Lua pattern matching
--   local escaped_target = vim.pesc(target_path)
--
--   -- Pattern logic:
--   -- 1. ^(.-)      -> Capture any characters at the very start (up to our target)
--   -- 2. sep?       -> Match an optional separator before the target
--   -- 3. target     -> Match your specific path
--   -- 4. sep?       -> Match an optional separator after the target
--   -- 5. (.*)$      -> Capture everything else until the end
--   local pattern = '^(.-)' .. sep .. '?' .. escaped_target .. sep .. '?' .. '(.*)$'
--
--   local prefix, suffix = path:match(pattern)
--
--   -- If we found it, verify it was near the front (e.g., within 3 separators)
--   if prefix and suffix then
--     local _, sep_count = prefix:gsub(sep, '')
--     if sep_count < 3 then
--       -- Reconstruct the path, ensuring we don't double-up separators
--       local new_path = prefix .. (prefix ~= '' and suffix ~= '' and sep or '') .. suffix
--       vim.env.PATH = new_path
--       local end_time = vim.loop.hrtime()
--       local duration = (end_time - start_time) / 1e6
--       vim.notify(string.format('compiledb: paths fixed in %.2fms', duration), vim.log.levels.INFO)
--       return true
--     end
--   end
--   return false
-- end

-- function M.updateDefaultEnv()
--   local pio_ini = vim.fn.getcwd() .. '/platformio.ini'
--   local active_env = _G.metadata.active_env
--
--   if not active_env or active_env == '' then
--     vim.notify('No active_env found in metadata', vim.log.levels.WARN)
--     return
--   end
--
--   if vim.fn.filereadable(pio_ini) == 0 then
--     vim.notify('platformio.ini not found', vim.log.levels.ERROR)
--     return
--   end
--
--   local lines = vim.fn.readfile(pio_ini)
--   local updated = false
--
--   for i, line in ipairs(lines) do
--     -- Matches 'default_envs =' with any amount of whitespace
--     if line:match('^%s*default_envs%s*=') then
--       lines[i] = 'default_envs = ' .. active_env
--       updated = true
--       break
--     end
--   end
--
--   if updated then
--     vim.fn.writefile(lines, pio_ini)
--     print('✅ platformio.ini updated: default_envs = ' .. active_env)
--   else
--     vim.notify("Could not find 'default_envs =' line in platformio.ini", vim.log.levels.WARN)
--   end
-- end

--INFO:
-- stylua: ignore
-------------------------------------------------------------------------------
local function removeFromPath(path_to_remove)
  local sep = vim.fn.has('win32') == 1 and ';' or ':'
  -- Split the path by the separator
  local paths = vim.split(vim.env.PATH, sep, { trimempty = true })

  -- Filter out the path we want to remove
  local new_paths = vim.tbl_filter(function(p) return p ~= path_to_remove end, paths)

  -- Rejoin and update the environment
  vim.env.PATH = table.concat(new_paths, sep)
end

--INFO:
-------------------------------------------------------------------------------
-- Usage:
-- 1. Internal State & Defaults
local _pio_metadata = {
  isBusy = false,
  envs = {},
  active_env = '',
  default_envs = {},
  core_dir = '',
  packages_dir = '',
  platforms_dir = '',
  query_driver = '**',
  cc_compiler = '',
  includes_build = {},
  includes_compatlib = {},
  includes_toolchain = {},
  cc_path = '',
  cc_flags = {},
  cxx_path = '',
  cxx_flags = {},
  gdb_path = '',
  defines = {},
  triplet = '',
  toolchain_root = '',
  sysroot = '',
  fallbackFlags = {},
  originalPath = vim.env.PATH,
  last_projectChecksum = '', -- Used to track changes
}
-- 2. The Reactive Proxy Wrapper
-- Any write to _G.metadata.key = val triggers this logic
_G.metadata = setmetatable({}, {
  __index = _pio_metadata,
  __newindex = function(_, key, value)
    if _pio_metadata[key] == value then
      -- print('Value is identical, returning...') -- DEBUG LINE
      return
    end -- Performance check
    -- print('Newindex attempt for: ' .. tostring(key)) -- DEBUG LINE
    local oldValue = _pio_metadata[key]
    _pio_metadata[key] = value

    -- Trigger background actions
    vim.schedule(function()
      -- M.save_project_config(true)
      if key == 'toolchain_root' then
        local binPath = value .. '/bin'
        local sep = (vim.fn.has('win32') == 1 and ';' or ':')

        local oldPath = oldValue .. '/bin'
        local start_time = vim.loop.hrtime()
        -- remove_nearby_front(oldPath)
        removeFromPath(oldPath)
        local end_time = vim.loop.hrtime()
        local duration = (end_time - start_time) / 1e6
        vim.notify(string.format('PIO env: ' .. oldPath .. ' removed from path in %.2fms', duration), vim.log.levels.INFO)

        vim.env.PATH = binPath .. sep .. vim.env.PATH
        -- vim.env.PATH = binPath .. sep .. _G.metadata.originalPath

        vim.notify('PIO env: ' .. binPath .. ' added to path', vim.log.levels.INFO, { title = 'PlatformIO', render = 'compact' })
      elseif key == 'last_projectChecksum' then
        -- elseif key == 'active_env' then
        --   _pio_metadata['isBusy'] = true
        --   vim.misc.updateDefaultEnv()
        --   _pio_metadata['isBusy'] = false
      end
    end)
  end,
})

local config_path = vim.fs.joinpath(vim.uv.cwd(), '.project_config.json')
-- -- Add this temporary line in a file where you are coding:
-- ---@type platformio.utils.misc
-- local misc = vim.misc
--INFO:
-- 2. Save Logic (Uses sha256 for stability)
-------------------------------------------------------------------------------
function M.save_project_config(from)
  -- 1. Generate the formatted string directly, jsonFormat already returns a string!
  local ok, pretty_json = pcall(vim.misc.jsonFormat, _pio_metadata)

  if not ok or not pretty_json then
    print('Error formatting metadata')
    return
  end

  local current_hash = vim.fn.sha256(pretty_json)

  -- 2. Only write if the content actually changed
  if current_hash ~= last_saved_hash then
    local status, err = vim.misc.writeFile(config_path, pretty_json, {})

    if status then
      last_saved_hash = current_hash
      vim.notify(from .. 'config save success', vim.log.levels.INFO, { title = 'PlatformIO' })
    else
      vim.notify(from .. 'config save failed==> ' .. (err or 'unknown error'), vim.log.levels.ERROR)
    end
  end
end

--INFO:
-- 3. Load Logic (Populates proxy safely)
-------------------------------------------------------------------------------
function M.load_project_config()
  if vim.fn.filereadable(config_path) == 1 then
    local _, json_data = vim.misc.readFile(config_path)
    if json_data then
      local ok, table_data = pcall(vim.json.decode, json_data)
      if ok and type(table_data) == 'table' then
        -- We update _pio_metadata directly to avoid triggering
        -- 50+ notifications/restarts during the initial load loop
        for k, v in pairs(table_data) do
          _G.metadata[k] = v
        end
        last_saved_hash = vim.fn.sha256(json_data)
        return
      end
    end
  end
  -- If no file, initialize hash with defaults
  last_saved_hash = vim.fn.sha256(vim.misc.jsonFormat(_pio_metadata))
end

--INFO:
-- 4. Initialization
-------------------------------------------------------------------------------
M.load_project_config()

return M
