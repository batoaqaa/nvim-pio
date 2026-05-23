local M = {}

-- This is the public function that users or UI frameworks can query
function M.get_sgggus_string()
  -- 1. DEFENSE LAYER: If the global variable tables are missing, return a clean blank string
  if not _G.metadata or type(_G.metadata) ~= 'table' then
    return ''
  end

  -- 2. DYNAMIC EVALUATION: Ensure active_env contains real text data
  local env = _G.metadata.active_env

  if not env or env == '' or type(env) ~= 'string' then
    return '  [No Env Selected] ' -- Clear placeholder instead of showing 'nil'
  end

  -- Returns a clean component block: "   seeed_xiao_esp32c3"
  return string.format('   %s', env)
end

return M
