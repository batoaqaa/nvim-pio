-- stylua: ignore start
local uv = vim.uv or vim.loop

-- 1. Gather all the data first
local sysname = uv.os_uname().sysname
local home = uv.os_homedir()
local is_win = (sysname:find('Windows') or vim.fn.has('win32') == 1 or vim.fn.has("win64") == 1)
local is_mac = sysname == 'Darwin'
local is_linux = sysname == 'Linux'

-- Safe Check for WSL
local is_wsl = false
if is_linux and vim.fn.filereadable('/proc/version') == 1 then
  local lines = vim.fn.readfile('/proc/version')
  local version = (lines and lines[1]) or ''
  if version:lower():find('microsoft') then is_wsl = true end
end
local projectDir = uv.cwd() or '.'
local xdg_config_home = vim.env.XDG_CONFIG_HOME or (
  is_win
    and (vim.env.LOCALAPPDATA or vim.fs.joinpath(home, 'AppData', 'Local'))
    or  vim.fs.joinpath(home, '.config')
)
local clangd_user_dir = vim.fs.joinpath(xdg_config_home, 'clangd')
local nvimpioConfigDir = vim.fs.joinpath(projectDir, '.nvimpio')
local pioConfigDir = vim.fs.joinpath(projectDir, '.pio')
---@class OS
---@field name "windows"|"macos"|"linux"
---@field app_name string
---@field debug string
---@field is_win boolean
---@field is_mac boolean
---@field is_linux boolean
---@field is_wsl boolean
---@field home string
---@field folder_sep string
---@field path_sep string
---@field devNul string
---@field eol string
---@field shell table
---@field config_dir string
---@field data_dir string
---@field cache_dir string
---@field bin_dir string
---@field project_dir string
---@field clangd_filter string
---@field nvimpio_env_dir string
---@field clangd_config string
---@field clangd_db string
---@field cc_flags string
---@field cxx_flags string
---@field project_config string
---@field clangd_user_file string
---@field clangd_user_dir string
---@field nvimpio_config_dir string
---@field pio_config_dir string
---@field notify fun(msg: string, level?: string|integer)
---@field preparePOSIXPathPattern fun(raw_path: string)
---@field prepareLuaEscapePattern fun(raw: string)
---@field pioReady fun(local_pio_executable: string): boolean

---@type OS
_G.OS = _G.OS or {}
local OS = _G.OS ---@cast OS +OS

local _pioReady = false

-- 2. Build the data table
local os_info = {
  name = is_win and 'windows' or (is_mac and 'macos' or 'linux'),
  app_name = 'nvim-pio',
  debug = 'info',  --off
  is_win = is_win,
  is_mac = is_mac,
  is_linux = is_linux,
  is_wsl = is_wsl,
  home = home,
  path_sep = is_win and ';' or ':',
  folder_sep = is_win and '\\' or '/',
  devNul = is_win and ' nul' or ' /dev/null',
  eol = is_win and '\r\n' or '\n',
  config_dir = vim.fn.stdpath('config'),
  data_dir = vim.fn.stdpath('data'),
  cache_dir = vim.fn.stdpath('cache'),
  bin_dir = is_win and "Scripts" or "bin",
  project_dir = vim.fs.normalize(projectDir),
  clangd_filter = '.clangdFilter.json',
  clangd_config = vim.fs.joinpath(nvimpioConfigDir, '.clangdConfig.json'),
  clangd_db = vim.fs.joinpath(nvimpioConfigDir, 'compile_commands.json'),
  clangd_user_dir = vim.fs.normalize(clangd_user_dir),
  clangd_user_file = vim.fs.joinpath(clangd_user_dir, "config.yaml"),
  cc_flags = '.clangdCCFlags.txt',
  cxx_flags = '.clangdCXXFlags.txt',
  project_config = vim.fs.joinpath(nvimpioConfigDir, '.projectConfig.json'),
  nvimpio_config_dir = vim.fs.normalize(nvimpioConfigDir),
  pio_config_dir = vim.fs.normalize(pioConfigDir),
  nvimpio_env_dir = '',
  shell = OS.is_win and {
    'pwsh.exe',
    '-NoExit',
    '-NoLogo',
    '-NoProfile',
    '-ExecutionPolicy', 'Bypass',
    '-Command', '[Console]::InputEncoding=[Console]::OutputEncoding=[System.Text.Encoding]::UTF8;'
  } or (function()
    local default_shell = vim.api.nvim_get_option_value('shell', {})
    if default_shell:find('zsh') then return { default_shell, '-f' } end
    return default_shell
  end)(),

  ---@param msg string The message to display
  ---@param level string|integer|nil
  notify = function(msg, level)
    -- vim.log = { levels = { TRACE = 0, DEBUG = 1, INFO = 2, WARN = 3, ERROR = 4, OFF = 5, }, }
    local string_to_level = {
      trace = vim.log.levels.TRACE,
      debug = vim.log.levels.DEBUG,
      info = vim.log.levels.INFO,
      warn = vim.log.levels.WARN,
      error = vim.log.levels.ERROR,
      off = vim.log.levels.OFF,
    }
    if type(level) == 'string' then level = string_to_level[level:lower()] end
    if level == vim.log.levels.OFF then return end

    ---@cast level integer
    level = level or vim.log.levels.INFO

    vim.schedule(function()
      vim.notify(msg, level, { title = 'nvim-pio', icon = ' ' })
    end)
  end,

  ---@param raw string
  ---@return string
  prepareLuaEscapePattern = function(raw)
    -- 1. Standardize to lowercase and use forward slashes for Windows safety
    local escaped_string = raw

    -- 2. List of all characters that Lua patterns treat as special magic wildcards
    local magic_chars = { "%", ".", "-", "+", "*", "?", "^", "$", "(", ")", "[", "]" }

    -- 3. Loop through and escape each magic character by prepending a '%'
    for _, char in ipairs(magic_chars) do
      -- Force gsub to find the literal character (e.g. "%." for dot)
      local search_pattern = "%" .. char

      -- "%%%" translates to a single literal '%' in the output string plus the character
      local replace_string = "%%%" .. char

      escaped_string = escaped_string:gsub(search_pattern, replace_string)
    end
    return escaped_string
  end,

  ---@param raw_path string
  ---@return string
  preparePOSIXPathPattern = function(raw_path)
      -- 1. Clean up slashes using Neovim's normalizer
      local path = vim.fs.normalize(raw_path)
      -- 2. Strip any trailing slash if it exists, so it fits your "%s/.*" template perfectly
      path = path:gsub("/$", "")
      -- 3.Captures ONLY the letter (%a), leaving the colon outside the brackets
      local drive_letter, main_path = path:match("^([a-zA-Z]):(.*)$")
      local drive
      if drive_letter then
        -- Wraps just the letters into [cC] and appends the colon outside
        drive = '[' .. drive_letter:lower() .. drive_letter:upper() .. ']:'
        path = main_path
      else drive = "" end -- Linux/macOS
      local finalPath = drive .. path
      -- 4. Escape every literal dot inside the folders completely dynamically
      finalPath = finalPath:gsub("%.", "[.]")
      -- 5. Recombine them seamlessly without a trailing slash
      return finalPath
  end,

  ---Checks if PlatformIO is installed and working (Cached after first success)
  ---@param local_pio_executable string
  ---@return boolean
  pioReady = function(local_pio_executable)
    _pioReady = false
    if vim.fn.executable(local_pio_executable) ~= 1 then _pioReady = false end
    local ok, obj = pcall(function() return vim.system({ local_pio_executable, '--version' }):wait() end)
    if ok and obj and (obj.code == 0)  and obj.stdout:match("PlatformIO") then _pioReady = true end
    return _pioReady
  end,
} ---@as OS

-- 3. Lock it down
setmetatable(OS, {
  __index = os_info,
  __newindex = function(_, key, value)
    if os_info[key] ~= nil then
      if os_info[key] == value then return end -- Performance check
      if key == 'nvimpio_env_dir' then
        os_info[key] = value
      end
    else
      error("Error: Cannot assign new property '" .. tostring(key) .. "' to protected OS registry.", 2)
    end
    -- error("Error: Table 'OS' is read-only. Cannot modify key: " .. tostring(key), 2)
  end,
  __metatable = false,
})

return OS
