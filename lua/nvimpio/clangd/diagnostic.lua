local M = {}

-- ====================================================================
-- 0. CONFIGURATION & STATE MANIFEST PATHS
-- ====================================================================
local root_markers = { 'platformio.ini', '.git', '.clangd' }
local initial_buf = vim.api.nvim_get_current_buf()
local initial_file = vim.api.nvim_buf_get_name(initial_buf)
local project_root = vim.fs.root(initial_file, root_markers) or vim.uv.cwd()

-- Target location for persistent memory states
local json_database_file = project_root .. '/.filter.json'

-- High-speed hot-memory tracking sets
M.blocked_codes = {}
M.removed_flags = {}

-- ====================================================================
-- 1. PERSISTENT DISK STORAGE SYNC TO BOILER.LUA
-- ====================================================================
local function load_filter_database()
  M.blocked_codes = {}
  M.removed_flags = {}

  local f = io.open(json_database_file, 'rb')
  if not f then
    return
  end
  local raw_json = f:read('*all')
  f:close()

  if raw_json and raw_json ~= '' then
    local success, data = pcall(vim.json.decode, raw_json)
    if success and data and type(data) == 'table' then
      M.blocked_codes = data.codes or {}
      M.removed_flags = data.flags or {}
    end
  end

  if not M.blocked_codes then
    M.blocked_codes = {}
  end
  if not M.removed_flags then
    M.removed_flags = {}
  end
end

local function save_filter_database()
  local f = io.open(json_database_file, 'wb')
  if f then
    local payload = { codes = M.blocked_codes, flags = M.removed_flags }
    local pretty = require('nvimpio.utils.misc').jsonFormat(payload)
    f:write(pretty)
    f:close()
  end

  local boiler = require('nvimpio.boilerplate')

  boiler.remove = {}
  for flag, _ in pairs(M.removed_flags or {}) do
    table.insert(boiler.remove, flag)
  end
  table.sort(boiler.remove)

  boiler.suppress = {}
  for code, _ in pairs(M.blocked_codes or {}) do
    table.insert(boiler.suppress, code)
  end
  table.sort(boiler.suppress)

  local boilerplate_gen = boiler.boilerplate_gen
  if boilerplate_gen then
    pcall(boilerplate_gen, '.clangd', vim.g.platformioRootDir)
  end
end

-- Initialize database tables into hot memory right on file load pass
load_filter_database()

-- ====================================================================
-- 2. UNIFIED COMPILER MANGLER DASHBOARD (BLOCK / UNBLOCK / RESET)
-- ====================================================================
function M.manage_file_diagnostics_interactive()
  local function open_dashboard_loop()
    local current_buf = vim.api.nvim_get_current_buf()
    local dashboard_items = {}

    -- SECTION A: MASTER RESET OPTION
    local has_active_filters = false
    for _, _ in pairs(M.blocked_codes) do
      has_active_filters = true
      break
    end
    if not has_active_filters then
      for _, _ in pairs(M.removed_flags) do
        has_active_filters = true
        break
      end
    end

    if has_active_filters then
      table.insert(dashboard_items, {
        action = 'reset',
        display = '💥 Unblock all',
      })
    end

    -- SECTION B: LIVE ACTIVE COMPILER DIAGNOSTICS (THE BLOCK ZONE)
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
      local code_name = diag.code or ''
      local msg = diag.message or ''

      -- 1. Safely evaluate boolean state conditions first without changing types
      local is_driver_error = false
      if type(code_name) == 'string' and code_name:find('drv_unknown') then
        is_driver_error = true
      end

      -- 2. Extract string values safely using dedicated regex capturing groups
      -- local unknown_arg = msg:match('argument%s*[\'"]?(%-[%w%-]+)[\'"]?')
      -- or msg:match('option%s*[\'"]?(%-[%w%-]+)[\'"]?')
      -- or msg:match('mean%s*[\'"]?(%-[%w%-]+)[\'"]?')
      local unknown_arg = msg:match('argument%s*[\'"]?(%-.-)[\'"]?%s*')
        or msg:match('option%s*[\'"]?(%-.-)[\'"]?%s*')
        or msg:match('mean%s*[\'"]?(%-.-)[\'"]?%??$')

      -- Fallback route: if it is a driver flag error but text regex missed, fall back safely
      if is_driver_error and not unknown_arg then
        -- unknown_arg = msg:match("'([%w%-]+)'") or msg:match("'(%-[%w%-]+)'") or '-mlongcalls'
        unknown_arg = msg:match("'(%-.-)'") or '-mlongcalls'
      end

      -- 3. Run string sanitization steps ONLY if unknown_arg is guaranteed to be a valid string
      if unknown_arg and type(unknown_arg) == 'string' then
        unknown_arg = unknown_arg:gsub('[\'"%?]', ''):gsub('%s+$', '')
        if not M.removed_flags[unknown_arg] and not unique_active_entries[unknown_arg] then
          unique_active_entries[unknown_arg] = true
          table.insert(block_options, {
            action = 'block_flag',
            id = unknown_arg,
            display = string.format('🔨 Remove compiler flag: [%s]', unknown_arg),
          })
        end
      elseif code_name ~= '' then
        if not M.blocked_codes[code_name] and not unique_active_entries[code_name] then
          unique_active_entries[code_name] = true
          table.insert(block_options, {
            action = 'block_code',
            id = code_name,
            display = string.format('🔒 Suppress Code: [%s] (%s)', code_name, msg),
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

    -- SECTION C: CURRENTLY SUPPRESSED ITEMS (THE UNBLOCK ZONE)
    local unblock_options = {}

    for flag, _ in pairs(M.removed_flags) do
      table.insert(unblock_options, {
        action = 'unblock_flag',
        id = flag,
        display = string.format('🔓 RESTORE Compiler Flag: [%s]', flag),
      })
    end

    for code, _ in pairs(M.blocked_codes) do
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

    if #dashboard_items == 0 then
      vim.notify('✅ Complete Parity: No outstanding compilation exceptions found.', vim.log.levels.INFO, { title = 'Compiler Mangler' })
      return
    end

    local lspRestart = require('nvimpio.clangd.control').restart
    vim.ui.select(dashboard_items, {
      prompt = 'Unified Native .clangd Template Controller Dashboard',
      kind = 'nvimpio_clangd_mangler',
      format_item = function(item)
        return item.display
      end,
    }, function(choice)
      -- 🌟 Escape/Cancel Route: User hits Esc to apply changes
      if not choice then
        save_filter_database()
        lspRestart()
        -- force a complete buffer reload to destroy clangd's in-memory cache.
        -- vim.defer_fn(function()
        --   if vim.api.nvim_buf_is_valid(current_buf) then
        --     vim.cmd('checktime') -- Synch file modifications with the file system safely
        --     vim.cmd('edit!') -- Forces a hard buffer refresh, clearing old errors instantly
        --   end
        -- end, 100)
        return
      end

      if choice.action == 'reset' then
        M.blocked_codes = {}
        M.removed_flags = {}
        save_filter_database()
        vim.notify('💥 Data wiped clean. Reverting back to original static settings.', vim.log.levels.ERROR, { title = 'Compiler Mangler' })
        lspRestart()

        -- vim.defer_fn(function()
        --   if vim.api.nvim_buf_is_valid(current_buf) then
        --     vim.cmd('checktime')
        --     vim.cmd('edit!')
        --   end
        -- end, 100)
        return
      elseif choice.action == 'block_flag' then
        M.removed_flags[choice.id] = true
      elseif choice.action == 'block_code' then
        M.blocked_codes[choice.id] = true
      elseif choice.action == 'unblock_flag' then
        M.removed_flags[choice.id] = nil
      elseif choice.action == 'unblock_code' then
        M.blocked_codes[choice.id] = nil
      end

      save_filter_database()

      vim.schedule(function()
        open_dashboard_loop()
      end)
    end)
    -- local lspRestart = require('nvimpio.clangd.control').restart
    -- vim.ui.select(dashboard_items, {
    --   prompt = 'Unified Native .clangd Template Controller Dashboard',
    --   kind = 'nvimpio_clangd_mangler',
    --   format_item = function(item)
    --     return item.display
    --   end,
    -- }, function(choice)
    --   if not choice then
    --     save_filter_database()
    --     lspRestart()
    --     return
    --   end
    --
    --   if choice.action == 'reset' then
    --     M.blocked_codes = {}
    --     M.removed_flags = {}
    --     save_filter_database()
    --     vim.notify('💥 Data wiped clean. Reverting back to original static settings.', vim.log.levels.ERROR, { title = 'Compiler Mangler' })
    --     lspRestart()
    --     return
    --   elseif choice.action == 'block_flag' then
    --     M.removed_flags[choice.id] = true
    --   elseif choice.action == 'block_code' then
    --     M.blocked_codes[choice.id] = true
    --   elseif choice.action == 'unblock_flag' then
    --     M.removed_flags[choice.id] = nil
    --   elseif choice.action == 'unblock_code' then
    --     M.blocked_codes[choice.id] = nil
    --   end
    --
    --   save_filter_database()
    --
    --   vim.schedule(function()
    --     open_dashboard_loop()
    --   end)
    -- end)
  end

  open_dashboard_loop()
end

return M
