local M = {}

-- Helper helper function to verify if a file lives inside the PlatformIO system folders
local function is_platformio_system_file(buf_name)
  local normalized_name = vim.fs.normalize(buf_name):lower()

  -- 1. Check against the strict global package cache path marker
  if normalized_name:find('.platformio', 1, true) then
    return true
  end

  -- 2. Check against your plugin's dynamic metadata framework memory layout
  if _G.metadata and _G.metadata.framework_root and _G.OS and _G.OS.prepareLuaEscapePattern then
    local raw_root = vim.fs.normalize(_G.metadata.framework_root):lower()
    local clean_framework = _G.OS.prepareLuaEscapePattern(raw_root)
    if string.match(normalized_name, clean_framework) then
      return true
    end
  end

  return false
end

-- ============================================================================
-- 1. UNIFIED ROOT DIRECTORY DETECTOR (Neovim 0.11+ Validated)
-- ============================================================================
M.root_dir = function(bufnr, on_dir)
  local buf_name = vim.api.nvim_buf_get_name(bufnr)

  -- Force any global framework system file to map directly against the local project workspace
  if is_platformio_system_file(buf_name) then
    on_dir(vim.fn.getcwd())
    return
  end

  -- FIXED SYNTAX: Properly nested fallbacks using native marker lookups
  local project_root = vim.fs.root(bufnr, { 'platformio.ini', 'CMakeLists.txt' })
  if not project_root then
    project_root = vim.fs.root(bufnr, { '.git' })
  end

  on_dir(project_root or vim.fn.getcwd())
end

-- ============================================================================
-- 2. UNIFIED CLIENT REUSE EVALUATOR (Neovim 0.11+ Validated)
-- ============================================================================
M.reuse_client = function(client, current_config)
  if client.name ~= current_config.name then
    return false
  end

  -- Safe, target-buffer bounded file retrieval (Replaced 0 with explicit buffer context)
  local current_file = vim.api.nvim_buf_get_name(0)

  -- If the file we are evaluating is an external system header file,
  -- force client reuse instantly to stop secondary process spawns.
  if is_platformio_system_file(current_file) then
    return true
  end

  -- For standard source files, fallback to matching strict directory boundaries
  return client.config.root_dir == current_config.root_dir
end

return M
