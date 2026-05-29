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
-- 3. THE HIGH-PERFORMANCE RENDER OVERRIDE (0 LINTER WARNINGS!)
-- ====================================================================
-- Intercepting at the handler wrapper layer provides optimal performance.
-- Neovim passes a numeric namespace handle directly to the function signature.
if not _G.__nvimpio_handler_hooked then
  local original_show_handler = vim.diagnostic.handlers.show

  vim.diagnostic.handlers.show = function(namespace, bufnr, diagnostics, opts)
    -- Fetch meta properties using the pure numeric handle provided by Neovim
    local ns_meta = vim.diagnostic.get_namespace(namespace)

    -- 🚀 PERFORMANCE BOUNDARY GUARD: Only filter if the engine is clangd
    if ns_meta and ns_meta.name and ns_meta.name:find('clangd') then
      diagnostics = M.clean_diagnostics_pipeline(diagnostics)
    end

    original_show_handler(namespace, bufnr, diagnostics, opts)
  end
  _G.__nvimpio_handler_hooked = true
end

-- local original_diagnostic_handler = vim.lsp.handlers['textDocument/publishDiagnostics']
-- vim.lsp.handlers['textDocument/publishDiagnostics'] = function(err, result, ctx, config)
--   -- 1. Ultra-fast boundary checks: exit immediately if it's not clangd data
--   -- Cast ctx cleanly so the language server knows it contains protocol definitions
--   local target_ctx = ctx ---@as lsp.HandlerContext
--   local client_id = target_ctx and target_ctx.client_id
--   local client = client_id and vim.lsp.get_client_by_id(client_id)
--
--   if not client or client.name ~= 'clangd' then
--     return original_diagnostic_handler(err, result, ctx, config)
--   end
--
--   -- 2. Clangd exclusive payload processing zone
--   if not err and result and result.diagnostics then
--     if M.clean_diagnostics_pipeline then
--       result.diagnostics = M.clean_diagnostics_pipeline(result.diagnostics)
--     end
--   end
--   -- Hand off the validated and stripped data array down to the UI renderer
--   original_diagnostic_handler(err, result, ctx, config)
-- end
-- ====================================================================
-- 4. THE PREMIUM STATE-AWARE SNACKS.PICKER INTERFACE
-- ====================================================================
function M.manage_file_diagnostics_interactive()
  local current_buf = vim.api.nvim_get_current_buf()
  local diagnostics = vim.diagnostic.get(current_buf)

  if #diagnostics == 0 then
    vim.notify('✅ Complete Parity: No active compiler exceptions detected!', vim.log.levels.INFO)
    return
  end

  local code_counts = {}
  for _, diag in ipairs(diagnostics) do
    local c_name = diag.code or 'uncategorized_noise'
    code_counts[c_name] = (code_counts[c_name] or 0) + 1
  end

  local picker_items = {}
  for _, diag in ipairs(diagnostics) do
    local code_name = diag.code or 'uncategorized_noise'
    local count = code_counts[code_name]

    local sev_icon, sev_hl = '⚠️ ', 'DiagnosticWarn'
    if diag.severity == 1 then
      sev_icon, sev_hl = '❌', 'DiagnosticError'
    end

    table.insert(picker_items, {
      text = string.format('📂 Group [%s] (%d items) • Line %d', code_name, count, diag.lnum + 1),
      comment = diag.message,
      idx = #picker_items + 1,
      code = code_name,
      message = diag.message,
      icon = sev_icon,
      icon_hl = sev_hl,
    })
  end

  table.sort(picker_items, function(a, b)
    return a.code < b.code
  end)

  local ok, snacks_api = pcall(require, 'snacks')
  if not ok or not snacks_api.picker then
    vim.notify('❌ snacks.nvim picker component is not fully loaded yet.', vim.log.levels.ERROR)
    return
  end

  snacks_api.picker({
    source = 'Microcontroller Diagnostic Mangler',
    items = picker_items,
    layout = 'vertical', -- Stable, standard built-in layout configuration preset
    win = {
      input = {
        keys = {
          ['<Tab>'] = { 'toggle_select', mode = { 'n', 'i' } },
          ['<C-g>'] = { 'suppress_group_action', mode = { 'n', 'i' } },
        },
      },
    },
    actions = {
      confirm = function(picker, item)
        picker:close()
        if not item then
          return
        end

        local selections = picker:selected({ fallback = true })
        local added = 0

        for _, selected_item in ipairs(selections) do
          local target = selected_item.code
          if target and target ~= '' and target ~= 'uncategorized_noise' then
            if not blocked_codes[target] then
              blocked_codes[target] = true
              added = added + 1
            end
          else
            local word1, word2 = string.match(selected_item.message:lower(), '([%w%-]+)%s+([%w%-]+)')
            local key_phrase = (word1 and word2) and (word1 .. ' ' .. word2) or selected_item.message:lower()
            if not blocked_phrases[key_phrase] then
              blocked_phrases[key_phrase] = true
              added = added + 1
            end
          end
        end

        if added > 0 then
          save_filter_database()
          vim.notify('🔒 Overrides Saved!', vim.log.levels.WARN, { title = 'Compiler Mangler' })

          -- 🚀 FORCE AN INSTANT SCREEN RE-RENDER
          -- This triggers Neovim to push current items through the wrapper,
          -- dropping newly blocked items instantly without resetting the server link!
          vim.diagnostic.show(nil, current_buf)
        end
      end,

      suppress_group_action = function(picker, item)
        if not item then
          return picker:close()
        end
        picker:close()

        local target_code = item.code
        local bulk_diags = vim.diagnostic.get(current_buf)
        local added = 0

        for _, diag in ipairs(bulk_diags) do
          local cur_code = diag.code or 'uncategorized_noise'
          if cur_code == target_code then
            if cur_code ~= 'uncategorized_noise' then
              if not blocked_codes[cur_code] then
                blocked_codes[cur_code] = true
                added = added + 1
              end
            else
              local word1, word2 = string.match(diag.message:lower(), '([%w%-]+)%s+([%w%-]+)')
              local phrase = (word1 and word2) and (word1 .. ' ' .. word2) or diag.message:lower()
              if not blocked_phrases[phrase] then
                blocked_phrases[phrase] = true
                added = added + 1
              end
            end
          end
        end

        if added > 0 then
          save_filter_database()
          vim.notify('💥 Group Cleansed!', vim.log.levels.WARN, { title = 'Compiler Mangler' })

          -- 🚀 FORCE AN INSTANT SCREEN RE-RENDER
          vim.diagnostic.show(nil, current_buf)
        end
      end,
    },
  })
end

return M
