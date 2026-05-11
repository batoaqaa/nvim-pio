local M = {}

local clangd = require('nvimpio.clangd.control')
local pio = require('nvimpio.pio.upkeep')
local misc = require('nvimpio.utils.misc')
local clangdRestart = clangd.clangdRestart
local boilerplate = require('nvimpio.boilerplate')
local boilerplate_gen = boilerplate.boilerplate_gen

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
--=============================================================================
--  watchers setup
--=============================================================================
-- Ensure this is at the TOP of your file, outside any functions
-------------------------------------------------------------------------------
local uv = vim.uv or vim.loop
M.watcher_handles = {}
local debounce_timer = uv.new_timer()

-- --INFO:
-- --stylua: ignore
-- --1.run_compiledb after platformio.ini changed
-- -----------------------------------------------------------------------------
-- function M.run_compiledb(target)
--   if target.isBusy then return end
--   if _G.metadata.isBusy == true then return end
--
--   local env = pio.get_active__env()
--   if not env then return end
--   target.isBusy = true
--     misc.notify('PIO platformio.ini change: compiledb update ...', "info")
--     vim.system({ 'pio', 'run', '-t', 'compiledb', '-s', '-e', env }, { text = true }, function(obj)
--       vim.schedule(function()
--         target.isBusy = false
--
--         if obj.code == 0 then
--           vim.schedule(function ()
--             local pio_refresh = require('nvimpio.pio.upkeep').pio_refresh
--             pio_refresh(function()
--               misc.notify('PIO platformio.ini change: compiledb update Success', "info")
--               clangdRestart()
--             end, 'PIO platformio.ini  change: ')
--           end)
--         else
--           local err = (obj.stderr and obj.stderr ~= '') and obj.stderr or 'Check PIO logs'
--           misc.notify('PIO Build Failed: ' .. err, "error")
--         end
--         _G.metadata.isBusy = false
--       end)
--     end)
-- end
--
--INFO:
--stylua: ignore
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
--stylua: ignore
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
--stylua: ignore
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
    -- Protected Execution
    -- local ok, result = pcall(function()
    --   local stat = uv.fs_stat(target.path)
    --   if not stat or stat.mtime.sec <= last_mtime then return end
    --
    --   vim.schedule(function()
    --     if debounce_timer then
    --       debounce_timer:stop()
    --       local retries = 0
    --       local max_retries = 15 -- 15 seconds max wait
    --
    --       local function attempt_callback()
    --         -- Check if busy (checks both local M and global _G)
    --         if target.isBusy then --or (_G.metadata and _G.metadata.isBusy) then
    --           if retries < max_retries then
    --             retries = retries + 1
    --             debounce_timer:start(1000, 0, vim.schedule_wrap(attempt_callback))
    --             return
    --           end
    --           misc.notify('PIO Control: Sync timed out (busy)', "error")
    --           return
    --         end
    --
    --         -- Final validation & run
    --         local final_stat = uv.fs_stat(target.path)
    --         if final_stat and final_stat.mtime.sec > last_mtime then
    --           last_mtime = final_stat.mtime.sec
    --           callback(target)
    --         end
    --       end
    --
    --       debounce_timer:start(500, 0, vim.schedule_wrap(attempt_callback))
    --     end
    --   end)
    -- end)
    --
    -- if not ok then
    --   vim.schedule(function()
    --     misc.notify('PIO Control: Error; ' .. tostring(result), "error")
    --   end)
    -- end
  end)

  table.insert(M.watcher_handles, handle)
  return handle
end

--INFO:
--stylua: ignore
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
      path = misc.joinPath(project_root, 'platformio.ini'),
      cb = function(self)
        -- if self.isBusy then
        --   return
        -- end
        -- _G.metadata.isBusy = true
        -- self.isBusy = true
        -- if _G.metadata.isBusy then return end

        -- If no real change, unlock immediately and exit
        local new_hash = get_hash(self.path) or ''
        if new_hash == self.last_hash then
          self.isBusy = false
          if _G.metadata then _G.metadata.isBusy = false end
          return
        end

        self.last_hash = new_hash
        local env = pio.get_active__env('PIO platformio.ini change:')

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
              -- vim.schedule(function ()
              local pio_refresh = require('nvimpio.pio.upkeep').pio_refresh
              pio_refresh(function()
                clangd.getUnknownArgs()
                self.isBusy = false
                if _G.metadata then _G.metadata.isBusy = false end
                -- clangdRestart()
              end, 'PIO platformio.ini  change: ')
              -- end)
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
      path = misc.joinPath(project_root, '.pio', 'build', 'project.checksum'), --checksum_path
      cb = function(self)
        -- if self.isBusy then
        --   return
        -- end
        -- _G.metadata.isBusy = true
        -- self.isBusy = true
        -- if _G.metadata.isBusy then return end
        local ok, current_checksum = misc.readFile(self.path)
        -- Check if we should exit early
        if ok and type(current_checksum) == 'string' and current_checksum ~= '' then
          if current_checksum == _G.metadata.last_projectChecksum then
            self.isBusy = false
            if _G.metadata then _G.metadata.isBusy = false end
            return
          end
          -- vim.defer_fn(function ()
          vim.schedule(function()
            local pio_refresh = require('nvimpio.pio.upkeep').pio_refresh
            pio_refresh(function()
              self.isBusy = false
              if _G.metadata then _G.metadata.isBusy = false end
              misc.notify('PIO checksum: Metadata synced', 'info')
              clangdRestart()
            end, 'PIO checksum: ')
          end)
          -- end, 500)
        end
      end,
    },
  }

  for _, target in ipairs(targets) do
    --[[ wrap the callback in a small anonymous function,
        so it passes the target (self) back into it.]]
    watch_file(target, target.cb)
  end
end

--INFO: 6.  Exported setup function
--stylua: ignore
-------------------------------------------------------------------------------
function M.init(clangd_config)
  -- pio = require('nvimpio.pio.upkeep')
  -- misc = require('nvimpio.utils.misc')
  -- clangd = require('nvimpio.clangd.control')

  require('nvimpio.pio.commands')
  misc.notify('PIO Control: initialize', "info")

  require('nvimpio.pio.metadata') --.load_project_config()

  if clangd_config.support then clangd.init(clangd_config) end

  -- Always start the watcher so it can catch a future 'pio init'
  M.start_watchers()

  -- If the file already exists, do an initial sync
  if vim.fn.filereadable(vim.uv.cwd() .. '/platformio.ini') == 1 then
    _G.metadata.isBusy = true
    local pio_refresh = require('nvimpio.pio.upkeep').pio_refresh
    pio_refresh(function()
      boilerplate.core_dir = _G.metadata.core_dir
      clangd.getUnknownArgs()
      boilerplate_gen([[.clang-format]], vim.g.platformioRootDir)
      _G.metadata.isBusy = false
    end, 'PIO start: ')
  end
end

return M
