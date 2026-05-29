local M = {}

-- ====================================================================
-- 0. CONFIGURATION & STATE MANIFEST PATHS
-- ====================================================================
local root_markers = { 'platformio.ini', '.git', '.clangd' }
local initial_buf = vim.api.nvim_get_current_buf()
local initial_file = vim.api.nvim_buf_get_name(initial_buf)
local project_root = vim.fs.root(initial_file, root_markers) or vim.uv.cwd()

local database_file = project_root .. '/.nvimpio_filters.json'
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
      -- Strips out blocked compiler noise from the payload stream permanently
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

  -- Define the core loop block locally so it can re-trigger itself
  local function open_picker_loop()
    local diagnostics = vim.diagnostic.get(current_buf)

    -- Base Escape Condition: Exit cleanly if no errors remain
    if #diagnostics == 0 then
      vim.notify('✅ Complete Parity: No active workspace exceptions detected!', vim.log.levels.INFO)
      -- Sync file modifications to the disk background workspace state once finished
      vim.cmd('edit!')
      return
    end

    -- 1. Deduplicate remaining codes and phrases dynamically
    local unique_codes = {}
    local distinct_items = {}

    for _, diag in ipairs(diagnostics) do
      local code_name = diag.code

      if code_name and code_name ~= '' then
        if not unique_codes[code_name] then
          unique_codes[code_name] = true
          table.insert(distinct_items, {
            type = 'code',
            id = code_name,
            display = string.format('🔒 Block Code: [%s] (%s)', code_name, diag.message),
          })
        end
      else
        -- Fallback to key-phrase calculation for uncategorized noise
        local word1, word2 = string.match(diag.message:lower(), '([%w%-]+)%s+([%w%-]+)')
        local key_phrase = (word1 and word2) and (word1 .. ' ' .. word2) or diag.message:lower()

        table.insert(distinct_items, {
          type = 'phrase',
          id = key_phrase,
          display = string.format('📝 Block Phrase matching: "%s..."', key_phrase),
        })
      end
    end

    -- Sort choices alphabetically for easier scanning
    table.sort(distinct_items, function(a, b)
      return a.display < b.display
    end)

    -- 2. Execute via Neovim's universal selector protocol
    vim.ui.select(distinct_items, {
      prompt = 'Microcontroller Diagnostic Mangler (Esc to Save & Apply)',
      kind = 'nvimpio_mangler',
      format_item = function(item)
        return item.display
      end,
    }, function(choice)
      -- 🌟 Escape/Cancel Route: User is done picking items!
      if not choice then
        save_filter_database()
        vim.notify('🔒 Filter Overrides Saved & Applied!', vim.log.levels.WARN, { title = 'Compiler Mangler' })

        -- Force a complete clean background buffer reload to apply the final updates
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
        -- 🚀 FORCE AN INSTANT SCREEN RE-RENDER WITHOUT CLOSING THE PICKER CONTEXT
        -- Instead of calling a slow async disk reload, we immediately pull
        -- the current diagnostics list and push it back through our pipeline manually.
        local filtered = M.clean_diagnostics_pipeline(diagnostics)

        -- Find the active workspace client namespaces and override layout visibility
        for ns_id, _ in pairs(vim.diagnostic.get_namespaces()) do
          vim.diagnostic.set(ns_id, current_buf, filtered)
        end

        -- Wait exactly 1 frame step for the UI to update, then cycle the picker menu
        vim.schedule(function()
          open_picker_loop()
        end)
      else
        open_picker_loop()
      end
    end)
  end

  -- Initial trigger execution call
  open_picker_loop()
end

return M
