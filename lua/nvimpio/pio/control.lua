local M = {}

local clangdRestart = require('nvimpio.clangd.control').clangdRestart
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
  local ok, data = vim.misc.readFile(path) -- readfile is safer than io.open
  return (ok and type(data) == 'string' and data ~= '') and vim.fn.sha256(data) or ''
end


--INFO:
--stylua: ignore
-------------------------------------------------------------------------------
function M.pio_refresh(callback, from)
  local msg = (type(from)=='string' and from ~= '') and from or 'PIO: '
  vim.misc.notify(msg ..'Config sync ...', "info")

  local function on_done(active_env)
    if active_env then vim.misc.notify(msg .. 'active_env= ' .. active_env, "info") end
    if active_env then vim.pio.fetch_metadata(callback, active_env, from, 1) end
  end
  vim.pio.fetch_config(on_done, from)
  -- local active_env = vim.pio.get_active__env(from)
  -- if active_env then
  --   vim.misc.notify(msg .. 'active_env= ' .. active_env, "info")
  --   vim.pio.fetch_metadata(callback, active_env, from, 1)
  -- end
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
local last_mtime = 0

-- --INFO:
-- --stylua: ignore
-- --1.run_compiledb after platformio.ini changed
-- -----------------------------------------------------------------------------
-- function M.run_compiledb(target)
--   if target.isBusy then return end
--   if _G.metadata.isBusy == true then return end
--
--   local env = vim.pio.get_active__env()
--   if not env then return end
--   target.isBusy = true
--     vim.misc.notify('PIO platformio.ini change: compiledb update ...', "info")
--     vim.system({ 'pio', 'run', '-t', 'compiledb', '-s', '-e', env }, { text = true }, function(obj)
--       vim.schedule(function()
--         target.isBusy = false
--
--         if obj.code == 0 then
--           vim.schedule(function ()
--             M.pio_refresh(function()
--               vim.misc.notify('PIO platformio.ini change: compiledb update Success', "info")
--               clangdRestart()
--             end, 'PIO platformio.ini  change: ')
--           end)
--         else
--           local err = (obj.stderr and obj.stderr ~= '') and obj.stderr or 'Check PIO logs'
--           vim.misc.notify('PIO Build Failed: ' .. err, "error")
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

  local handle = uv.new_fs_event()
  if not handle then return end

  handle:start(folder_path, {recursive = false}, function(err, filename, events)
    if err then return end
    if events and not (events.change or events["rename"]) then return end
    if _G.metadata.isBusy then return end
    if target.isBusy or (filename and filename ~= target_filename) then return end

    -- local f = io.open(target.path, "r")
    -- if f then f:close()
    -- else return end -- Not readable (protected, locked, or missing)

    if not uv.fs_access(target.path, 'R') then return end

    -- Protected Execution
    local ok, result = pcall(function()
      local stat = uv.fs_stat(target.path)
      if not stat or stat.mtime.sec <= last_mtime then return end

      vim.schedule(function()
        if debounce_timer then
          debounce_timer:stop()
          local retries = 0
          local max_retries = 15 -- 15 seconds max wait

          local function attempt_callback()
            -- Check if busy (checks both local M and global _G)
            if target.isBusy then --or (_G.metadata and _G.metadata.isBusy) then
              if retries < max_retries then
                retries = retries + 1
                debounce_timer:start(1000, 0, vim.schedule_wrap(attempt_callback))
                return
              end
              vim.misc.notify('PIO Control: Sync timed out (busy)', "error")
              return
            end

            -- Final validation & run
            local final_stat = uv.fs_stat(target.path)
            if final_stat and final_stat.mtime.sec > last_mtime then
              last_mtime = final_stat.mtime.sec
              callback(target)
            end
          end

          debounce_timer:start(500, 0, vim.schedule_wrap(attempt_callback))
        end
      end)
    end)

    if not ok then
      vim.schedule(function()
        vim.misc.notify('PIO Control: Error; ' .. tostring(result), "error")
      end)
    end
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
  if next(M.watcher_handles) then M.stop_watchers() end

  local project_root = vim.uv.cwd() -- Use dynamic CWD instead of hardcoded path

  local targets = {
    { -- watcher for platformio.ini
      name = 'ini',
      isBusy = false,
      last_hash = '',
      path = vim.misc.joinPath(project_root, 'platformio.ini'),
      cb = function(self)
        if self.isBusy then return end
        _G.metadata.isBusy = true
        self.isBusy = true
        -- if _G.metadata.isBusy then return end
        local new_hash = get_hash(self.path) or ''
        if new_hash and new_hash ~= self.last_hash then
          self.last_hash = new_hash
          local env = vim.pio.get_active__env('PIO platformio.ini change: ')
          if not env then
            self.isBusy = false
            _G.metadata.isBusy = false
            return
          end
          vim.misc.notify('PIO platformio.ini change: compiledb update ...', "info")
          vim.system({ 'pio', 'run', '-t', 'compiledb', '-s', '-e', env }, { text = true }, function(obj)
            vim.schedule(function()
              if obj.code == 0 then
                -- vim.schedule(function ()
                  M.pio_refresh(function()
                    vim.clangd.getUnknownArgs()
                    vim.misc.notify('PIO platformio.ini change: compiledb update Success', "info")
                    -- clangdRestart()
                  end, 'PIO platformio.ini  change: ')
                -- end)
              else
                local err = (obj.stderr and obj.stderr ~= '') and obj.stderr or 'Check PIO logs'
                vim.misc.notify('PIO platformio.ini change: Build Failed: ' .. err, "error")
              end
              self.isBusy = false
              _G.metadata.isBusy = false
            end)
          end)
        end
      end,
    },
    { -- watcher for ./.pio/build/projct.checksum
      name = 'checksum',
      isBusy = false,
      path = vim.misc.joinPath(project_root, '.pio', 'build', 'project.checksum'), --checksum_path
      cb = function(self)
        if self.isBusy then return end
        _G.metadata.isBusy = true
        self.isBusy = true
        -- if _G.metadata.isBusy then return end
        local ok, current_checksum = vim.misc.readFile(self.path)
        -- Check if we should exit early
        if ok and type(current_checksum) == 'string' and current_checksum ~= '' then
          if current_checksum == _G.metadata.last_projectChecksum then
            self.isBusy = false
            _G.metadata.isBusy = false
            return
          end
          -- vim.defer_fn(function ()
          vim.schedule(function ()
            M.pio_refresh(function()
              self.isBusy = false
              _G.metadata.isBusy = false
              vim.misc.notify('PIO checksum: Metadata synced', "info")
              clangdRestart()
            end, 'PIO checksum: ')
          end)
          -- end, 500)
        end
      end
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
function M.init(clangd)
  vim.g.platformioRootDir = vim.fn.getcwd()

  vim.pio = require('nvimpio.pio.upkeep')
  vim.misc = require('nvimpio.utils.misc')
  vim.clangd = require('nvimpio.clangd.control')

  vim.misc.notify('PIO Control: initialize', "info")

  require('nvimpio.pio.metadata') --.load_project_config()

  if clangd.support then vim.clangd.init(clangd) end

  -- Always start the watcher so it can catch a future 'pio init'
  M.start_watchers()

  -- If the file already exists, do an initial sync
  if vim.fn.filereadable(vim.uv.cwd() .. '/platformio.ini') == 1 then
    _G.metadata.isBusy = true
    M.pio_refresh(function()
      boilerplate.core_dir = _G.metadata.core_dir
      _G.metadata.isBusy = false
    end, 'PIO start: ')
  end
end

return M
