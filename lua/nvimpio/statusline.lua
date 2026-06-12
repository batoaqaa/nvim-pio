local M = {}

-- This is the public function that users or UI frameworks can query
function M.get_status_string()
  if not _G.metadata or not _G.metadata.active_env or _G.metadata.active_env == '' then
    return ''
  end
  -- Returns a clean component block: "   seeed_xiao_esp32c3"
  return string.format('   %s', _G.metadata.active_env)
end

-- 1. Create a safe global helper function in Neovim's global namespace
_G.get_nvimpio_status = function()
  -- Safely check if the module exists without crashing Neovim
  local ok, statusline = pcall(require, 'nvimpio.statusline')

  -- If it exists and the function is valid, return the status text
  if ok and statusline and type(statusline.get_status_string) == 'function' then
    return statusline.get_status_string()
  end

  -- Return a completely empty string silently if the plugin is not yet loaded by lazy.nvim
  return ''
end

return M
