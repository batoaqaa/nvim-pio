local M = {}

-- This is the public function that users or UI frameworks can query
function M.get_status_string()
  if not _G.metadata or not _G.metadata.active_env or _G.metadata.active_env == '' then
    return ''
  end
  -- Returns a clean component block: "   seeed_xiao_esp32c3"
  return string.format('   %s', _G.metadata.active_env)
end

return M
