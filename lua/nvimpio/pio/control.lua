local M = {}

--stylua: ignore start
local clangd = require('nvimpio.clangd.control')
local misc = require('nvimpio.utils.misc')

------------------------------------------------------------------------------------
M.watcher_handles = {}
M.augroup = vim.api.nvim_create_augroup('NvimpioWatchers', { clear = true })

local uv = vim.uv or vim.loop

--- Non-blocking, error-trapped SHA256 file hashing
---@param path string
---@return string hash SHA256 string or empty string ''
function M.get_hash(path)
  if not path or path == '' then return '' end

  local stat = uv.fs_stat(path)
  if not stat or stat.type ~= 'file' or stat.size == 0 then
    return ''
  end

  local fd = uv.fs_open(path, 'r', 438) -- 0666 permissions octal
  if not fd then
    return ''
  end

  local ok, data = pcall(uv.fs_read, fd, stat.size, 0)
  pcall(uv.fs_close, fd)

  if not ok or type(data) ~= 'string' or data == '' then
    return ''
  end

  return vim.fn.sha256(data)
end

--- Standardize paths safely across platforms
local function normalize_path(path)
  if not path or path == '' then return '' end
  return vim.fs.normalize(path)
end

--- Case-insensitive string comparison for OS compatibility
local function filenames_equal(a, b)
  if OS.is_win or OS.is_mac then
    return string.lower(a) == string.lower(b)
  end
  return a == b
end

--- Safely close any libuv handle (timer or fs_event) with explicit nil checks
local function safe_close_handle(handle)
  if handle and type(handle) == 'userdata' then
    local is_closing = pcall(function() return handle:is_closing() end) and handle:is_closing()
    if not is_closing then
      if handle.stop then
        pcall(function() handle:stop() end)
      end
      pcall(function() handle:close() end)
    end
  end
end

function M.stop_watchers()
  local handles_to_close = M.watcher_handles
  M.watcher_handles = {} -- Clear reference first to prevent iteration mutation bugs

  for _, handle in ipairs(handles_to_close) do
    safe_close_handle(handle)
  end

  vim.api.nvim_clear_autocmds({ group = M.augroup })
end

--- Remove a specific handle from the global handle array safely
local function remove_watcher_handle(handle)
  if not handle then return end
  for i = #M.watcher_handles, 1, -1 do
    if M.watcher_handles[i] == handle then
      table.remove(M.watcher_handles, i)
      break
    end
  end
end

local function add_watch_target(target)
  target.last_hash = target.last_hash or ''
  target.is_busy = false

  local norm_target_path = normalize_path(target.path)
  local debounce_timer = uv.new_timer()
  local busy_timeout_timer = uv.new_timer()

  if debounce_timer then table.insert(M.watcher_handles, debounce_timer) end
  if busy_timeout_timer then table.insert(M.watcher_handles, busy_timeout_timer) end

  local current_execution_id = 0

  local function done(exec_id)
    -- Ignore stale completion tokens from previous runs
    if exec_id and exec_id ~= current_execution_id then return end

    if busy_timeout_timer then
      pcall(function() busy_timeout_timer:stop() end)
    end
    target.is_busy = false
  end

  local safe_execute = vim.schedule_wrap(function()
    if target.is_busy then return end

    local new_hash = M.get_hash(target.path)
    if new_hash == '' or new_hash == target.last_hash then return end

    -- Update last_hash immediately upon qualification to prevent duplicate tick triggers
    target.last_hash = new_hash
    target.is_busy = true
    current_execution_id = current_execution_id + 1
    local local_exec_id = current_execution_id

    -- SAFEGUARD: Reset busy flag after 10s timeout to prevent permanent lock
    if busy_timeout_timer then
      pcall(function() busy_timeout_timer:stop() end)
      busy_timeout_timer:start(10000, 0, vim.schedule_wrap(function()
        if target.is_busy and current_execution_id == local_exec_id then
          target.is_busy = false
          vim.notify('Nvimpio Watcher Timeout [' .. target.name .. ']: Reset busy flag', vim.log.levels.WARN)
        end
      end))
    end

    local status, err = pcall(function()
      target.cb(target, function() done(local_exec_id) end)
    end)

    if not status then
      done(local_exec_id)
      vim.notify('Nvimpio Watcher Error [' .. target.name .. ']: ' .. tostring(err), vim.log.levels.ERROR)
    end
  end)

  local function trigger()
    if debounce_timer then
      pcall(function() debounce_timer:stop() end)
      debounce_timer:start(75, 0, safe_execute)
    end
  end

  -- CHANNEL 1: Internal Neovim file saves (Direct Lua path check instead of fragile C pattern matching)
  vim.api.nvim_create_autocmd('BufWritePost', {
    group = M.augroup,
    callback = function(ev)
      local buf_path = normalize_path(vim.api.nvim_buf_get_name(ev.buf))
      if filenames_equal(buf_path, norm_target_path) then
        trigger()
      end
    end,
  })

  -- CHANNEL 2: External CLI writes (Directory Watcher with Safe Retries)
  if target.external then
    local dir_path = vim.fs.dirname(target.path)
    local target_filename = vim.fs.basename(target.path)

    local function attach_fs_event()
      if not uv.fs_stat(dir_path) then return false end

      local handle = uv.new_fs_event()
      if handle then
        handle:start(dir_path, { recursive = false }, function(err, filename)
          if err then return end

          if filename then
            local norm_filename = vim.fs.basename(normalize_path(filename))
            if not filenames_equal(norm_filename, target_filename) then
              return
            end
          end

          trigger()
        end)
        table.insert(M.watcher_handles, handle)
        return true
      end
      return false
    end

    -- Retry attachment if directory doesn't exist yet
    if not attach_fs_event() then
      local retry_timer = uv.new_timer()
      local attempts = 0
      local max_attempts = 30 -- Stop polling after 60s

      if retry_timer then
        table.insert(M.watcher_handles, retry_timer)
        retry_timer:start(2000, 2000, vim.schedule_wrap(function()
          if not retry_timer then return end
          local is_closing = pcall(function() return retry_timer:is_closing() end) and retry_timer:is_closing()
          if is_closing then return end

          attempts = attempts + 1
          if attach_fs_event() or attempts >= max_attempts then
            safe_close_handle(retry_timer)
            remove_watcher_handle(retry_timer)
          end
        end))
      end
    end
  end
end

function M.start_watchers()
  M.stop_watchers()

  local project_root = OS.project_dir or uv.cwd()

  local targets = {
    {
      name = 'ini',
      path = vim.fs.joinpath(project_root, 'platformio.ini'),
      cb = function(_, done)
        local meta = require('nvimpio.pio.metadata')
        local env = meta.get_active_env('PIO platformio.ini change:')
        if not env then
          done()
          return
        end

        require('nvimpio.pio.upkeep').pio_refresh(function(success)
          if not success then OS.notify('PIO platformio change: fail') end
          done()
        end, 'PIO platformio.ini change: ')
      end,
    },
    {
      name = 'db',
      path = vim.fs.joinpath(project_root, 'compile_commands.json'),
      cb = function(_, done)
        -- Debounce LSP restart to ensure compiledb file lock releases cleanly
        vim.defer_fn(function()
          OS.notify('PIO compiledb changed', OS.debug)
          require('nvimpio.clangd.control').restart()
          done()
        end, 300)
      end,
    },
    {
      name = 'checksum',
      path = vim.fs.joinpath(project_root, '.pio', 'build', 'project.checksum'),
      external = true,
      cb = function(_, done)
        require('nvimpio.pio.upkeep').pio_refresh(function(success)
          if success then OS.notify('PIO checksum: Metadata synced', OS.debug) end
          done()
        end, 'PIO checksum: ')
      end,
    },
  }

  for _, target in ipairs(targets) do
    add_watch_target(target)
  end
end




-- --INFO:
-- --=============================================================================
-- --  watchers setup
-- --=============================================================================
-- -- Ensure this is at the TOP of your file, outside any functions
-- -------------------------------------------------------------------------------
-- local uv = vim.uv or vim.loop
-- M.watcher_handles = {}
--
-- -- INFO:
-- -- Unified hashing for change detection
-- -------------------------------------------------------------------------------
-- function M.get_hash(path)
--   if vim.fn.filereadable(path) == 0 then
--     return nil
--   end
--   -- local ok, data = pcall(vim.fn.readfile, path) -- readfile is safer than io.open
--   -- return ok and vim.fn.sha256(table.concat(data, '\n')) or nil
--   local ok, data = misc.readFile(path) -- readfile is safer than io.open
--   return (ok and type(data) == 'string' and data ~= '') and vim.fn.sha256(data) or ''
-- end
--
-- --INFO:
-- --1.stop_watchers 
-- -------------------------------------------------------------------------------
-- function M.stop_watchers()
--   if not M.watcher_handles or (type(M.watcher_handles) ~= 'table') then M.watcher_handles = {} return end
--
--   for _, handle in ipairs(M.watcher_handles) do
--     if handle and not handle:is_closing() then
--       handle:stop()
--       handle:close() -- CRITICAL: This allows Neovim to quit instantly
--     end
--   end
--   M.watcher_handles = {}
-- end
--
-- --INFO:
-- --2.watcher cleanup
-- -------------------------------------------------------------------------------
-- function M.cleanup()
--   M.stop_watchers()
--   -- if debounce_timer and not debounce_timer:is_closing() then
--   --   debounce_timer:stop()
--   --   debounce_timer:close()
--   -- end
-- end
--
-- -- Force cleanup when leaving Neovim to prevent :qa lag
-- vim.api.nvim_create_autocmd('VimLeavePre', {
--   callback = function()
--     M.cleanup()
--   end,
-- })
--
-- --INFO:
-- --3. MAIN WATCHER: Efficient Folder Monitoring
-- -------------------------------------------------------------------------------
-- local function watch_file(target, callback)
--   local folder_path     = vim.fs.dirname(target.path)
--   local target_filename = vim.fs.basename(target.path)
--   -- local folder_path = target.path:match('(.*[/\\])')
--   -- local target_filename = target.path:match('[^/\\]+$')
--   local last_mtime = 0
--
--   local handle = uv.new_fs_event()
--   if not handle then
--     return
--   end
--
--   local debounce_timer = uv.new_timer()
--   handle:start(folder_path, { recursive = false }, function(err, filename, events)
--     if err or (filename and filename ~= target_filename) then return end
--     if events and not (events.change or events['rename']) then return end
--
--     -- if target.isBusy then return end
--
--     -- 'r': Read access
--     --'w': Write access
--     --'x': Execute access
--     --'f': Existence check (checks if the file simply exists on disk
--     if not uv.fs_access(target.path, 'r') then return end
--
--     if debounce_timer then
--       debounce_timer:stop()
--       debounce_timer:start(
--         500,
--         0,
--         vim.schedule_wrap(function()
--           local stat = uv.fs_stat(target.path)
--           if stat and stat.mtime.sec > last_mtime then
--             last_mtime = stat.mtime.sec
--
--             -- Set Busy flags before entering the heavy callback
--             -- target.isBusy = true
--             -- if _G.metadata then _G.isBusy = true end
--
--             callback(target)
--           end
--         end)
--       )
--     end
--   end)
--
--   table.insert(M.watcher_handles, handle)
--   return handle
-- end
--
-- --INFO:
-- --4. start_watches
-- -------------------------------------------------------------------------------
-- function M.start_watchers()
--   -- Clean up any existing watchers first to prevent duplicates
--   if next(M.watcher_handles) then
--     M.stop_watchers()
--   end
--
--   local project_root = OS.project_dir or vim.uv.cwd()
--
--   local targets = {
--     { -- watcher for compile_commands.json
--       name = 'db',
--       isBusy = false,
--       last_hash = '',
--       path = vim.fs.joinpath(project_root, 'compile_commands.json'),
--       cb = function(self)
--         if self.isBusy then return end
--         -- If no real change, unlock immediately and exit
--         local new_hash = M.get_hash(self.path) or ''
--         if new_hash == self.last_hash then
--           OS.notify('PIO compiledb no change', OS.debug)
--           return
--         end
--
--         self.last_hash = new_hash
--
--         vim.schedule(function()
--           OS.notify('PIO compiledb changed', OS.debug)
--           self.isBusy = true
--           -- require('nvimpio.pio.upkeep').compile_commandsFix(function ()
--           -- require('nvimpio.pio.upkeep').generate(function ()
--           --   self.last_hash = get_hash(self.path)
--             -- _G.isBusy = false
--             self.isBusy = false
--             require('nvimpio.clangd.control').restart()
--           -- end)
--         end)
--       end,
--     },
--     { -- watcher for platformio.ini
--       name = 'ini',
--       isBusy = false,
--       last_hash = M.get_hash(vim.fs.joinpath(project_root, 'platformio.ini')) or '',
--       path = vim.fs.joinpath(project_root, 'platformio.ini'),
--       cb = function(self)
--         if _G.isBusy or self.isBusy then return end
--         -- If no real change, unlock immediately and exit
--         local new_hash = M.get_hash(self.path) or ''
--         if new_hash == self.last_hash then return end
--
--         self.last_hash = new_hash
--
--         local meta = require('nvimpio.pio.metadata')
--         local env, _ = meta.get_active_env('PIO platformio.ini change:')
--         if not env then return end
--
--         vim.schedule(function()
--           self.isBusy = true
--           local pio_refresh = require('nvimpio.pio.upkeep').pio_refresh
--           pio_refresh(function(success)
--             if success then
--               -- do end
--               -- OS.notify("PIO platformio change: success")
--             else OS.notify("PIO platformio change: fail")
--             end
--             self.isBusy = false
--           end, 'PIO platformio.ini change: ')
--         end)
--       end,
--     },
--     { -- watcher for ./.pio/build/projct.checksum
--       name = 'checksum',
--       isBusy = false,
--       last_hash = '',
--       path = vim.fs.joinpath(project_root, '.pio', 'build', 'project.checksum'), --checksum_path
--       cb = function(self)
--         -- Check if we should exit early
--         if self.isBusy then return end
--         local ok, new_hash = misc.readFile(self.path)
--         if ok and type(new_hash) == 'string' and new_hash ~= '' then
--           if new_hash == self.last_hash then return end
--
--           self.last_hash = new_hash
--           vim.schedule(function()
--             self.isBusy = true
--             local pio_refresh = require('nvimpio.pio.upkeep').pio_refresh
--             pio_refresh(function(success)
--               if success then OS.notify('PIO checksum: Metadata synced', OS.debug) end
--               self.isBusy = false
--             end, 'PIO checksum: ')
--           end)
--         end
--       end,
--     },
--   }
--   for _, target in ipairs(targets) do watch_file(target, target.cb) end
-- end

--INFO: telescope settings vim.ui.select()
local dropdown_settings = {
  theme            = "dropdown",
  initial_mode     = "normal",
  sorting_strategy = "ascending",
  selection_caret  = "❯ ",
  entry_prefix     = "  ",
  layout_config = {
    height = 25,
    prompt_position = "top",
  },
}

-- Backup the core native UI selection channel handler
local original_select = vim.ui.select

---@diagnostic disable-next-line: duplicate-set-field
vim.ui.select = function(items, opts, on_choice)
  local telescope_ok, _ = pcall(require, 'telescope')
  if telescope_ok then
    opts = opts or {}

    local function format_single_item(item)
      if opts.format_item then
        return opts.format_item(item)
      elseif type(item) == "table" then
        return item.text or item.name or vim.inspect(item)
      end
      return tostring(item)
    end

    local action_state = require('telescope.actions.state')
    local actions = require('telescope.actions')
    local finders = require('telescope.finders')

    -- Helper to generate a clean entry table for Telescope's live engine refresh
    local function make_entry_list()
      return finders.new_table({
        results = items,
        entry_maker = function(entry)
          local display_str = format_single_item(entry)
          return {
            value = entry,
            display = display_str,
            ordinal = display_str,
          }
        end
      })
    end

    local picker_opts = vim.tbl_deep_extend('force', dropdown_settings, {
      prompt_title = "",
      prompt_prefix = (opts.prompt and ("🔍 " .. opts.prompt .. " › ")) or "🔍  ",
      finder = make_entry_list(), -- Uses our entry maker list tracker
      sorter = require('telescope.sorters').get_generic_fuzzy_sorter({}),

      borderchars = {
        prompt  = { "─", "│", " ", "│", "╭", "╮", "│", "│" },
        results = { "─", "│", "─", "│", "├", "┤", "╯", "╰" },
        preview = { "─", "│", "─", "│", "╭", "╮", "╯", "╰" },
      },
      attach_mappings = function(prompt_bufnr, map)
        -- Hitting Escape or q signals the menu to close and fires the single save disk dump
        local close_and_trigger_save = function()
          actions.close(prompt_bufnr)
          vim.schedule(function()
            on_choice(nil, nil)
          end)
        end

        map('n', '<Esc>', close_and_trigger_save)
        map('n', 'q',     close_and_trigger_save)

        -- THE SMARTER ZERO-FLICKER MULTI-SELECT AND AUTO-CLOSE ENGINE:
        actions.select_default:replace(function()
          local selection = action_state.get_selected_entry()
          if not selection then return end

          local clicked_item = selection.value
          local clicked_index = selection.index

          if opts.keep_open == true then
            ------------------------------------------------------------------
            -- CASE A: KEEP OPEN (Multi-select / Interactive Toggle Menus)
            ------------------------------------------------------------------
            -- Capture state of all items before callback to detect bulk changes
            local snapshot_before = {}
            for i, itm in ipairs(items) do
              snapshot_before[i] = format_single_item(itm)
            end

            -- Execute choice callback while window stays open
            on_choice(clicked_item, clicked_index)

            local current_picker = action_state.get_current_picker(prompt_bufnr)
            if current_picker then
              -- Count how many items changed text representation during on_choice
              local changed_count = 0
              for i, itm in ipairs(items) do
                if format_single_item(itm) ~= snapshot_before[i] then
                  changed_count = changed_count + 1
                end
              end

              if changed_count > 1 then
                -- BULK CHANGE DETECTED (e.g. Reset All): Full finder refresh
                current_picker:refresh(make_entry_list(), { reset_prompt = false })
              else
                -- SINGLE OR NO LINE CHANGE: Fast in-place buffer mutation
                local updated_text = format_single_item(clicked_item)
                selection.display = updated_text
                selection.ordinal = updated_text

                local results_buf = current_picker.results_bufnr
                if vim.api.nvim_buf_is_valid(results_buf) then
                  local prefix = current_picker.selection_caret or dropdown_settings.selection_caret or "  "
                  local final_line = prefix .. updated_text

                  vim.api.nvim_buf_set_lines(results_buf, clicked_index - 1, clicked_index, false, { final_line })
                end
              end
            end
          else
            ------------------------------------------------------------------
            -- CASE B: CLOSE ON ENTER (Standard Single-Select Pickers)
            ------------------------------------------------------------------
            actions.close(prompt_bufnr)
            vim.schedule(function()
              on_choice(clicked_item, clicked_index)
            end)
          end
          -- local selection = action_state.get_selected_entry()
          -- if not selection then return end
          --
          -- local clicked_item = selection.value
          -- local clicked_index = selection.index
          --
          -- -- Capture state of all items before callback to detect bulk changes
          -- local snapshot_before = {}
          -- for i, itm in ipairs(items) do
          --   snapshot_before[i] = format_single_item(itm)
          -- end
          --
          -- -- Execute choice callback
          -- on_choice(clicked_item, clicked_index)
          --
          -- local current_picker = action_state.get_current_picker(prompt_bufnr)
          -- if current_picker then
          --   -- Count how many items changed text representation during on_choice
          --   local changed_count = 0
          --   for i, itm in ipairs(items) do
          --     if format_single_item(itm) ~= snapshot_before[i] then
          --       changed_count = changed_count + 1
          --     end
          --   end
          --
          --   if changed_count > 1 then
          --     -- BULK CHANGE DETECTED (e.g. Reset All): Full finder refresh
          --     current_picker:refresh(make_entry_list(), { reset_prompt = false })
          --   else
          --     -- SINGLE OR NO LINE CHANGE: Fast in-place buffer mutation
          --     local updated_text = format_single_item(clicked_item)
          --     selection.display = updated_text
          --     selection.ordinal = updated_text
          --
          --     local results_buf = current_picker.results_bufnr
          --     if vim.api.nvim_buf_is_valid(results_buf) then
          --       local prefix = current_picker.selection_caret or dropdown_settings.selection_caret or "  "
          --       local final_line = prefix .. updated_text
          --
          --       vim.api.nvim_buf_set_lines(results_buf, clicked_index - 1, clicked_index, false, { final_line })
          --     end
          --   end
          -- end
        end)
        return true
      end
    })

    local final_theme = require('telescope.themes').get_dropdown(picker_opts)
    require('telescope.pickers').new({}, final_theme):find()
  else
    original_select(items, opts, on_choice)
  end
end

--INFO: 6.  Exported setup function
-------------------------------------------------------------------------------
function M.init(clangd_config)
  OS.notify('PIO Control: initialize', OS.debug)
  -- vim.env.PATH = OS.project_dir .. OS.path_sep .. vim.env.PATH
  -- vim.env.PLATFORMIO_BUILD_FLAGS="-std=gnu23 -std=gnu++23"
  -- require('nvimpio.device.terminal').reopen()
  require('nvimpio.pio.commands')
  require('nvimpio.pio.metadata').updateProjectConfig() --.load_project_config()
  -- require('nvimpio.pio.diagnostic')


  if clangd_config.support then clangd.init(clangd_config) end

  -- Set log level to see RPC communication (choose 'debug' or 'trace')
  -- vim.lsp.log.set_level('debug')
  -- Force multi-line formatting for all LSP entries
  -- vim.lsp.log.set_format_func(vim.inspect)

  -- Always start the watcher so it can catch a future 'pio init'
  M.start_watchers()

  -- If the file already exists, do an initial sync
  -- if vim.fn.filereadable(vim.uv.cwd() .. '/platformio.ini') == 1 then
    -- _G.metadata.isBusy = true
    -- local pio_refresh = require('nvimpio.pio.upkeep').pio_refresh
    -- pio_refresh(function(success)
    --   if success then
    --     boilerplate.core_dir = _G.metadata.core_dir
    --     -- clangd.getUnknownArgs('PIO start: ')
    --     boilerplate_gen([[.clang-format]], vim.g.platformioRootDir)
    --   end
    --   _G.metadata.isBusy = false
    -- end, 'PIO Control: ')
  -- end
end

-- stylua: ignore end
return M
