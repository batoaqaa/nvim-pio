local M = {}

--stylua: ignore start
local clangd = require('nvimpio.clangd.control')
local pio = require('nvimpio.pio.upkeep')
local misc = require('nvimpio.utils.misc')
local clangdRestart = clangd.clangdRestart
local boilerplate = require('nvimpio.boilerplate')
local boilerplate_gen = boilerplate.boilerplate_gen

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
    if target.isBusy or (_G.metadata and _G.metadata.isBusy) then return end
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
            target.isBusy = true
            if _G.metadata then _G.metadata.isBusy = true end

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
          if _G.metadata then _G.metadata.isBusy = false end
          return
        end

        self.last_hash = new_hash
        local meta = require('nvimpio.pio.metadata')
        local env, _ = meta.get_active_env('PIO platformio.ini change:')
        -- local env = pio.get_active_env('PIO platformio.ini change:')

        if not env then
          self.isBusy = false
          if _G.metadata then _G.metadata.isBusy = false end
          return
        end

        misc.notify('PIO platformio.ini change: compiledb update ...', 'info')
        vim.system({ 'pio', 'run', '-t', 'compiledb', '-s', '-e', env }, { text = true }, function(obj)
          vim.schedule(function()
            if obj.code == 0 then
              misc.notify('PIO platformio.ini change: compiledb update Success', 'info')
              local pio_refresh = require('nvimpio.pio.upkeep').pio_refresh
              pio_refresh(function(success)
                if success then
                  -- clangd.getUnknownArgsCli('PIO platformio.ini  change: ')
                  if _G.metadata then _G.metadata.isBusy = false end
                end
                self.isBusy = false
                -- clangdRestart()
              end, 'PIO platformio.ini  change: ')
            else
              local err = (obj.stderr and obj.stderr ~= '') and obj.stderr or 'Check PIO logs'
              misc.notify('PIO platformio.ini change: Build Failed: ' .. err, 'error')
              self.isBusy = false
              if _G.metadata then _G.metadata.isBusy = false end
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
            if _G.metadata then _G.metadata.isBusy = false end
            return
          end
          vim.schedule(function()
            local pio_refresh = require('nvimpio.pio.upkeep').pio_refresh
            pio_refresh(function(success)
              if success then
                misc.notify('PIO checksum: Metadata synced', 'info')
                clangdRestart()
              end
              if _G.metadata then _G.metadata.isBusy = false end
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
local is_telescope_loaded = package.loaded['telescope'] ~= nil

-- 2. Safely capture the Telescope module reference
local telescope_ok, telescope = pcall(require, 'telescope')

if telescope_ok then
  local dropdown_settings = require('telescope.themes').get_dropdown({
    borderchars = {
      prompt = { ' ', ' ', ' ', ' ', ' ', ' ', ' ', ' ' },
      results = { ' ', ' ', ' ', ' ', ' ', ' ', ' ', ' ' },
      preview = { '─', '│', '─', '│', '╭', '╮', '╯', '╰' },
    },
    prompt_position  = 'top',
    prompt_prefix    = '🔍 ',
    selection_caret  = '❯ ',
    entry_prefix     = '  ',
    initial_mode     = 'normal',
    sorting_strategy = 'ascending',
  })

  -- 3. Now the conditional branches will fire accurately
  if not is_telescope_loaded then
    -- Brand new setup
    telescope.setup({
      extensions = {
        ['ui-select'] = dropdown_settings
      }
    })
  else
    -- Fallback for injecting into an already active runtime profile
    local ts_config = require('telescope.config')
    ts_config.values.extensions = ts_config.values.extensions or {}
    ts_config.values.extensions['ui-select'] = vim.tbl_deep_extend(
      'force',
      ts_config.values.extensions['ui-select'] or {},
      dropdown_settings
    )
  end

  pcall(telescope.load_extension, 'ui-select')
end


--INFO: 6.  Exported setup function
-------------------------------------------------------------------------------
function M.init(clangd_config)
  misc.notify('PIO Control: initialize', "info")
  require('nvimpio.pio.commands')
  require('nvimpio.pio.metadata') --.load_project_config()
  -- require('nvimpio.pio.diagnostic')

  if clangd_config.support then clangd.init(clangd_config) end







local term_buf = nil

vim.keymap.set({'n', 't'}, '<leader>st', function()
  vim.cmd.vnew()
  vim.cmd.term()
  vim.cmd.wincmd("J")
  vim.api.nvim_win_set_height(0,5)
end, { desc = "Toggle true full-buffer terminal" })



vim.keymap.set({'n', 't'}, '<leader>tf', function()
  -- 1. Safely exit terminal mode if you are currently typing in it
  if vim.api.nvim_get_mode().mode == 't' then
    vim.cmd([[raw_mode == 't' and <C-\><C-n>]])
  end

  -- 2. If the terminal is open and visible on screen, hide it by switching to your last code file
  if term_buf and vim.api.nvim_buf_is_valid(term_buf) and vim.fn.bufwinnr(term_buf) ~= -1 then
    vim.cmd("b#")
    return
  end

  -- 3. If the terminal already exists in memory but is hidden, bring it into your active file window
  if term_buf and vim.api.nvim_buf_is_valid(term_buf) then
    vim.api.nvim_set_current_buf(term_buf)
  else
    -- 4. Create a fresh terminal buffer inside your current window (keeps neo-tree/nvim-tree perfectly open)
    vim.cmd("terminal")
    term_buf = vim.api.nvim_get_current_buf()

    -- Strip line numbers and set styles to match a clean terminal pane
    vim.cmd("setlocal nonumber norelativenumber signcolumn=no")
  end

  -- Automatically drop your cursor into typing mode
  vim.cmd("startinsert")
end, { desc = "Toggle true full-buffer terminal" })

vim.keymap.set('n', '<leader>tl', function()
  local tabs = vim.api.nvim_list_tabpages()
  local current_tab = vim.api.nvim_get_current_tabpage()
  local choices = {}
  local current_idx = 1

  for i, tab in ipairs(tabs) do
    if tab == current_tab then
      current_idx = i
    end

    -- 1. Try to fetch the custom toggleterm title we saved inside the tab
    local success, custom_title = pcall(vim.api.nvim_tabpage_get_var, tab, "tab_title")
    local display_name = ""

    if success and custom_title then
      display_name = custom_title
    else
      -- 2. Fallback to extracting the active buffer name if no custom tab title exists
      local win = vim.api.nvim_tabpage_get_win(tab)
      local buf = vim.api.nvim_win_get_buf(win)
      local buf_name = vim.api.nvim_buf_get_name(buf)

      if buf_name ~= "" then
        if buf_name:match("toggleterm") or vim.bo[buf].buftype == "terminal" then
          display_name = "   Terminal"
        else
          display_name = "   " .. vim.fn.fnamemodify(buf_name, ":t")
        end
      else
        display_name = "[No Name]"
      end

      -- Append modified marker if file has unsaved changes
      if vim.bo[buf].modified then
        display_name = display_name .. " ◉"
      end
    end

    local label = string.format("%d: Tab %d (%s)", i, i, display_name)
    table.insert(choices, label)
  end

  if #choices <= 1 then
    vim.notify("Only one tab page open!", vim.log.levels.INFO)
    return
  end

  vim.ui.select(choices, {
    prompt = '   Jump to Tab Page:',
    kind = 'tabpage',
    default = choices[current_idx],
  }, function(choice)
    if choice then
      local tab_idx = choice:match("^(%d+):")
      if tab_idx then
        vim.cmd("tabnext " .. tab_idx)
      end
    end
  end)
end, { desc = "Interactive Tab List Menu" })





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
