-- stylua: ignore start

-- 1. Gather all the data first
local sysname = vim.uv.os_uname().sysname
local is_win = (sysname:find('Windows') or vim.fn.has('win32') == 1)
local is_mac = sysname == 'Darwin'
local is_linux = sysname == 'Linux'
-- Check for WSL
local is_wsl = false
if is_linux then
  local version = vim.fn.readfile('/proc/version')[1] or ''
  if version:lower():find('microsoft') then is_wsl = true end
end

---@class OS
---@field name "windows"|"macos"|"linux"
---@field app_name string
---@field is_win boolean
---@field is_mac boolean
---@field is_linux boolean
---@field is_wsl boolean
---@field home string
---@field env_sep string
---@field path_sep string
---@field devNul string
---@field eol string
---@field shell string
---@field config_dir string
---@field data_dir string
---@field cache_dir string
---@field notify fun(msg: string, level?: string|integer)
---@field pioReady fun(): boolean

---@type OS
_G.OS = _G.OS or {}
local OS = _G.OS ---@cast OS +OS

local _pioRady = false

-- 2. Build the data table
local os_info = {
  name = is_win and 'windows' or (is_mac and 'macos' or 'linux'),
  app_name = 'nvim-pio',
  is_win = is_win,
  is_mac = is_mac,
  is_linux = is_linux,
  is_wsl = is_wsl,
  home = vim.uv.os_homedir(),
  env_sep = is_win and ';' or ':',
  path_sep = is_win and '\\' or '/',
  devNul = is_win and ' 2>./nul' or ' 2>/dev/null',
  eol = is_win and '\r\n' or '\n',
  shell = vim.env.SHELL or (is_win and 'powershell.exe' or 'sh'),
  config_dir = vim.fn.stdpath('config'),
  data_dir = vim.fn.stdpath('data'),
  cache_dir = vim.fn.stdpath('cache'),

  ---@param msg string The message to display
  ---@param level string|integer|nil
  notify = function(msg, level)
    local string_to_level = {
      info = vim.log.levels.INFO,
      warn = vim.log.levels.WARN,
      error = vim.log.levels.ERROR,
      debug = vim.log.levels.DEBUG,
    }
    if type(level) == 'string' then level = string_to_level[level:lower()] end

    ---@cast level integer
    level = level or vim.log.levels.INFO

    vim.notify(msg, level, { title = 'nvim-pio', icon = ' ' })
  end,

  ---Checks if PlatformIO is installed and working (Cached after first success)
  ---@return boolean
  pioReady = function()
    if _pioRady then return true end

    if vim.fn.executable('pio') ~= 1 then return false end

    local ok, obj = pcall(function() return vim.system({ 'pio', '--version' }):wait() end)

    if ok and obj and obj.code == 0 then
      _pioRady = true
      return true
    end
    return false
  end,
} ---@as OS

-- 3. Lock it down
-- _G.OS = {} ---@as OS
setmetatable(OS, {
  __index = os_info,
  __newindex = function(_, key)
    error("Error: Table 'OS' is read-only. Cannot modify key: " .. tostring(key), 2)
  end,
  __metatable = false,
})
