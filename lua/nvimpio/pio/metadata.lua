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
-- Usage:
-- 1. Internal State & Defaults
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
  -- includes_build = {},
  -- includes_compatlib = {},
  -- includes_toolchain = {},
  cc_path = '',
  -- cc_flags = {},
  cxx_path = '',
  -- cxx_flags = {},
  gdb_path = '',
  -- defines = {},
  triplet = '',
  toolchain_root = '',
  sysroot = '',
  -- fallbackFlags = {},
  originalPath = vim.env.PATH,
  last_projectChecksum = '', -- Used to track changes
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
      elseif key == 'active_env' then
        local from = 'Meta active_env change: '
        _G.metadata.isBusy = true


        -- OS.notify(from .. 'compiledb update ...', 'info')
        --
        -- local pio = require('nvimpio.pio.upkeep')
        -- local cb = function(status)
          -- pio.handlePioDB(status, function (suscess)
          --   if(suscess)then
          --     OS.notify(from .. 'compiledb update Success', 'info')
              local pio_refresh = require('nvimpio.pio.upkeep').pio_refresh
              pio_refresh(function(suscess)
                if suscess then
                  -- local pio = require('nvimpio.pio.upkeep')
                  -- local active_env, metadata = pio.get_active_env(from)
                  -- if active_env and active_env ~= '' then
                  --   metadata = metadata or {}
                  --   _pio_metadata.core_dir = metadata.core_dir
                  --   _pio_metadata.packages_dir = metadata.packages_dir
                  --   _pio_metadata.platforms_dir = metadata.platforms_dir
                  --   _pio_metadata.default_envs = metadata.default_envs
                  --   _pio_metadata.envs = metadata.envs
                  --   _pio_metadata.active_env = active_env
                  -- end
                end
                -- if (suscess) then require('nvimpio.clangd.control').getUnknownArgs(from) end
                if _G.metadata then _G.metadata.isBusy = false end
              end, from)
        --     else
        --       OS.notify(string.format('%sBuild Failed %s',from), 'error')
        --       _G.metadata.isBusy = false
        --     end
        --   end)
        -- end
        -- local cmd = 'pio run -t compiledb -e ' .. value
        -- pio.run_sequence({ cmnds = { cmd }, cb = cb })

        -- vim.system({ 'pio', 'run', '-t', 'compiledb', '-s', '-e', value }, { text = true }, function(obj)
        --   vim.schedule(function()
        --     if obj.code == 0 then
        --       OS.notify(from .. 'compiledb update Success', 'info')
        --       local pio_refresh = require('nvimpio.pio.upkeep').pio_refresh
        --       pio_refresh(function()
        --         require('nvimpio.clangd.control').getUnknownArgs(from)
        --         if _G.metadata then _G.metadata.isBusy = false end
        --         -- clangdRestart()
        --       end, from)
        --     else
        --       local err = (obj.stderr and obj.stderr ~= '') and obj.stderr or 'Check PIO logs'
        --       OS.notify(string.format('%sBuild Failed %s',from, err), 'error')
        --       _G.metadata.isBusy = false
        --     end
        --   end)
        -- end)
      -- elseif key == 'last_projectChecksum' then
      --   local from = 'Meta last_projectChecksum change: '
      --   _G.metadata.isBusy = true
      --   OS.notify(from .. 'compiledb update ...', 'info')
      --
      --   local pio = require('nvimpio.pio.upkeep')
      --   local cb = function(status)
      --     pio.handlePioDB(status, function (suscess)
      --       if(suscess)then
      --         OS.notify(from .. 'compiledb update Success', 'info')
      --         local pio_refresh = require('nvimpio.pio.upkeep').pio_refresh
      --         pio_refresh(function()
      --           require('nvimpio.clangd.control').getUnknownArgs(from)
      --           if _G.metadata then _G.metadata.isBusy = false end
      --         end, from)
      --       else
      --         OS.notify(string.format('%sBuild Failed %s',from), 'error')
      --         _G.metadata.isBusy = false
      --       end
      --     end)
      --   end
      --   local cmd = 'pio run -t compiledb -e ' .. pio.get_active_env(from)
      --   pio.run_sequence({ cmnds = { cmd }, cb = cb })
      end
    end)
  end,
})

-- Highly optimized string retriever for statusline rendering loops
function M.get_status_string()
  -- Catch early boot or uninitialized states safely
  if not _G.metadata or not _G.metadata.active_env or _G.metadata.active_env == "" then
    return ""
  end

  -- Return a clean visual indicator snippet (using the filled circle or an electronics icon)
  return string.format("   %s", _G.metadata.active_env)
end

local config_path = vim.fs.joinpath(vim.uv.cwd(), '.project_config.json')

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

  -- local build_dir = misc.joinPath(vim.uv.cwd(), '.pio', 'build')
  -- local checksum_file = misc.joinPath(build_dir, 'project.checksum')
  -- local cok, current_checksum = misc.readFile(checksum_file)
  if vim.fn.filereadable(config_path) == 1 then
    local _, json_data = misc.readFile(config_path)
    if json_data then
      local ok, table_data = pcall(vim.json.decode, json_data)
      if ok and type(table_data) == 'table' then
        for k, v in pairs(table_data) do
          -- _G.metadata[k] = v
          _pio_metadata[k] = v
        end
        last_saved_hash = vim.fn.sha256(json_data)
        return
      end
    end
  -- elseif cok and (type(current_checksum) == 'string' and current_checksum ~= '') then
  --   _G.metadata.last_projectChecksum = current_checksum
  --   OS.notify('checksum_file')
  -- else
  --   _G.metadata.last_projectChecksum = vim.fn.sha256('')
  --   OS.notify('no checksum_file')
  end
  -- If no file, initialize hash with defaults
  last_saved_hash = vim.fn.sha256(misc.jsonFormat(_pio_metadata))
  local pio = require('nvimpio.pio.upkeep')
  local active_env, metadata = pio.get_active_env('meta load: ')
  if active_env and active_env ~= '' then
    metadata = metadata or {}
    _pio_metadata.core_dir = metadata.core_dir
    _pio_metadata.packages_dir = metadata.packages_dir
    _pio_metadata.platforms_dir = metadata.platforms_dir
    _pio_metadata.default_envs = metadata.default_envs
    _pio_metadata.envs = metadata.envs
    _G.metadata.active_env = active_env
  end
end

--INFO:
-- 4. Initialization
-------------------------------------------------------------------------------
M.load_project_config()

return M
