local M = {}

local boilerplate = require('nvimpio.boilerplate')
local boilerplate_gen = boilerplate.boilerplate_gen

-- stylua: ignore start
----------------------------------------------------------------------------------------
-- INFO: configure clangd lsp server
--stylua: ignore
-----------------------------------------------------------------------------------------
function M.clangdIntall(callback, package_name)
  package_name = package_name or 'clangd'

  -- Modern Neovim 0.11+ way to ensure Mason binaries are found
  local bin_name = OS.is_win and package_name .. '.cmd' or package_name
  local mason_bin = vim.fs.joinpath(OS.data_dir, 'mason', 'bin')
  local mason_exe = vim.fs.joinpath(mason_bin, bin_name)

  local registry = require('mason-registry')

  local check_count = 0
  local max_checks = 60 -- 60 * 1000ms = 60 seconds timeout (installs take time)

  local function poll()
    registry.refresh(function()
      local pkg = registry.get_package(package_name)

      -- 1. SUCCESS: Installed and file is ready
      if pkg:is_installed() and vim.fn.executable(mason_exe) == 1 then
        callback(mason_exe)
        return
      end

      -- 2. TRIGGER: Not installed and NOT installing? Start the install.
      if not pkg:is_installed() and not pkg:is_installing() then
        vim.notify('Mason: Auto-installing ' .. package_name .. ' ...', vim.log.levels.INFO)
        pkg:install()
        -- After triggering install, we continue to poll to wait for completion
      end

      -- 3. WAIT: If we haven't timed out, check again in 1 second
      if check_count < max_checks then
        check_count = check_count + 1
        -- Visual feedback for long installs
        if check_count % 5 == 0 then
          vim.schedule(function()
            vim.cmd('echo "Mason: Waiting for ' .. package_name .. ' installation... ' .. check_count .. 's"')
          end)
        end
        vim.defer_fn(poll, 1000)
        return
      end

      -- 4. FAIL/TIMEOUT: Return system fallback
      vim.notify('Mason: ' .. package_name .. ' setup timed out. Using system fallback.', vim.log.levels.WARN)
      callback(package_name)
    end)
  end
  poll()
end

----------------------------------------------------------------------------------------
-- INFO: configure clangd lsp server
-----------------------------------------------------------------------------------------

-----------------------------------------------------------------------------------------
-- 1. DEFINE PATHS AND MEMORY BUFFERS
local blocklist_file = vim.uv.cwd() .. "/clangd_blocklist.txt"
M.runtime_blocklist = {
  -- -- Preprocessor & Macro Overload Errors
  -- ["macro_too_many_args"] = true,                   -- Silences ESPAsyncWebServer warnings
  -- ["too_many_args_in_macro_invoc"] = true,          -- Silences fatal preprocessor macro spikes
  -- ["pp_file_not_found"] = true,                     -- Silences nested SDK header routing gaps
  --
  -- -- GCC Toolchain Conflict Flags
  -- ["drv_unknown_argument_with_suggestion"] = true,  -- Silences the -mlongcalls warning
  -- ["drv_unknown_argument"] = true,                  -- Silences other architecture specific flags
  --
  -- -- Host Machine vs Microcontroller Architecture Clashes
  -- ["redefinition_different_typedef"] = true,        -- Silences int vs ssize_t library overrides
  -- ["err_target_unknown_arch"] = true,               -- Silences unmapped core parser targets
  -- ["unused_macro_definition"] = true,               -- Mutes system config macro flooding
}

-- stylua: ignore
function M.getClangdConfig()
  local new_root_dir = vim.uv.cwd() or '.'
  if not new_root_dir then return end

  -- Safe defaults (Standard clangd behavior)
  local q_driver, merged_json = '**', ''
  -- local f_flags = [["-std=c++17", "-xc++"]]

  -- Run your toolchain detection
  if _G.metadata and _G.metadata.cc_path and _G.metadata.cc_path ~= '' then
    if _G.metadata.triplet and _G.metadata.triplet ~= '' then
      -- local include_flags = table.concat(vim.tbl_map(function(item)
      --   return '"' .. item .. '"'
      -- end, _G.metadata.fallbackFlags), ", ")

      -- local includes_toolchain = table.concat(vim.tbl_map(function(item)
      --   return '"' .. item .. '"'
      -- end, _G.metadata.includes_toolchain), ", ")

      -- f_flags = string.format([["-std=gnu++17", "-xc++", "-D__cplusplus=201703L", "--target=%s", "--sysroot=%s", %s, %s]], _G.metadata.triplet, _G.metadata.sysroot, includes_toolchain, include_flags)

      q_driver = _G.metadata.query_driver --.. ',C:/PROGRA~1/LLVM/bin/*'          -- use with "--query-driver=%s"
    end
  end

  -- Format your template string
  local json_config = boilerplate_gen([[.clangd_config.json]], vim.g.platformioRootDir)
  if not json_config then return nil end

  local _, count = json_config:gsub('%%s', '')
  -- Only use string.format if there is one or less %s
  if count <= 1 then merged_json = string.format(json_config or '', q_driver) end
  -- local formatted_str = string.format(table_config or '', q_driver, f_flags, misc.normalizePath(new_root_dir))

  -- 'decode' converts JSON string -> Lua table
  local tok, clangd_config = pcall(vim.json.decode, merged_json)

  if not tok then return nil end

  -- ====================================================================
  -- 3. THE COMPILER RENDERING HANDLERS INTERFACE
  -- ====================================================================
  -- clangd_config.handlers = {
  --   ["textDocument/publishDiagnostics"] = function(err, result, ctx, config)
  --     -- ====================================================================
  --     -- 2. Always sync the blocklist from disk right before parsing frames
  --
  --     if result and result.diagnostics then
  --       local filtered = {}
  --       for _, diagnostic in ipairs(result.diagnostics) do
  --         local code = diagnostic.code or ""
  --         local msg = (diagnostic.message or ""):lower()
  --
  --         -- 🌟 BACKEND TEXT PATTERN MATCHING FALLBACKS
  --         local matches_text_pattern = string.find(msg, "unknown argument", 1, true)
  --                                   or string.find(msg, "-mlongcalls", 1, true)
  --                                   or string.find(msg, "tweak:", 1, true)
  --
  --         -- Combine error codes and text patterns into a single master shield evaluation
  --         local is_explicitly_blocked = runtime_blocklist[code] or matches_text_pattern
  --
  --         -- ─── 🌟 THE CRITICAL PRECEDENCE GATEWAY FIX ───
  --         if is_explicitly_blocked then
  --           -- 🥇 HIGHEST PRIORITY: If it is blocked in our list or text patterns,
  --           -- DROP IT INSTANTLY. Never let it reach the severity shield!
  --
  --         elseif diagnostic.severity == 1 then
  --           -- 🥈 SECONDARY PRIORITY: Keep genuine compilation breaks (missing semicolons, typos)
  --           table.insert(filtered, diagnostic)
  --
  --         elseif not runtime_blocklist[code] then
  --           -- 🥉 TERTIARY PRIORITY: Pass normal unblocked warnings through
  --           table.insert(filtered, diagnostic)
  --         end
  --       end
  --       result.diagnostics = filtered
  --     end
  --     -- Pass cleanly down to the Neovim 0.11 global LSP handler
  --     vim.lsp.handlers["textDocument/publishDiagnostics"](err, result, ctx, config)
  --   end,
  -- }
  if clangd_config then return clangd_config end
end

-- ====================================================================
-- 3. DYNAMIC INTERACTION LAYER
-- ====================================================================
-- Create the execution function to permanently ban a code on the fly
function M.block_diagnostic_under_cursor()
  local line, col = unpack(vim.api.nvim_win_get_cursor(0))
  local diagnostics = vim.diagnostic.get(0, { lnum = line - 1 })

  local target_diag = nil
  for _, diag in ipairs(diagnostics) do
    if col >= diag.col and col <= diag.end_col then
      target_diag = diag
      break
    end
  end

  if target_diag then
    local code = target_diag.code
    local msg = target_diag.message or ""
    local target_code = ""

    -- CASE A: If the error has a valid code handle, use it
    if code and code ~= "" then
      target_code = code
    -- else
    --   -- CASE B: Blank code -> Extract the first two words dynamically (e.g. "unknown argument")
    --   local word1, word2 = string.match(msg:lower(), "([%w%-]+)%s+([%w%-]+)")
    --   if word1 and word2 then
    --     target_code = word1 .. " " .. word2
    --   else
    --     target_code = msg:lower():gsub("([^%w%s])", "%%%1")
    --   end
    end

    -- Check if it's already blocked
    if M.runtime_blocklist[target_code] then
      vim.notify("ℹ️ '" .. target_code .. "' is already blocked.", vim.log.levels.INFO)
      return
    end

    -- Inject into memory table instantly
    M.runtime_blocklist[target_code] = true

    -- Append to disk permanently
    local f_append = io.open(blocklist_file, "ab")
    if f_append then
      f_append:write(target_code .. "\n")
      f_append:close()
    end

    -- local current_buf = vim.api.nvim_get_current_buf()
    -- local namespaces = vim.diagnostic.get_namespaces()
    -- for ns_id, _ in pairs(namespaces) do
    --   -- Passes an integer explicitly to avoid the type checking crash
    --   vim.diagnostic.set(ns_id, current_buf, {})
    -- end
    -- Refresh active buffer layout right away without restarting Neovim
    vim.cmd("edit!")
    -- vim.cmd('checktime')
    vim.schedule(function ()
      M.restart()
    end)
    vim.notify("✅ Silenced '" .. target_code .. "' permanently!", vim.log.levels.WARN, { title = "LSP Blocklist Manager" })
  else
    vim.notify("❌ No valid LSP diagnostic error found under cursor.", vim.log.levels.ERROR)
  end
end



-- INFO: clangdRestart()
--------------------------------------------------------------------------------
--- stylua: ignore
function M.restart()
  local name = 'clangd'
  OS.notify('LSP: Clangd restart.', 'warn')

  local clangConfig = M.getClangdConfig()

  vim.lsp.config(name, clangConfig)
  vim.lsp.enable(name, false)
  vim.lsp.enable(name, true)
  vim.cmd('checktime')
  _G.metadata.isBusy = false
end

-- INFO: set_clang_format_style()
--------------------------------------------------------------------------------
-- stylua: ignore
function M.setFormatStyle()
  local styles = { 'LLVM', 'Google', 'Chromium', 'Mozilla', 'WebKit', 'Microsoft', 'GNU' }

  vim.ui.select(styles, {
    prompt = 'Select Clang-Format base style:',
  }, function(choice)
    if not choice then return end

    -- Define the command as a table for cleaner execution
    -- We use cmd /c only because of the '>' redirect

    M.clangdIntall(function(clangdCmd)
      -- using toggleterm for setting clang-format style
      local cmd = string.format('%s --style=%s --dump-config > .clang-format', clangdCmd, choice:lower())
      local pio = require('nvimpio.pio.upkeep')
      pio.run_sequence({
        cmnds = { cmd },
        cb = pio.clangFormat,
        from = 'clangdIntall',
      })

      -- using hidden system command for setting clang-format style
      -- local cmd = { clangdCmd, string.format('--style=%s --dump-config > .clang-format', choice:lower()) }
      -- Execute asynchronously
      -- vim.system(cmd, { text = true }, function(obj)
      --   -- This callback runs when the process finishes
      --   -- Use vim.schedule to perform UI tasks/API calls on the main thread
      --   vim.schedule(function()
      --     if obj.code == 0 then
      --       OS.notify('Created .clang-format (' .. choice .. ')', "info")
      --
      --       -- Restart clangd to apply the new rules
      --       M.restart()
      --       print('LSP Reloaded: Using ' .. choice .. ' style.')
      --     else
      --       OS.notify('Failed to generate .clang-format. Error: ' .. (obj.stderr or "Unknown"), "error")
      --     end
      --   end)
      -- end)
    end, 'clang-format')
  end)
end


-- pio/control 160
-- pio/upkeep 170, 1001, 1178
-- INFO: get_clangd_unknown_args
--------------------------------------------------------------------------------
---@param from string
function M.getUnknownArgsCli(from)
  from = (type(from)=='string' and from ~= '') and from or 'PIO: '
  -- 1. RESET: Clear flags and rebuild .clangd (removes old 'Remove' block)
  boilerplate.args = {}

  -- Strip out any previous dynamic blocks to prevent endless growing
  boilerplate_gen('.clangd', vim.g.platformioRootDir) -- read user '.clangd'

  -- 2. FIND: Grab the first .cpp or .c file in /src
  local check_file = vim.fs.find(function(name)
    return name:match('%.cpp$') or name:match('%.c$')
  end, { limit = 1, path = vim.uv.cwd() .. '/src' })[1]

  if not check_file then
    boilerplate_gen([[main.cpp]], vim.uv.cwd() .. '/src')
    boilerplate_gen([[main.hpp]], vim.uv.cwd() .. '/include')
    check_file = vim.uv.cwd() .. '/src/main.cpp'
  end

  -- 3. SCAN: Run clangd (it will see all errors because .clangd is now empty)
  M.clangdIntall(function(clangdCmd)

    -- local output_chunks = {}
    -- local clangd_cmd = { "clangd", "--compile-commands-dir=.", "--check=" .. check_file, "--log=error" }
    -- -- 3. Run in a completely isolated background thread pool
    -- vim.system(clangd_cmd, {
    --   text = true,
    --   -- ⏳ THE BULLETPROOF TIMEOUT: Native OS process monitoring.
    --   -- Sets a generous maximum hard cutoff time limit (e.g., 60 seconds)
    --   -- to comfortably accommodate slow platform installations or library downloads.
    --   timeout = 60000,
    --   stdout = function(_, data) if data then table.insert(output_chunks, data) end end,
    --   stderr = function(_, data) if data then table.insert(output_chunks, data) end end,
    -- }, function(obj)
    --   vim.schedule(function()
    --   end)
    -- end)

    OS.notify('getting unknown arguments for file ' .. check_file)
    --------------------------------------------------------------------------------
    -- cli
    local cmd = { clangdCmd, '--compile-commands-dir=.', '--check=' .. check_file, '--query-driver=**', '--log=error' }
    -- local cmd = { clangdCmd, '--compile-commands-dir=.', '--check=' .. check_file, '--log=error' }
    vim.system(cmd, { text = true }, function(obj)
      vim.schedule(function()
        local output = (obj.stdout or '') .. (obj.stderr or '')
        local args_table = {}
        local seen = {} -- 🌟 Look-up filter to prevent duplicate flags

        -- Extract anything clangd reports as an 'unknown argument'
        if not string.find(output, "%.clang%-format") then
          for arg in string.gmatch(output, "unknown argument[:%s]+'([^']+)'") do
            local clean_flag = string.format('"%s"', arg:gsub('[;%.]$', ''))

            -- ✅ Only save the flag if we haven't encountered it yet on this run
            if not seen[clean_flag] then
              seen[clean_flag] = true
              table.insert(args_table, clean_flag)
            end
          end
        end
        -- 4. UPDATE: Rebuild with the new discovered flags
        boilerplate.args = args_table
        boilerplate_gen('.clangd', vim.g.platformioRootDir)

        OS.notify(from .. ' Clangd ✅Extracted ' .. #args_table .. ' flags.')
        M.restart()
      end)
    end)
  end, 'clangd')
end


-- INFO: get_clangd_unknown_args
--------------------------------------------------------------------------------
---@param from string
function M.getUnknownArgsGui(from)
  from = (type(from)=='string' and from ~= '') and from or 'PIO: '
  -- 1. RESET: Clear flags and rebuild .clangd (removes old 'Remove' block)
  boilerplate.args = {}

  -- Strip out any previous dynamic blocks to prevent endless growing
  boilerplate_gen('.clangd', vim.g.platformioRootDir) -- read user '.clangd'

  -- 2. FIND: Grab the first .cpp or .c file in /src
  local check_file = vim.fs.find(function(name)
    return name:match('%.cpp$') or name:match('%.c$')
  end, { limit = 1, path = vim.uv.cwd() .. '/src' })[1]

  if not check_file then
    boilerplate_gen([[main.cpp]], vim.uv.cwd() .. '/src')
    boilerplate_gen([[main.hpp]], vim.uv.cwd() .. '/include')
    check_file = vim.uv.cwd() .. '/src/main.cpp'
  end

  -- 3. SCAN: Run clangd (it will see all errors because .clangd is now empty)
  M.clangdIntall(function(clangdCmd)
    OS.notify('getting unknown arguments for file ' .. check_file)
    --------------------------------------------------------------------------------
    --------------------------------------------------------------------------------
    -- gui

-- C:/Users/batoaqaa/AppData/Local/nvim-data/mason/bin/clangd.cmd --compile-commands-dir=. --check=C:/VSCode/data/Projects/Digital-Wall-Clock-Long-ESP32S3-Pray5/src/mainClock.cpp --query-driver=C:/Users/batoaqaa/.platformio/esp32s3/packages/toolchain-xtensa-esp32s3/bin/xtensa-esp32s3-elf-* --log=error
-- "--fallback-style=llvm" --compile_args_from=filesystem -- -Wno-unknown-argument && echo _CMMNDS_0001:DONE || echo _CMMNDS_0001:FAIL
    local cmd_str = string.format('%s --compile-commands-dir=. --check=%s --query-driver=%s --log=error --enable-config --fallback-style=llvm --compile_args_from=filesystem', clangdCmd, check_file, _G.metadata.query_driver)
    local pio = require('nvimpio.pio.upkeep')
    local cb = function(status)
      pio.handleClangdCheck(status, function(success, args_table)
        args_table = args_table or {}
        if success then
          boilerplate.args = args_table
          boilerplate_gen('.clangd', vim.g.platformioRootDir)

          OS.notify(from .. ' Clangd ✅Extracted ' .. #args_table .. ' flags.')
          M.restart()
        end
      end)
    end
    pio.run_sequence({ cmnds = { cmd_str }, cb = cb, from = string.format('%s clangdCmd' , from) })
  end, 'clangd')
end
--------------------------------------------------------------------------------

--stylua: ignore
--=============================================================================
function M.init(clangd)
  OS.notify('Clangd Control: initialize', "info")

  -- ====================================================================
  -- 1. LOAD PREVIOUSLY SAVED DYNAMIC CODES ON BOOT
  local f_read = io.open(blocklist_file, "rb")
  if f_read then
    for line in f_read:lines() do
      -- Strip hidden Windows carriage returns and whitespaces cleanly
      local clean_code = line:gsub("\r", ""):gsub("^%s*(.-)%s*$", "%1")
      if clean_code ~= "" then
        M.runtime_blocklist[clean_code] = true
      end
    end
    f_read:close()
  end

  -- ====================================================================
  -- ====================================================================
  -- ====================================================================
-- 1. DEFINE GLOBAL CONFIGURATION PATHS NATIVELY
local appdata = os.getenv("LOCALAPPDATA") or (os.getenv("USERPROFILE") .. "\\AppData\\Local")
local global_config_dir = appdata .. "\\clangd"
local global_config_file = global_config_dir .. "\\config.yaml"

if vim.fn.isdirectory(global_config_dir) == 0 then
  vim.fn.mkdir(global_config_dir, "p")
end

-- ====================================================================
-- 2. NATIVE UNIVERSAL CLIENT SPECIFICATION
-- ====================================================================
vim.lsp.config("clangd", {
  cmd = {
    "clangd",
    "--enable-config",            -- Forces clangd to read your global file
    "--background-index=false",   -- Protects CPU from your 13,000-line file
    "--limit-results=100",        -- Prevents autocomplete UI lag
    "--query-driver=C:/Users/batoaqaa/.platformio/esp32s3/packages/toolchain-xtensa-esp32s3/bin/*"
  },
  filetypes = { "c", "cpp", "objc", "objcpp" },
})
vim.lsp.enable("clangd")

  -- ====================================================================
  -- 3. THE INTERACTIVE BULK MANGLEMENT SELECTOR ENGINE
  -- ====================================================================
  function M.manage_file_diagnostics_interactive()
    local current_buf = vim.api.nvim_get_current_buf()
    -- Fetch ALL diagnostics currently active for the open file buffer
    local diagnostics = vim.diagnostic.get(current_buf)

    if #diagnostics == 0 then
      vim.notify("✅ No active LSP diagnostics found in this file!", vim.log.levels.INFO)
      return
    end

    -- Track unique diagnostic codes to prevent displaying duplicates in the menu
    local unique_items = {}
    local seen_codes = {}

    for _, diag in ipairs(diagnostics) do
      local code = diag.code
      if code and code ~= "" and not seen_codes[code] then
        seen_codes[code] = true
        table.insert(unique_items, {
          code = code,
          message = diag.message,
          line = diag.lnum + 1
        })
      end
    end

    if #unique_items == 0 then
      vim.notify("ℹ️ Active diagnostics do not contain valid internal error codes.", vim.log.levels.INFO)
      return
    end

    -- Render the selectable popup menu window layout
    vim.ui.select(unique_items, {
      prompt = " 🛠️ Select an LSP Error Code to Suppress Permanently (.clangd) ",
      format_item = function(item)
        -- Formats the rows beautifully inside the floating layout window
        return string.format("[%s] Line %d: %s", item.code, item.line, item.message:sub(1, 60) .. "...")
      end,
    }, function(choice)
      -- If the user hits 'q' or Esc to close the menu without selecting, abort safely
      if not choice then return end

      local target_code = choice.code

      -- A. Ensure base structure configuration files are fully present on disk
      local f_check = io.open(global_config_file, "r")
      if not f_check then
        local f_init = io.open(global_config_file, "wb")
        if f_init then
          f_init:write("CompileFlags:\n  Remove: []\n  Add: []\nDiagnostics:\n  Suppress: []\n")
          f_init:close()
        end
      else
        f_check:close()
      end

      -- B. Load text layout to execute duplication security gates
      local file_content = ""
      local f_read = io.open(global_config_file, "rb")
      if f_read then
        file_content = f_read:read("*all")
        f_read:close()
      end

      if string.find(file_content, target_code, 1, true) then
        vim.notify("ℹ️ '" .. target_code .. "' is already suppressed inside config.yaml.", vim.log.levels.INFO)
        return
      end

      -- C. Ingress insertion: Inject choice code string inside the YAML Suppress block array
      local pattern = "(Suppress:%s*%[)"
      local replacement = "Suppress: [\n    \"" .. target_code .. "\","
      local updated_content, count = string.gsub(file_content, pattern, replacement)

      if count == 0 then
        pattern = "(Suppress:)"
        replacement = "Suppress:\n    - \"" .. target_code .. "\""
        updated_content = string.gsub(file_content, pattern, replacement)
      end

      -- D. Write configurations instantly down to binary streams storage paths
      local f_write = io.open(global_config_file, "wb")
      if f_write then
        f_write:write(updated_content)
        f_write:close()
      end

      -- E. Reboot the active language server engine background tracking nodes
      vim.notify("🚀 Suppressing rule: Injecting '" .. target_code .. "' into global compiler limits...", vim.log.levels.WARN, { title = "Global Clangd Config Manager" })
      vim.cmd("LspRestart clangd")
    end)
  end

  -- 4. BIND TO A UNIFIED WORKSPACE SHORTCUT MAPPING
  -- vim.keymap.set("n", "<leader>da", "<cmd>lua _G.manage_file_diagnostics_interactive()<CR>", { desc = "Review and Ignore File LSP Codes" })
  -- ====================================================================
  -- ====================================================================
  -- ====================================================================
  -- 🌟 THE ISOLATED CLANGD HANDLER GATEWAY (ZERO PERFORMANCE LOSS FOR OTHER LSPs)
  -- ====================================================================
  -- local original_diagnostic_handler = vim.lsp.handlers["textDocument/publishDiagnostics"]
  --
  -- vim.lsp.handlers["textDocument/publishDiagnostics"] = function(err, result, ctx, config)
  --   -- Get the active client object processing this exact message package
  --   local client = vim.lsp.get_client_by_id(ctx.client_id)
  --
  --   -- 🛡️ CONDITIONAL GATEWAY: Only scrub data frames if they originate from clangd
  --   if client and client.name == "clangd" then
  --     if result and result.diagnostics then
  --       local cleaned = {}
  --
  --       for _, diagnostic in ipairs(result.diagnostics) do
  --         local code = diagnostic.code or ""
  --         local msg = (diagnostic.message or ""):lower()
  --
  --         -- Simultaneously evaluate our dynamic blocklist dictionary and pattern text strings
  --         local is_blocked = M.runtime_blocklist[code]
  --                         -- or string.find(msg, "unknown argument", 1, true)
  --                         -- or string.find(msg, "-mlongcalls", 1, true)
  --                         -- or string.find(msg, "tweak:", 1, true)
  --         if not is_blocked then
  --           table.insert(cleaned, diagnostic)
  --         end
  --       end
  --       result.diagnostics = cleaned
  --     end
  --   end
  --   -- Safely pass the payload to the native engine, completely untouched for all other LSPs!
  --   original_diagnostic_handler(err, result, ctx, config)
  -- end
  -- --==========================================================================

  require('nvimpio.clangd.commands')

  vim.keymap.set('n', 'gll', function()
    vim.cmd.edit(vim.lsp.log.get_filename())
  end, { desc = 'open LSP [l]og' })

  if clangd.install then require('nvimpio.clangd.config') end
end

-- stylua: ignore end

return M
