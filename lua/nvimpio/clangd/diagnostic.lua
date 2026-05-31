local M = {}

-- ====================================================================
-- 0. CONFIGURATION & STATE MANIFEST PATHS
-- ====================================================================
local root_markers = { 'platformio.ini', '.git', '.clangd' }
local initial_buf = vim.api.nvim_get_current_buf()
local initial_file = vim.api.nvim_buf_get_name(initial_buf)
local project_root = vim.fs.root(initial_file, root_markers) or vim.uv.cwd()

-- Isolated project JSON state database location
local database_file = project_root .. '/.nvimpio_filters.json'

-- High-speed memory tracking dictionaries
local blocked_codes = {}
local blocked_phrases = {}

-- ====================================================================
-- 1. DATABASE DESERIALIZATION LOOPS (READ / WRITE)
-- ====================================================================
local function load_filter_database()
  local f = io.open(database_file, 'rb')
  if not f then
    return
  end
  local raw_json = f:read('*all')
  f:close()

  if raw_json and raw_json ~= '' then
    local success, data = pcall(vim.json.decode, raw_json)
    if success and data then
      blocked_codes = data.codes or {}
      blocked_phrases = data.phrases or {}
    end
  end
end

local function save_filter_database()
  local f = io.open(database_file, 'wb')
  if f then
    local payload = { codes = blocked_codes, phrases = blocked_phrases }
    local pretty = require('nvimpio.utils.misc').jsonFormat(payload)
    f:write(pretty)
    f:close()
  end
end

-- Pre-load active database profiles directly into hot memory tracking states
load_filter_database()

-- ====================================================================
-- 2. UNIVERSAL IN-MEMORY SUPPRESSION FILTER PIPELINE
-- ====================================================================
function M.clean_diagnostics_pipeline(diagnostics)
  if not diagnostics or #diagnostics == 0 then
    return {}
  end
  local cleaned = {}
  for _, diag in ipairs(diagnostics) do
    local code = diag.code or ''
    local msg = (diag.message or ''):lower()

    local matches_text_pattern = false
    for saved_phrase, _ in pairs(blocked_phrases) do
      if string.find(msg, saved_phrase:lower(), 1, true) then
        matches_text_pattern = true
        break
      end
    end

    if not (blocked_codes[code] or matches_text_pattern) then
      table.insert(cleaned, diag)
    end
  end
  return cleaned
end

-- this function is done on clangd config setup in lua/nvimpio/control/getClangdConfig()
-- ====================================================================
-- 3. THE HIGH-PERFORMANCE UPSTREAM LSP INTERCEPTOR (0 LINTER WARNINGS!)
-- ====================================================================
-- local original_diagnostic_handler = vim.lsp.handlers['textDocument/publishDiagnostics']
--
-- vim.lsp.handlers['textDocument/publishDiagnostics'] = function(err, result, ctx, config)
--   local target_ctx = ctx ---@as lsp.HandlerContext
--   local client_id = target_ctx and target_ctx.client_id
--   local client = client_id and vim.lsp.get_client_by_id(client_id)
--
--   if not client or client.name ~= 'clangd' then
--     return original_diagnostic_handler(err, result, ctx, config)
--   end
--
--   if not err and result and result.diagnostics then
--     if M.clean_diagnostics_pipeline then
--       result.diagnostics = M.clean_diagnostics_pipeline(result.diagnostics)
--     end
--   end
--
--   original_diagnostic_handler(err, result, ctx, config)
-- end

-- ====================================================================
-- 4. UNIFIED COMPILER MANGLER DASHBOARD (BLOCK / UNBLOCK / RESET)
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
      for _, _ in pairs(blocked_phrases) do
        has_active_filters = true
        break
      end
    end

    if has_active_filters then
      table.insert(dashboard_items, {
        action = 'reset',
        display = '💥 WIPE ALL BLOCKED OVERRIDES (RESET DATABASE CLEAN)',
      })
    end

    -- ----------------------------------------------------------------
    -- SECTION B: LIVE ACTIVE COMPILER DIAGNOSTICS (THE BLOCK ZONE)
    -- ----------------------------------------------------------------
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

    local unique_active_codes = {}
    local block_options = {}

    for _, diag in ipairs(raw_diagnostics) do
      local code_name = diag.code

      if code_name and code_name ~= '' then
        if not blocked_codes[code_name] and not unique_active_codes[code_name] then
          unique_active_codes[code_name] = true
          table.insert(block_options, {
            action = 'block_code',
            id = code_name,
            display = string.format('🔒 Block Code: [%s] (%s)', code_name, diag.message),
          })
        end
      else
        local word1, word2 = string.match(diag.message:lower(), '([%w%-]+)%s+([%w%-]+)')
        local key_phrase = (word1 and word2) and (word1 .. ' ' .. word2) or diag.message:lower()

        if not blocked_phrases[key_phrase] then
          table.insert(block_options, {
            action = 'block_phrase',
            id = key_phrase,
            display = string.format('📝 Block Phrase matching: "%s..."', key_phrase),
          })
        end
      end
    end

    -- Sort the unblocked errors alphabetically and merge them into items
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

    for code, _ in pairs(blocked_codes) do
      table.insert(unblock_options, {
        action = 'unblock_code',
        id = code,
        display = string.format('🔓 UNBLOCK Code: [%s]', code),
      })
    end

    for phrase, _ in pairs(blocked_phrases) do
      table.insert(unblock_options, {
        action = 'unblock_phrase',
        id = phrase,
        display = string.format('✏️  UNBLOCK Phrase: "%s..."', phrase),
      })
    end

    -- Sort the active blocked filters alphabetically and merge them at the bottom
    table.sort(unblock_options, function(a, b)
      return a.display < b.display
    end)
    for _, opt in ipairs(unblock_options) do
      table.insert(dashboard_items, opt)
    end

    -- ----------------------------------------------------------------
    -- SECTION D: ESCAPE CONDITIONS & VIEW RENDERING
    -- ----------------------------------------------------------------
    if #dashboard_items == 0 then
      vim.notify('✅ Complete Parity: No active exceptions or active overrides detected.', vim.log.levels.INFO, { title = 'Compiler Mangler' })
      vim.cmd('edit!')
      return
    end

    vim.ui.select(dashboard_items, {
      prompt = 'Compiler Mangler Control Panel (Esc to Save & Close)',
      kind = 'nvimpio_unified_dashboard',
      format_item = function(item)
        return item.display
      end,
    }, function(choice)
      -- User pressed Esc: Save everything to file and run a clean file reload
      if not choice then
        save_filter_database()
        vim.notify('🔒 Overrides Saved & Applied!', vim.log.levels.WARN, { title = 'Compiler Mangler' })
        vim.cmd('edit!')
        return
      end

      -- Process Selected Dashboard Command node
      if choice.action == 'reset' then
        blocked_codes = {}
        blocked_phrases = {}
        save_filter_database()
        vim.notify('💥 Blocklist database wiped completely clean!', vim.log.levels.ERROR, { title = 'Compiler Mangler' })
        vim.cmd('edit!')
        return
      elseif choice.action == 'block_code' then
        blocked_codes[choice.id] = true
      elseif choice.action == 'block_phrase' then
        blocked_phrases[choice.id] = true
      elseif choice.action == 'unblock_code' then
        blocked_codes[choice.id] = nil
      elseif choice.action == 'unblock_phrase' then
        blocked_phrases[choice.id] = nil
      end

      -- Save updates immediately into the JSON schema file
      save_filter_database()

      -- Instantly update screen diagnostics in hot-memory for visual feedback
      local filtered = M.clean_diagnostics_pipeline(raw_diagnostics)
      for ns_id, _ in pairs(vim.diagnostic.get_namespaces()) do
        vim.diagnostic.set(ns_id, current_buf, filtered)
      end

      -- Re-open the loop smoothly on the next frame refresh tick
      vim.schedule(function()
        open_dashboard_loop()
      end)
    end)
  end

  open_dashboard_loop()
end

return M
