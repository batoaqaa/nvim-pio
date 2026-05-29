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

-- ====================================================================
-- 3. THE HIGH-PERFORMANCE UPSTREAM LSP INTERCEPTOR (0 LINTER WARNINGS!)
-- ====================================================================
local original_diagnostic_handler = vim.lsp.handlers['textDocument/publishDiagnostics']

vim.lsp.handlers['textDocument/publishDiagnostics'] = function(err, result, ctx, config)
  -- Cast ctx cleanly so the language server knows it contains protocol definitions
  local target_ctx = ctx ---@as lsp.HandlerContext
  local client_id = target_ctx and target_ctx.client_id
  local client = client_id and vim.lsp.get_client_by_id(client_id)

  if not client or client.name ~= 'clangd' then
    return original_diagnostic_handler(err, result, ctx, config)
  end

  -- Clangd exclusive payload processing zone
  if not err and result and result.diagnostics then
    if M.clean_diagnostics_pipeline then
      result.diagnostics = M.clean_diagnostics_pipeline(result.diagnostics)
    end
  end

  -- Hand off the validated and stripped data array down to the UI renderer
  original_diagnostic_handler(err, result, ctx, config)
end

-- ====================================================================
-- 4. UNIVERSAL RECURSIVE INTERACTIVE SELECTION INTERFACE
-- ====================================================================
function M.manage_file_diagnostics_interactive()
  local current_buf = vim.api.nvim_get_current_buf()

  local function open_picker_loop()
    -- Query active namespaces to pull down the original raw background cache records
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

    -- Filter out options already stored in our active blocklist
    local unique_codes = {}
    local distinct_items = {}

    for _, diag in ipairs(raw_diagnostics) do
      local code_name = diag.code

      if code_name and code_name ~= '' then
        if not blocked_codes[code_name] and not unique_codes[code_name] then
          unique_codes[code_name] = true
          table.insert(distinct_items, {
            type = 'code',
            id = code_name,
            display = string.format('🔒 Block Code: [%s] (%s)', code_name, diag.message),
          })
        end
      else
        local word1, word2 = string.match(diag.message:lower(), '([%w%-]+)%s+([%w%-]+)')
        local key_phrase = (word1 and word2) and (word1 .. ' ' .. word2) or diag.message:lower()

        if not blocked_phrases[key_phrase] then
          table.insert(distinct_items, {
            type = 'phrase',
            id = key_phrase,
            display = string.format('📝 Block Phrase matching: "%s..."', key_phrase),
          })
        end
      end
    end

    -- Base Condition: Save and exit if no errors remain unblocked
    if #distinct_items == 0 then
      save_filter_database()
      vim.notify('✅ Complete Parity: All compile items have been successfully filtered!', vim.log.levels.INFO, { title = 'Compiler Mangler' })
      vim.cmd('edit!')
      return
    end

    table.sort(distinct_items, function(a, b)
      return a.display < b.display
    end)

    vim.ui.select(distinct_items, {
      prompt = 'Microcontroller Diagnostic Mangler (Esc to Save & Apply)',
      kind = 'nvimpio_mangler',
      format_item = function(item)
        return item.display
      end,
    }, function(choice)
      -- User pressed Esc to finish and save changes
      if not choice then
        save_filter_database()
        vim.notify('🔒 Filter Overrides Saved & Applied!', vim.log.levels.WARN, { title = 'Compiler Mangler' })
        vim.cmd('edit!')
        return
      end

      local added = false
      if choice.type == 'code' then
        if not blocked_codes[choice.id] then
          blocked_codes[choice.id] = true
          added = true
        end
      elseif choice.type == 'phrase' then
        if not blocked_phrases[choice.id] then
          blocked_phrases[choice.id] = true
          added = true
        end
      end

      if added then
        save_filter_database()

        -- Force an instant inline visual screen redraw
        local filtered = M.clean_diagnostics_pipeline(raw_diagnostics)
        for ns_id, _ in pairs(vim.diagnostic.get_namespaces()) do
          vim.diagnostic.set(ns_id, current_buf, filtered)
        end

        -- Call the next picker loop iteration on the next frame schedule tick
        vim.schedule(function()
          open_picker_loop()
        end)
      else
        open_picker_loop()
      end
    end)
  end

  open_picker_loop()
end

return M
