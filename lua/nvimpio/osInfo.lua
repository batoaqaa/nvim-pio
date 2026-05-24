-- stylua: ignore start

-- 1. Gather all the data first
local sysname = vim.uv.os_uname().sysname
local is_win = (sysname:find('Windows') or vim.fn.has('win32') == 1 or vim.fn.has("win64") == 1)
local is_mac = sysname == 'Darwin'
local is_linux = sysname == 'Linux'
-- Check for WSL
-- Safe Check for WSL
local is_wsl = false
if is_linux and vim.fn.filereadable('/proc/version') == 1 then
  local lines = vim.fn.readfile('/proc/version')
  local version = (lines and lines[1]) or ''
  if version:lower():find('microsoft') then is_wsl = true end
end
local  winHome = os.getenv("USERPROFILE") or "C:\\"
local  nixHome = vim.uv.os_homedir() or "/root"
local  defaultHome = is_win and winHome or nixHome

---@class OS
---@field name "windows"|"macos"|"linux"
---@field app_name string
---@field is_win boolean
---@field is_mac boolean
---@field is_linux boolean
---@field is_wsl boolean
---@field home string
---@field winHome string
---@field nixHome string
---@field defaultHome string
---@field folder_sep string
---@field path_sep string
---@field devNul string
---@field eol string
---@field shell string
---@field config_dir string
---@field data_dir string
---@field cache_dir string
---@field bin_dir string
---@field platformio_dir string
---@field notify fun(msg: string, level?: string|integer)
---@field pioReady fun(): boolean

---@type OS
_G.OS = _G.OS or {}
local OS = _G.OS ---@cast OS +OS

local _pioReady = false

-- 2. Build the data table
local os_info = {
  name = is_win and 'windows' or (is_mac and 'macos' or 'linux'),
  app_name = 'nvim-pio',
  is_win = is_win,
  is_mac = is_mac,
  is_linux = is_linux,
  is_wsl = is_wsl,
  winHome = winHome,
  nixHome = nixHome,
  defaultHome = defaultHome,
  path_sep = is_win and ';' or ':',
  folder_sep = is_win and '\\' or '/',
  devNul = is_win and ' 2>./nul' or ' 2>/dev/null',
  eol = is_win and '\r\n' or '\n',
  shell = vim.env.SHELL or (is_win and 'powershell.exe' or 'sh'),
  config_dir = vim.fn.stdpath('config'),
  data_dir = vim.fn.stdpath('data'),
  cache_dir = vim.fn.stdpath('cache'),
  bin_dir = is_win and "Scripts" or "bin",
  platformio_dir = vim.fs.joinpath( vim.uv.os_homedir(), ".platformio"),

  ---@param msg string The message to display
  ---@param level string|integer|nil
  notify = function(msg, level)

    -- vim.log = { levels = { TRACE = 0, DEBUG = 1, INFO = 2, WARN = 3, ERROR = 4, OFF = 5, }, }

    local string_to_level = {
      info = vim.log.levels.INFO,
      warn = vim.log.levels.WARN,
      error = vim.log.levels.ERROR,
      debug = vim.log.levels.DEBUG,
    }
    if type(level) == 'string' then level = string_to_level[level:lower()] end

    ---@cast level integer
    level = level or vim.log.levels.INFO

    vim.schedule(function()
      vim.notify(msg, level, { title = 'nvim-pio', icon = ' ' })
    end)
  end,

  ---Checks if PlatformIO is installed and working (Cached after first success)
  ---@return boolean
  pioReady = function()
    if _pioReady then return true end

    -- local local_pio_executable = target_bin .. OS.folder_sep .. (OS.is_win and 'pio.exe' or 'pio')
    if vim.fn.executable('pio') ~= 1 then return false end

    local ok, obj = pcall(function() return vim.system({ 'pio', '--version' }):wait() end)

    if ok and obj and obj.code == 0 then
      _pioReady = true
      return true
    end
    return false
  end,
} ---@as OS

-- 3. Lock it down
setmetatable(OS, {
  __index = os_info,
  __newindex = function(_, key)
    error("Error: Table 'OS' is read-only. Cannot modify key: " .. tostring(key), 2)
  end,
  __metatable = false,
})
