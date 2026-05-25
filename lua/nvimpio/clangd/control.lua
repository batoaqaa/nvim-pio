local M = {}

local boilerplate = require('nvimpio.boilerplate')
local boilerplate_gen = boilerplate.boilerplate_gen
local misc = require('nvimpio.utils.misc')

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
local runtime_blocklist = {
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

local runtime_patterns = {
  -- ["unknown argument"] = true,
  -- ["%-mlongcalls"] = true,
  -- ["tweak:"] = true,
}

local function sync_blocklist_from_disk()
  -- If the file doesn't exist yet, create an empty one automatically
  local f_check = io.open(blocklist_file, "r")
  if not f_check then
    local f_create = io.open(blocklist_file, "w")
    if f_create then f_create:close() end
  else
    f_check:close()
  end

  -- Safely open the file to read its saved rules
  local f_read = io.open(blocklist_file, "r")
  if f_read then
    for line in f_read:lines() do
      -- local clean_entry = vim.trim(line)
      local clean_entry = line:gsub("\r", ""):gsub("^%s*(.-)%s*$", "%1")
      if clean_entry ~= "" then
        if string.match(clean_entry, "^pattern:") then
          local raw_pattern = string.sub(clean_entry, 9)
          runtime_patterns[raw_pattern] = true
        else
          -- Save it as BOTH a code block and a generic text pattern to catch all edge cases!
          runtime_blocklist[clean_entry] = true
          runtime_patterns[clean_entry:lower()] = true
        end
      end
    end
    f_read:close()
  end
end
-- -- Pre-load it once on editor initialization
-- sync_blocklist_from_disk()
-- Guarantees the file is parsed AFTER Neovim has calculated true system paths
vim.api.nvim_create_autocmd("VimEnter", {
  callback = function()
    sync_blocklist_from_disk()
  end,
})


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

  -- ====================================================================
  -- 2. THE COMPILER RENDERING HANDLERS INTERFACE
  -- ====================================================================
  clangd_config.handlers = {
    ["textDocument/publishDiagnostics"] = function(err, result, ctx, config)
      -- 1. Always sync the blocklist from disk right before parsing frames
      sync_blocklist_from_disk()

      if result and result.diagnostics then
        local filtered = {}
        for _, diagnostic in ipairs(result.diagnostics) do
          local code = diagnostic.code or ""
          local msg = (diagnostic.message or ""):lower()

          -- Loop check across our dynamic message pattern blocks
          local matches_text_pattern = false
          for pat, _ in pairs(runtime_patterns) do
            if string.match(msg, pat) then
              matches_text_pattern = true
              break
            end
          end

          -- Evaluate dynamic codes and dynamic text simultaneously
          local is_driver_noise = runtime_blocklist[code] or matches_text_pattern

          if is_driver_noise then
            -- Drop it silently!
          elseif diagnostic.severity == 1 then
            -- Keep true fatal compiler breaks (like missing semicolons or typos)
            table.insert(filtered, diagnostic)
          elseif not runtime_blocklist[code] then
            table.insert(filtered, diagnostic)
          end
        end
        result.diagnostics = filtered
      end
      -- Pass cleanly down to the Neovim 0.11 global LSP handler
      vim.lsp.handlers["textDocument/publishDiagnostics"](err, result, ctx, config)
    end,
  }
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


    -- FORCE DYNAMIC TEXT PROTECTION:
    -- We save BOTH the code name AND the first two words of the error text
    -- This guarantees it catches it even if clangd glitches its code reporting.
    local word1, word2 = string.match(msg:lower(), "([%w%-]+)%s+([%w%-]+)")
    local generic_keyword = "unknown argument"
    if word1 and word2 then
      generic_keyword = word1 .. " " .. word2
    end

    -- Write entries to disk text file permanently
    local f_append = io.open(blocklist_file, "a")
    if f_append then
      if code and code ~= "" then f_append:write(code .. "\n") end
      f_append:write("pattern:" .. generic_keyword .. "\n")
      f_append:close()
    end

    -- local save_line = ""
    -- local display_name = ""
    --
    -- -- CASE A: The error has an official code ID
    -- if code and code ~= "" then
    --   if runtime_blocklist[code] then
    --     vim.notify("ℹ️ Code '" .. code .. "' is already blocked.", vim.log.levels.INFO)
    --     return
    --   end
    --   runtime_blocklist[code] = true
    --   save_line = code
    --   display_name = "Code: " .. code
    --
    -- -- CASE B: No official code handle exists -> Extract raw string message pattern instead
    -- else
    --   -- Escape special regex chars like symbols/hyphens to make text matching safe
    --   local clean_msg = msg:lower():gsub("([^%w%s])", "%%%1")
    --   -- Shorten long error arrays to a clean sentence fragment match
    --   local snippet = string.match(clean_msg, "[^:]+") or clean_msg
    --   snippet = vim.trim(snippet)
    --
    --   if runtime_patterns[snippet] then
    --     vim.notify("ℹ️ Pattern matching this text is already blocked.", vim.log.levels.INFO)
    --     return
    --   end
    --   runtime_patterns[snippet] = true
    --   save_line = "pattern:" .. snippet
    --   display_name = "Text Pattern: " .. msg
    -- end
    --
    -- -- Append the dynamic signature to your disk text file permanently using standard Lua
    -- local f_append = io.open(blocklist_file, "a")
    -- if f_append then
    --   f_append:write(save_line .. "\n")
    --   f_append:close():
    -- end

    -- Force instant in-memory sync so we don't wait for the next handler cycle
    sync_blocklist_from_disk()

    -- Update active window layouts cleanly right away without restarting Neovim
    vim.cmd("edit!")
    vim.notify("✅ Silenced error text containing '" .. generic_keyword .. "' permanently!", vim.log.levels.WARN, { title = "LSP Blocklist Manager" })
    -- vim.notify("✅ Silenced '" .. display_name .. "' permanently!", vim.log.levels.WARN, { title = "LSP Blocklist Manager" })
  else
    vim.notify("❌ No active LSP diagnostic error found under cursor.", vim.log.levels.ERROR)
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

  require('nvimpio.clangd.commands')

  vim.keymap.set('n', 'gll', function()
    vim.cmd.edit(vim.lsp.log.get_filename())
  end, { desc = 'open LSP [l]og' })

  if clangd.install then require('nvimpio.clangd.config') end
end

-- stylua: ignore end

return M
