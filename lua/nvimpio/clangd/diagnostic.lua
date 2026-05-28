local M = {}

-- ====================================================================
-- 1. CONFIGURATION & STATE MANIFEST PATHS
-- ====================================================================
local root_markers = { 'platformio.ini', '.git', '.clangd' }

-- 🌟 FIXED: We fetch paths dynamically on boot, but do NOT grab static buffer IDs here anymore
local initial_buf = vim.api.nvim_get_current_buf()
local initial_file = vim.api.nvim_buf_get_name(initial_buf)
local project_root = vim.fs.root(initial_file, root_markers) or vim.uv.cwd()

-- Isolated project JSON state database location
local database_file = project_root .. '/.nvimpio_filters.json'

-- High-speed memory tracking dictionaries
local blocked_codes = {}
local blocked_phrases = {}

-- ====================================================================
-- 2. DATABASE DESERIALIZATION LOOPS (READ / WRITE)
-- ====================================================================
local function load_filter_database()
  local f = io.open(database_file, 'rb')
  if not f then
    return
  end
  local raw_json = f:read('*all')
  f:close()

  if raw_json and raw_json ~= '' then
    -- Safely parse using Neovim's native ultra-fast JSON decoder
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
    -- f:write(vim.json.encode(payload))
    f:close()
  end
end

-- Pre-load the active database directly into memory state variables
load_filter_database()

-- ====================================================================
-- 3. UNIVERSAL INMEMORY REDIRECTION LAYER (ZERO LEAKS CATCHER)
-- ====================================================================
function M.clean_diagnostics_pipeline(diagnostics)
  -- Bypass optimization for gigantic multi-error system includes
  if #diagnostics > 300 then
    return diagnostics
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

    local is_noise = blocked_codes[code] or matches_text_pattern

    if not is_noise then
      table.insert(cleaned, diag)
    end
  end
  return cleaned
end

-- ====================================================================
-- 4. THE PREMIUM STATE-AWARE SNACKS.PICKER INTERFACE
-- ====================================================================
function M.manage_file_diagnostics_interactive()
  -- 🌟 CRITICAL REPAIR: Always grab the current active buffer ID dynamically
  -- the exact millisecond the user executes this interactive function block!
  local current_buf = vim.api.nvim_get_current_buf()
  local diagnostics = vim.diagnostic.get(current_buf)

  if #diagnostics == 0 then
    vim.notify('✅ Complete Parity: No active compiler exceptions detected!', vim.log.levels.INFO)
    return
  end

  -- Group instances to count occurrences dynamically
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

  -- Force types via local fallback so lua_ls remains completely silent
  local ok, snacks_api = pcall(require, 'snacks')
  if not ok or not snacks_api.picker then
    vim.notify('❌ snacks.nvim picker component is not fully loaded yet.', vim.log.levels.ERROR)
    return
  end

  snacks_api.picker({
    source = 'Microcontroller Diagnostic Mangler',
    items = picker_items,
    layout = 'vscode',
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
          vim.notify('🔒 Overrides Saved! Filtered ' .. added .. ' new items.', vim.log.levels.WARN, { title = 'Compiler Mangler' })

          -- 🚀 FOOLPROOF UPSTREAM RE-RENDER ENGINE
          -- We fetch Neovim's global text namespace tied to the clangd service
          local lsp_namespace = vim.api.nvim_get_namespaces()['vim.lsp.clangd.' .. current_buf] or vim.api.nvim_get_namespaces()['vim.lsp.clangd']

          if lsp_namespace then
            -- 1. Extract the pristine diagnostic snapshot array currently stored inside Neovim's engine cache
            local cached_diagnostics = vim.diagnostic.get(current_buf, { namespace = lsp_namespace })

            -- 2. Run the snapshot array through your pipeline loop to filter out the newly blocked items
            local dynamic_filtered = M.clean_diagnostics_pipeline(cached_diagnostics)

            -- 3. Force-write the newly filtered diagnostic table into Neovim's master namespace
            vim.diagnostic.set(lsp_namespace, current_buf, dynamic_filtered)
          end
        else
          vim.notify('ℹ️ Selected items are already successfully blocked.', vim.log.levels.INFO)
        end
        -- if added > 0 then
        --   save_filter_database()
        --   vim.notify('🔒 Overrides Saved! Filtered ' .. added .. ' new items.', vim.log.levels.WARN, { title = 'Compiler Mangler' })
        --
        --   -- 🚀 SECURE HIGH-PERFORMANCE UPSTREAM MUTATION
        --   -- Instead of messing with raw client indices or calling complex redraw hooks,
        --   -- we pull Neovim's local buffer diagnostic storage array, run it through our
        --   -- custom pipeline filter, and update Neovim's master namespace list.
        --
        --   local active_diagnostics = vim.diagnostic.get(current_buf)
        --   local cleaned_diagnostics = M.clean_diagnostics_pipeline(active_diagnostics)
        --
        --   -- Use a loop to dynamically extract and query active language client namespaces safely
        --   local active_clients = vim.lsp.get_clients({ bufnr = current_buf, name = 'clangd' })
        --
        --   for _, target_client in ipairs(active_clients) do
        --     if target_client.id then
        --       -- 1. Grab the precise internal LSP diagnostic namespace matching clangd
        --       local ns = vim.lsp.diagnostic.get_namespace(target_client.id)
        --
        --       -- 2. Force-overwrite Neovim's display cache database records instantly
        --       vim.diagnostic.set(ns, current_buf, cleaned_diagnostics)
        --     end
        --   end
        -- else
        --   vim.notify('ℹ️ Selected items are already successfully blocked.', vim.log.levels.INFO)
        -- end
        -- if added > 0 then
        --   save_filter_database()
        --   vim.notify('🔒 Overrides Saved! Filtered ' .. added .. ' new items.', vim.log.levels.WARN, { title = 'Compiler Mangler' })
        --   vim.cmd('edit!')
        --   -- require('nvimpio.clangd.control').restart()
        -- else
        --   vim.notify('ℹ️ Selected items are already successfully blocked.', vim.log.levels.INFO)
        -- end
      end,

      suppress_group_action = function(picker, item)
        if not item then
          return
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
          vim.notify('🔒 Overrides Saved! Filtered ' .. added .. ' new items.', vim.log.levels.WARN, { title = 'Compiler Mangler' })

          -- 🚀 FOOLPROOF UPSTREAM RE-RENDER ENGINE
          -- We fetch Neovim's global text namespace tied to the clangd service
          local lsp_namespace = vim.api.nvim_get_namespaces()['vim.lsp.clangd.' .. current_buf] or vim.api.nvim_get_namespaces()['vim.lsp.clangd']

          if lsp_namespace then
            -- 1. Extract the pristine diagnostic snapshot array currently stored inside Neovim's engine cache
            local cached_diagnostics = vim.diagnostic.get(current_buf, { namespace = lsp_namespace })

            -- 2. Run the snapshot array through your pipeline loop to filter out the newly blocked items
            local dynamic_filtered = M.clean_diagnostics_pipeline(cached_diagnostics)

            -- 3. Force-write the newly filtered diagnostic table into Neovim's master namespace
            vim.diagnostic.set(lsp_namespace, current_buf, dynamic_filtered)
          end
        else
          vim.notify('ℹ️ Selected items are already successfully blocked.', vim.log.levels.INFO)
        end
        -- if added > 0 then
        --   save_filter_database()
        --   vim.notify('🔒 Overrides Saved! Filtered ' .. added .. ' new items.', vim.log.levels.WARN, { title = 'Compiler Mangler' })
        --
        --   -- 🚀 SECURE HIGH-PERFORMANCE UPSTREAM MUTATION
        --   -- Instead of messing with raw client indices or calling complex redraw hooks,
        --   -- we pull Neovim's local buffer diagnostic storage array, run it through our
        --   -- custom pipeline filter, and update Neovim's master namespace list.
        --
        --   local active_diagnostics = vim.diagnostic.get(current_buf)
        --   local cleaned_diagnostics = M.clean_diagnostics_pipeline(active_diagnostics)
        --
        --   -- Use a loop to dynamically extract and query active language client namespaces safely
        --   local active_clients = vim.lsp.get_clients({ bufnr = current_buf, name = 'clangd' })
        --
        --   for _, target_client in ipairs(active_clients) do
        --     if target_client.id then
        --       -- 1. Grab the precise internal LSP diagnostic namespace matching clangd
        --       local ns = vim.lsp.diagnostic.get_namespace(target_client.id)
        --
        --       -- 2. Force-overwrite Neovim's display cache database records instantly
        --       vim.diagnostic.set(ns, current_buf, cleaned_diagnostics)
        --     end
        --   end
        -- else
        --   vim.notify('ℹ️ Selected items are already successfully blocked.', vim.log.levels.INFO)
        -- end
        --

        -- if added > 0 then
        --   save_filter_database()
        --   vim.notify(
        --     '💥 Group Cleansed! Blocked all ' .. added .. ' instances matching [' .. target_code .. ']',
        --     vim.log.levels.WARN,
        --     { title = 'Compiler Mangler' }
        --   )
        --   vim.cmd('edit!')
        --   -- require('nvimpio.clangd.control').restart()
        -- else
        --   vim.notify('ℹ️ Global group constraints are already up to date.', vim.log.levels.INFO)
        -- end
      end,
    },
  })
end

return M
