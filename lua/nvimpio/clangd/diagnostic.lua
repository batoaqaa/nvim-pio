local M = {}

-- ====================================================================
-- 0. CONFIGURATION & STATE MANIFEST PATHS
-- ====================================================================
local root_markers = { 'platformio.ini', '.git', '.clangd' }
local initial_buf = vim.api.nvim_get_current_buf()
local initial_file = vim.api.nvim_buf_get_name(initial_buf)
local project_root = vim.fs.root(initial_file, root_markers) or vim.uv.cwd()

-- Target the native .clangd system configuration file directly
local clangd_config_file = project_root .. '/.clangd'

-- High-speed unified memory tracking states
local blocked_codes = {}
local removed_flags = {}

-- ====================================================================
-- 1. STABLE NATIVE .CLANGD YAML PARSER LOOPS
-- ====================================================================
local function load_clangd_config()
  blocked_codes = {}
  removed_flags = {}

  local f = io.open(clangd_config_file, 'r')
  if not f then
    return
  end

  local current_section = nil
  for line in f:lines() do
    -- Trim whitespace
    local clean_line = line:gsub('^%s+', ''):gsub('%s+$', '')

    -- Identify state boundary changes
    if clean_line:find('^CompileFlags:') then
      current_section = 'flags'
    elseif clean_line:find('^Diagnostics:') then
      current_section = 'diagnostics'
    elseif clean_line:find('^%-%s+') then
      -- Parse exact sequence item elements
      local item = clean_line:gsub('^%-%s+', ''):gsub('^[\'"]', ''):gsub('[\'"]$', '')
      if current_section == 'flags' and item ~= '' then
        removed_flags[item] = true
      elseif current_section == 'diagnostics' and item ~= '' then
        blocked_codes[item] = true
      end
    end
  end
  f:close()
end

local function save_clangd_config()
  local lines = {}

  -- 1. Construct the native compiler flag mutation block
  table.insert(lines, 'CompileFlags:')
  table.insert(lines, '  Remove:')
  local flag_list = {}
  for flag, _ in pairs(removed_flags) do
    table.insert(flag_list, flag)
  end
  table.sort(flag_list)
  for _, flag in ipairs(flag_list) do
    table.insert(lines, string.format('    - %s', flag))
  end

  -- 2. Construct the native engine diagnostic suppression block
  table.insert(lines, 'Diagnostics:')
  table.insert(lines, '  Suppress:')
  local code_list = {}
  for code, _ in pairs(blocked_codes) do
    table.insert(code_list, code)
  end
  table.sort(code_list)
  for _, code in ipairs(code_list) do
    table.insert(lines, string.format('    - %s', code))
  end

  local f = io.open(clangd_config_file, 'w')
  if f then
    f:write(table.concat(lines, '\n') .. '\n')
    f:close()
  end
end

-- Initialize the parser cache state immediately on script loading lifecycle
load_clangd_config()

-- ====================================================================
-- 2. UNIFIED COMPILER MANGLER DASHBOARD (BLOCK / UNBLOCK / RESET)
-- ====================================================================
function M.manage_file_diagnostics_interactive()
  local function open_dashboard_loop()
    local current_buf = vim.api.nvim_get_current_buf()
    local dashboard_items = {}

    -- ----------------------------------------------------------------
    -- SECTION A: MASTER RESET OPTION
    -- ----------------------------------------------------------------
    local has_active_filters = false
    for _, _ in pairs(blocked_codes) do
      has_active_filters = true
      break
    end
    if not has_active_filters then
      for _, _ in pairs(removed_flags) do
        has_active_filters = true
        break
      end
    end

    if has_active_filters then
      table.insert(dashboard_items, {
        action = 'reset',
        display = '💥 WIPE ENTIRE .CLANGD CONFIGURATION (RESET ALL)',
      })
    end

    -- ----------------------------------------------------------------
    -- SECTION B: LIVE ACTIVE COMPILER DIAGNOSTICS (THE BLOCK ZONE)
    -- ----------------------------------------------------------------
    -- Fetch raw backend diagnostics array natively
    local raw_diagnostics = {}
    for ns_id, ns_meta in pairs(vim.diagnostic.get_namespaces()) do
      if ns_meta.name and ns_meta.name:find('clangd') then
        raw_diagnostics = vim.diagnostic.get(current_buf, { namespace = ns_id })
        break
      end
    end
    if #raw_diagnostics == 0 then
      raw_diagnostics = vim.diagnostic.get(current_buf)
    end

    local unique_active_entries = {}
    local block_options = {}

    for _, diag in ipairs(raw_diagnostics) do
      local code_name = diag.code
      local msg = diag.message or ''

      -- Look for unknown argument compiler driver flags explicitly
      local unknown_arg = msg:match("Unknown argument:%s*'([^']+)'") or msg:match("unknown argument:%s*'([^']+)'")

      if unknown_arg then
        if not removed_flags[unknown_arg] and not unique_active_entries[unknown_arg] then
          unique_active_entries[unknown_arg] = true
          table.insert(block_options, {
            action = 'block_flag',
            id = unknown_arg,
            display = string.format('🔨 Remove Flag from Compiler: [%s]', unknown_arg),
          })
        end
      elseif code_name and code_name ~= '' then
        if not blocked_codes[code_name] and not unique_active_entries[code_name] then
          unique_active_entries[code_name] = true
          table.insert(block_options, {
            action = 'block_code',
            id = code_name,
            display = string.format('🔒 Suppress Code via .clangd: [%s] (%s)', code_name, msg),
          })
        end
      end
    end

    table.sort(block_options, function(a, b)
      return a.display < b.display
    end)
    for _, opt in ipairs(block_options) do
      table.insert(dashboard_items, opt)
    end

    -- ----------------------------------------------------------------
    -- SECTION C: PERSISTENT OVERRIDES CURRENTLY SAVED (THE UNBLOCK ZONE)
    -- ----------------------------------------------------------------
    local unblock_options = {}

    for flag, _ in pairs(removed_flags) do
      table.insert(unblock_options, {
        action = 'unblock_flag',
        id = flag,
        display = string.format('🔓 RESTORE Compiler Flag: [%s]', flag),
      })
    end

    for code, _ in pairs(blocked_codes) do
      table.insert(unblock_options, {
        action = 'unblock_code',
        id = code,
        display = string.format('🔓 ACTIVATE Diagnostic Code: [%s]', code),
      })
    end

    table.sort(unblock_options, function(a, b)
      return a.display < b.display
    end)
    for _, opt in ipairs(unblock_options) do
      table.insert(dashboard_items, opt)
    end

    -- ----------------------------------------------------------------
    -- SECTION D: VIEW RENDERING & SELECTION DISPATCH
    -- ----------------------------------------------------------------
    if #dashboard_items == 0 then
      vim.notify('✅ Complete Parity: No outstanding anomalies found.', vim.log.levels.INFO, { title = 'Compiler Mangler' })
      return
    end

    vim.ui.select(dashboard_items, {
      prompt = 'Unified Native .clangd Controller Dashboard',
      kind = 'nvimpio_clangd_mangler',
      format_item = function(item)
        return item.display
      end,
    }, function(choice)
      if not choice then
        save_clangd_config()
        -- 🚀 LSP RESTART TRIGGER: Force clangd to index the updated file changes instantly
        vim.cmd('LspRestart clangd')
        return
      end

      if choice.action == 'reset' then
        blocked_codes = {}
        removed_flags = {}
        save_clangd_config()
        vim.notify('💥 Configuration file dropped.', vim.log.levels.ERROR, { title = 'Compiler Mangler' })
        vim.cmd('LspRestart clangd')
        return
      elseif choice.action == 'block_flag' then
        removed_flags[choice.id] = true
      elseif choice.action == 'block_code' then
        blocked_codes[choice.id] = true
      elseif choice.action == 'unblock_flag' then
        removed_flags[choice.id] = nil
      elseif choice.action == 'unblock_code' then
        blocked_codes[choice.id] = nil
      end

      save_clangd_config()

      -- Cycle back dynamically with a quick schedule call
      vim.schedule(function()
        open_dashboard_loop()
      end)
    end)
  end

  open_dashboard_loop()
end

return M
