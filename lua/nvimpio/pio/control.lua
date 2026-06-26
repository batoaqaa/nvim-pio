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
                  require('nvimpio.clangd.control').restart()
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

          -- AUTO-DETECTION RADAR: 
          -- Check if the incoming items look like a checkbox toggle array (has choice.action or choice.id)
          local is_checkbox_menu = type(clicked_item) == "table" and (clicked_item.action ~= nil or clicked_item.id ~= nil)

          if is_checkbox_menu then
            -- CASE A: Persistent Checkbox List -> KEEP WINDOW OPEN, REDRAW IN PLACE
            on_choice(clicked_item, clicked_index)

            local current_picker = action_state.get_current_picker(prompt_bufnr)
            if current_picker then
              current_picker:refresh(make_entry_list(), { reset_prompt = false })
              vim.api.nvim_win_set_cursor(current_picker.results_win, { clicked_index, 0 })
            end
          else
            -- CASE B: Standard Selection Menu -> CLOSE WINDOW INSTANTLY AND JUMP
            actions.close(prompt_bufnr)
            vim.schedule(function()
              on_choice(clicked_item, clicked_index)
            end)
          end
        end)
        return true
      end,
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
  OS.notify('PIO Control: initialize', "info")
  -- vim.env.PATH = OS.project_dir .. OS.path_sep .. vim.env.PATH
  -- vim.env.PLATFORMIO_BUILD_FLAGS="-std=gnu23 -std=gnu++23"
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
