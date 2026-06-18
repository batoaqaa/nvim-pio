local M = {}

--stylua: ignore start
local clangd = require('nvimpio.clangd.control')
local misc = require('nvimpio.utils.misc')
local clangdRestart = clangd.clangdRestart

--INFO:
--=============================================================================
--  watchers setup
--=============================================================================
-- Ensure this is at the TOP of your file, outside any functions
-------------------------------------------------------------------------------
local uv = vim.uv or vim.loop
M.watcher_handles = {}
local debounce_timer = uv.new_timer()

-- INFO:
-- Unified hashing for change detection
-------------------------------------------------------------------------------
local function get_hash(path)
  if vim.fn.filereadable(path) == 0 then
    return nil
  end
  -- local ok, data = pcall(vim.fn.readfile, path) -- readfile is safer than io.open
  -- return ok and vim.fn.sha256(table.concat(data, '\n')) or nil
  local ok, data = misc.readFile(path) -- readfile is safer than io.open
  return (ok and type(data) == 'string' and data ~= '') and vim.fn.sha256(data) or ''
end

--INFO:
--1.stop_watchers 
-------------------------------------------------------------------------------
function M.stop_watchers()
  if not M.watcher_handles or (type(M.watcher_handles) ~= 'table') then M.watcher_handles = {} return end

  for _, handle in ipairs(M.watcher_handles) do
    if handle and not handle:is_closing() then
      handle:stop()
      handle:close() -- CRITICAL: This allows Neovim to quit instantly
    end
  end
  M.watcher_handles = {}
end

--INFO:
--2.watcher cleanup
-------------------------------------------------------------------------------
function M.cleanup()
  M.stop_watchers()
  if debounce_timer and not debounce_timer:is_closing() then
    debounce_timer:stop()
    debounce_timer:close()
  end
end

-- Force cleanup when leaving Neovim to prevent :qa lag
vim.api.nvim_create_autocmd('VimLeavePre', {
  callback = function()
    M.cleanup()
  end,
})

--INFO:
--3. MAIN WATCHER: Efficient Folder Monitoring
-------------------------------------------------------------------------------
local function watch_file(target, callback)
  local folder_path = target.path:match('(.*[/\\])')
  local target_filename = target.path:match('[^/\\]+$')
  local last_mtime = 0

  local handle = uv.new_fs_event()
  if not handle then
    return
  end

  handle:start(folder_path, { recursive = false }, function(err, filename, events)
    if err or (filename and filename ~= target_filename) then return end
    if target.isBusy or _G.isBusy then return end
    if events and not (events.change or events['rename']) then return end

    if not uv.fs_access(target.path, 'R') then return end

    if debounce_timer then
      debounce_timer:stop()
      debounce_timer:start(
        500,
        0,
        vim.schedule_wrap(function()
          local stat = uv.fs_stat(target.path)
          if stat and stat.mtime.sec > last_mtime then
            last_mtime = stat.mtime.sec

            -- Set Busy flags before entering the heavy callback
            -- target.isBusy = true
            -- if _G.metadata then _G.isBusy = true end

            callback(target)
          end
        end)
      )
    end
  end)

  table.insert(M.watcher_handles, handle)
  return handle
end

--INFO:
--4. start_watches
-------------------------------------------------------------------------------
function M.start_watchers()
  -- Clean up any existing watchers first to prevent duplicates
  if next(M.watcher_handles) then
    M.stop_watchers()
  end

  local project_root = vim.uv.cwd() -- Use dynamic CWD instead of hardcoded path

  local targets = {
    { -- watcher for platformio.ini
      name = 'ini',
      isBusy = false,
      last_hash = '',
      path = vim.fs.joinpath(project_root, 'platformio.ini'),
      cb = function(self)
        -- If no real change, unlock immediately and exit
        local new_hash = get_hash(self.path) or ''
        if new_hash == self.last_hash then
          self.isBusy = false
          _G.isBusy = false
          return
        end

        self.last_hash = new_hash
        local meta = require('nvimpio.pio.metadata')
        local env, _ = meta.get_active_env('PIO platformio.ini change:')
        -- local env = pio.get_active_env('PIO platformio.ini change:')

        if not env then
          self.isBusy = false
          _G.isBusy = false
          return
        end

        self.isBusy = true
        _G.isBusy = true
        OS.notify('PIO platformio.ini change: compiledb update ...', 'info')
        vim.system({ 'pio', 'run', '-t', 'compiledb', '-s', '-e', env }, { text = true }, function(obj)
          vim.schedule(function()
            if obj.code == 0 then
              OS.notify('PIO platformio.ini change: compiledb update Success', 'info')
              local pio_refresh = require('nvimpio.pio.upkeep').pio_refresh
              pio_refresh(function(success)
                if success then
                  do end
                  -- clangd.getUnknownArgsCli('PIO platformio.ini  change: ')
                end
                _G.isBusy = false
                self.isBusy = false
                -- clangdRestart()
              end, 'PIO platformio.ini  change: ')
            else
              local err = (obj.stderr and obj.stderr ~= '') and obj.stderr or 'Check PIO logs'
              OS.notify('PIO platformio.ini change: Build Failed: ' .. err, 'error')
              self.isBusy = false
              _G.isBusy = false
            end
          end)
        end)
      end,
    },
    { -- watcher for ./.pio/build/projct.checksum
      name = 'checksum',
      isBusy = false,
      path = vim.fs.joinpath(project_root, '.pio', 'build', 'project.checksum'), --checksum_path
      cb = function(self)
        local ok, current_checksum = misc.readFile(self.path)
        -- Check if we should exit early
        if ok and type(current_checksum) == 'string' and current_checksum ~= '' then
          if current_checksum == _G.metadata.last_projectChecksum then
            self.isBusy = false
            _G.isBusy = false
            return
          end
          vim.schedule(function()
            self.isBusy = true
            _G.isBusy = true
            local pio_refresh = require('nvimpio.pio.upkeep').pio_refresh
            pio_refresh(function(success)
              if success then
                OS.notify('PIO checksum: Metadata synced', 'info')
                clangdRestart()
              end
              _G.isBusy = false
              self.isBusy = false
            end, 'PIO checksum: ')
          end)
        end
      end,
    },
  }
  for _, target in ipairs(targets) do watch_file(target, target.cb) end
end

--INFO: telescope settings
-- 1. Check if telescope is ALREADY cached in the environment
-- local is_telescope_loaded = package.loaded['telescope'] ~= nil
--
-- -- 2. Safely capture the Telescope module reference
-- local telescope_ok, telescope = pcall(require, 'telescope')
--
-- if telescope_ok thendiagnostic.lua
--   local dropdown_settings = require('telescope.themes').get_dropdown({
--     borderchars = {
--       prompt = { ' ', ' ', ' ', ' ', ' ', ' ', ' ', ' ' },
--       results = { ' ', ' ', ' ', ' ', ' ', ' ', ' ', ' ' },
--       preview = { '─', '│', '─', '│', '╭', '╮', '╯', '╰' },
--     },
--     prompt_position  = 'top',
--     prompt_prefix    = '🔍 ',
--     selection_caret  = '❯ ',
--     entry_prefix     = '  ',
--     initial_mode     = 'normal',
--     sorting_strategy = 'ascending',
--   })
--
--   -- 3. Now the conditional branches will fire accurately
--   if not is_telescope_loaded then
--     -- Brand new setup
--     telescope.setup({
--       extensions = {
--         ['ui-select'] = dropdown_settings
--       }
--     })
--   else
--     -- Fallback for injecting into an already active runtime profile
--     local ts_config = require('telescope.config')
--     ts_config.values.extensions = ts_config.values.extensions or {}
--     ts_config.values.extensions['ui-select'] = vim.tbl_deep_extend(
--       'force',
--       ts_config.values.extensions['ui-select'] or {},
--       dropdown_settings
--     )
--   end
--
--   pcall(telescope.load_extension, 'ui-select')
-- end
-------------------------------------------------------------------------------------
-- above old working

-- Define your plugin's clean 25-line dropdown configuration explicitly
local dropdown_settings = require('telescope.themes').get_dropdown({
  borderchars      = { ' ', ' ', ' ', ' ', ' ', ' ', ' ', ' ' }, 
  prompt_position  = 'top',
  prompt_prefix    = '🔍 ',
  selection_caret  = '❯ ',
  entry_prefix     = '  ',
  initial_mode     = 'normal',        -- Forces Normal Mode navigation instantly
  layout_config    = { height = 25 }, -- Forces the window height to 25 rows
  sorting_strategy = 'ascending',
})

-- Backup Neovim's original select choice function
local original_select = vim.ui.select

-- THE ROBUST OVERRIDE:
-- Intercepts vim.ui.select when called by your plugin scripts.
-- Bypasses global caches and forces Telescope to render your custom look.
---@diagnostic disable-next-line: duplicate-set-field
vim.ui.select = function(items, opts, on_choice)
  local telescope_ok, telescope = pcall(require, 'telescope')

  if telescope_ok then
    -- If telescope.setup() was never run by the user, initialize it safely now
    local ts_config_ok, ts_config = pcall(require, 'telescope.config')
    if ts_config_ok and (not ts_config.values or vim.tbl_isempty(ts_config.values)) then
      telescope.setup({})
    end

    -- Inject theme parameters directly into Telescope's active call payload block
    opts = vim.tbl_deep_extend('force', opts or {}, {
      theme           = "dropdown",
      layout_strategy = "dropdown",
      telescope       = dropdown_settings
    })

    -- SAFEST RUNTIME ENTRY POINT:
    -- We load telescope-ui-select's native module directly behind Telescope's back.
    -- This bypasses broken load_extension() registries while using Telescope's official
    -- index mapping engine, making it 100% immune to index shifts or saving failures!
    local ext_ok, ui_select_mod = pcall(require, 'telescope._extensions.ui-select.actions')
    if ext_ok and ui_select_mod and type(ui_select_mod.telescope_ui_select) == "function" then
      ui_select_mod.telescope_ui_select(items, opts, on_choice)
      return
    end
  end

  -- Ultimate fallback to native menus if Telescope files are missing or unlinked
  original_select(items, opts, on_choice)
end



-- below new have issue
-------------------------------------------------------------------------------------
-- local dropdown_settings = require('telescope.themes').get_dropdown({
--   borderchars = {
--     prompt  = { ' ', ' ', ' ', ' ', ' ', ' ', ' ', ' ' },
--     results = { ' ', ' ', ' ', ' ', ' ', ' ', ' ', ' ' },
--     preview = { '─', '│', '─', '│', '╭', '╮', '╯', '╰' },
--   },
--   prompt_position  = 'top',
--   prompt_prefix    = '🔍  ',
--   selection_caret  = '❯ ',
--   entry_prefix     = '  ',
--   initial_mode     = 'normal',
--   layout_config    = { height = 25 },
--   sorting_strategy = 'ascending',
-- })
--
-- -- Backup the core native UI selection channel handler
-- local original_select = vim.ui.select
--
-- ---@diagnostic disable-next-line: duplicate-set-field
-- vim.ui.select = function(items, opts, on_choice)
--   local telescope_ok, telescope = pcall(require, 'telescope')
--   if telescope_ok then
--     opts = opts or {}
--
--     -- Convert whatever items table array is passed into readable strings cleanly
--     local item_strings = {}
--     for _, item in ipairs(items) do
--       local formatted = item
--       if opts.format_item then formatted = opts.format_item(item)
--       elseif type(item) == "table" then formatted = item.name or vim.inspect(item) end
--       table.insert(item_strings, tostring(formatted))
--     end
--
--     -- Bypasses extensions completely. Directly creates an instant dropdown picker.
--     local action_state = require('telescope.actions.state')
--     local actions = require('telescope.actions')
--
--     local picker_opts = vim.tbl_deep_extend('force', dropdown_settings, {
--       prompt_title = opts.prompt or "Select Option:",
--       finder = require('telescope.finders').new_table({ results = item_strings }),
--       sorter = require('telescope.sorters').get_generic_fuzzy_sorter({}),
--       attach_mappings = function(prompt_bufnr, _)
--         actions.select_default:replace(function()
--           local selection = action_state.get_selected_entry()
--           actions.close(prompt_bufnr)
--           if selection then on_choice(items[selection.index], selection.index)
--           else on_choice(nil, nil) end
--         end)
--         return true
--       end,
--     })
--
--     require('telescope.pickers').new({}, picker_opts):find()
--   else
--     -- Seamless ultimate fallback if the user has an incomplete runtime profile
--     original_select(items, opts, on_choice)
--   end
-- end

--INFO: 6.  Exported setup function
-------------------------------------------------------------------------------
function M.init(clangd_config)
  OS.notify('PIO Control: initialize', "info")
  require('nvimpio.pio.commands')
  require('nvimpio.pio.metadata') --.load_project_config()
  -- require('nvimpio.pio.diagnostic')


  if clangd_config.support then clangd.init(clangd_config) end

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
