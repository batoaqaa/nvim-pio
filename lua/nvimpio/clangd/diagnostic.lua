--- stylua: ignore start
local M = {}

M.manual_blocked_codes = {}
M.removed_flags = {}
M.session_discovered_codes = {}

-- Defined exactly once to fix the 'redefined-local' linter warning
local markers = { 'platformio.ini', '.git' }

-- 1. Unified database path resolver (Accepts bufnr OR raw absolute path string)
local function get_db_path(source)
  local f = ''

  if type(source) == 'string' then
    -- It's a raw file path string (Headless route)
    f = source
  elseif type(source) == 'number' or source == nil then
    -- It's a buffer ID or nil (Live UI route)
    local bufnr = source or vim.api.nvim_get_current_buf()
    f = vim.api.nvim_buf_get_name(bufnr)
  end

  -- Resolve workspace root based on the discovered file path
  local root_dir = (f ~= '') and vim.fs.root(f, markers) or nil

  -- Fallback logic to protect loose files
  if not root_dir and (type(source) == 'number' or source == nil) then
    local bufnr = source or vim.api.nvim_get_current_buf()
    local clients = vim.lsp.get_clients({ bufnr = bufnr })
    if #clients > 0 then
      root_dir = clients[1].config.root_dir
    end
  end

  root_dir = root_dir or vim.uv.cwd()
  return vim.fs.joinpath(root_dir, '.filter.json')
end

-- 2. Load persistent json arrays from disk
local function load_db(bufnr)
  M.manual_blocked_codes = {}
  local f = io.open(get_db_path(bufnr), 'rb')
  if not f then
    return
  end
  local raw = f:read('*all')
  f:close()
  if raw and raw ~= '' then
    local ok, data = pcall(vim.json.decode, raw)
    if ok and data and type(data.codes) == 'table' then
      for k, v in pairs(data.codes) do
        local s = (type(k) == 'string') and k or v
        if type(s) == 'string' and s ~= '' then
          M.manual_blocked_codes[s] = true
          M.session_discovered_codes[s] = true
        end
      end
    end
  end
end

-- 3. Save selections straight down to disk
local function save_db(bufnr)
  local f = io.open(get_db_path(bufnr), 'wb')
  if f then
    local payload = { codes = M.manual_blocked_codes, flags = M.removed_flags }
    local pretty = require('nvimpio.utils.misc').jsonFormat(payload)
    f:write(pretty)
    f:close()
  end
end

-- ===================================================================
-- 4. 🟢 ENGINE PATH A: Clean Project-Wide Toolchain Flags (Rigid Root)
-- ===================================================================
function M.clean_project_wide_flags(project_root, diagnostics)
  if not diagnostics or #diagnostics == 0 then
    return
  end

  local boiler = require('nvimpio.boilerplate')
  boiler.remove = boiler.remove or {}

  local flags_updated = false
  for _, diag in ipairs(diagnostics) do
    local code = diag.code
    local msg = diag.message or ''

    -- Identify toolchain driver errors using generic syntax rules
    local is_drv = false
    if type(code) == 'string' then
      is_drv = code:match('^drv_') or code:match('^fatal_') or msg:lower():match('argument')
    end

    if is_drv then
      local flag = msg:match('(%-[fmWOdsx][%w%-%.%*]+)')
      if flag and not M.removed_flags[flag] then
        table.insert(boiler.remove, flag)
        M.removed_flags[flag] = true
        flags_updated = true
      end
    end
  end

  -- Write updates straight to disk if a new bad compiler argument was caught
  if flags_updated then
    local filter_db_path = vim.fs.joinpath(project_root, '.filter.json')
    local f = io.open(filter_db_path, 'wb')
    if f then
      local payload = { codes = M.manual_blocked_codes, flags = M.removed_flags }
      f:write(require('nvimpio.utils.misc').jsonFormat(payload))
      f:close()
    end

    local boilerplate_gen = boiler.boilerplate_gen
    if boilerplate_gen then
      pcall(boilerplate_gen, '.clangd', project_root)
    end
  end
end
-- function M.clean_file_path_pipeline(absolute_file_path, diagnostics)
--   -- print(absolute_file_path)
--   if not absolute_file_path or absolute_file_path == '' then
--     return {}
--   end
--   diagnostics = diagnostics or {}
--
--   local filter_db_path = get_db_path(absolute_file_path)
--   local project_root = vim.fs.dirname(filter_db_path) -- Derive root folder directly from db location
--
--   -- Isolated disk lookup matching standard JSON loader
--   local manual_blocked = {}
--   local db_file = io.open(filter_db_path, 'rb')
--   if db_file then
--     local raw = db_file:read('*all')
--     db_file:close()
--     if raw and raw ~= '' then
--       local ok, data = pcall(vim.json.decode, raw)
--       if ok and data and type(data.codes) == 'table' then
--         for k, v in pairs(data.codes) do
--           local s = (type(k) == 'string') and k or v
--           if type(s) == 'string' and s ~= '' then
--             manual_blocked[s] = true
--           end
--         end
--       end
--     end
--   end
--
--   local boiler = require('nvimpio.boilerplate')
--   boiler.remove = {}
--
--   local clean_diagnostics = {}
--   for _, diag in ipairs(diagnostics) do
--     local keep = true
--     local code = diag.code
--     local msg = diag.message or ''
--
--     local is_drv = false
--     if type(code) == 'string' then
--       local lower_code = code:lower()
--       local lower_msg = msg:lower()
--       local has_driver_prefix = lower_code:match('^drv_') or lower_code:match('^fatal_')
--       local has_flag_keywords = lower_msg:match('argument') or lower_msg:match('unknown flag') or lower_msg:match('command line option')
--
--       if has_driver_prefix or has_flag_keywords then
--         is_drv = true
--       end
--     end
--
--     if is_drv then
--       keep = false
--       -- local f = msg:match('(%-[%w%-%.%*]+)')
--       -- [fmWOdsx] represents the universal language categories used by the entire GCC and Clang compiler family globally
--       -- f: Compiler Features / Optimizations (e.g., -fexceptions, -fno-rtti)
--       -- m: Machine / Architecture Directives (e.g., -mlongcalls, -mthumb)
--       -- W: Warning parameters (e.g., -Wno-deprecated, -Wsign-compare)
--       -- O: Optimization Levels (e.g., -Os, -O2)
--       -- d / s / x: Internal Debugging, Standards, and Language flags (e.g., -ggdb, -std=c++17, -xc++)
--       -- Starts strictly with a hyphen followed by a valid single-letter flag category indicator (f, m, W, O, d, s, x)
--       local f = msg:match('(%-[fmWOdsx][%w%-%.%*]+)')
--       if f then
--         table.insert(boiler.remove, f)
--         M.removed_flags[f] = true
--       end
--     elseif code and manual_blocked[code] then
--       keep = false
--     end
--
--     if code and type(code) == 'string' and code ~= '' and not is_drv then
--       M.session_discovered_codes[code] = true
--     end
--
--     if keep then
--       table.insert(clean_diagnostics, diag)
--     end
--   end
--
--   local boilerplate_gen = boiler.boilerplate_gen
--   if boilerplate_gen then
--     pcall(boilerplate_gen, '.clangd', project_root)
--   end
--
--   return clean_diagnostics
-- end

-- ===================================================================
-- 5. 🟢 ENGINE PATH B: Clean Source Code File Diagnostics (Pure Files)
-- ===================================================================
function M.clean_file_path_pipeline(absolute_file_path, diagnostics)
  if not diagnostics or #diagnostics == 0 then
    return diagnostics
  end

  local project_root = vim.fs.root(absolute_file_path, { 'platformio.ini', '.git' }) or vim.uv.cwd()
  local filter_db_path = vim.fs.joinpath(project_root, '.filter.json')

  -- Read the project-specific blocked codes dictionary map
  local manual_blocked = {}
  local db_file = io.open(filter_db_path, 'rb')
  if db_file then
    local raw = db_file:read('*all')
    db_file:close()
    if raw and raw ~= '' then
      local ok, data = pcall(vim.json.decode, raw)
      if ok and data and type(data.codes) == 'table' then
        for k, v in pairs(data.codes) do
          local s = (type(k) == 'string') and k or v
          if type(s) == 'string' and s ~= '' then
            manual_blocked[s] = true
          end
        end
      end
    end
  end

  local clean_diagnostics = {}
  for _, diag in ipairs(diagnostics) do
    local code = diag.code
    if not (code and manual_blocked[code]) then
      table.insert(clean_diagnostics, diag)
      if code and type(code) == 'string' and code ~= '' then
        M.session_discovered_codes[code] = true
      end
    end
  end

  return clean_diagnostics
end
-- function M.clean_diagnostics_pipeline(diagnostics, bufnr)
--   bufnr = bufnr or vim.api.nvim_get_current_buf()
--   local absolute_file_path = vim.api.nvim_buf_get_name(bufnr)
--   print(absolute_file_path)
--   return M.clean_file_path_pipeline(absolute_file_path, diagnostics)
-- end

-- ===================================================================
-- 6. INTERACTIVE DYNAMIC CHECKBOX PICKER
-- ===================================================================
function M.manage_file_diagnostics_interactive()
  local bufnr = vim.api.nvim_get_current_buf()
  load_db(bufnr)
  local items = {}

  if next(M.manual_blocked_codes) then
    table.insert(items, { action = 'reset', text = '💥 Reset All Filters' })
  end

  local raw_diagnostics = vim.diagnostic.get(bufnr)
  for _, d in ipairs(raw_diagnostics) do
    local c = d.code or ''
    local msg = d.message or ''
    local is_automated_arg = c:match('^drv_') or c:match('^fatal_')
    local is_flag_err = msg:match('argument') or msg:match('unknown flag')

    if c ~= '' and not is_automated_arg and not is_flag_err then
      M.session_discovered_codes[c] = true
    end
  end

  local registered_keys = {}
  for k, _ in pairs(M.session_discovered_codes) do
    table.insert(registered_keys, k)
  end
  table.sort(registered_keys)

  for _, c in ipairs(registered_keys) do
    local is_blocked = M.manual_blocked_codes[c]
    local mark = is_blocked and '[*]' or '[ ]'
    local status = is_blocked and 'Restore' or 'Suppress'
    table.insert(items, {
      action = is_blocked and 'unblock' or 'block',
      id = c,
      text = string.format('  %s %s Code: [%s]', mark, status, c),
    })
  end

  for f, _ in pairs(M.removed_flags) do
    table.insert(items, { action = 'none', text = '  [-] ⚙️ [AUTOMATED]: ' .. f })
  end

  if #items == 0 then
    vim.notify('✅ Clean Slate: No active lints.', vim.log.levels.INFO)
    return
  end

  vim.ui.select(items, {
    prompt = 'Filter Panel (Toggle items, press Esc to Save & Apply)',
    format_item = function(item)
      return item.text
    end,
  }, function(choice)
    if not choice then
      save_db(bufnr)
      vim.schedule(function()
        if vim.api.nvim_buf_is_valid(bufnr) then
          vim.api.nvim_buf_call(bufnr, function()
            local old = vim.o.shortmess
            vim.o.shortmess = old .. 'F'
            vim.cmd('silent! checktime')
            vim.cmd('silent! edit!')
            vim.o.shortmess = old
          end)
        end
      end)
      return
    end

    if choice.action == 'none' then
      M.manage_file_diagnostics_interactive()
      return
    end

    if choice.action == 'reset' then
      M.manual_blocked_codes = {}
    elseif choice.action == 'block' then
      M.manual_blocked_codes[choice.id] = true
    elseif choice.action == 'unblock' then
      M.manual_blocked_codes[choice.id] = nil
    end

    save_db(bufnr)
    M.manage_file_diagnostics_interactive()
  end)
end

-------------------------------------------------------------
local boilerplate = require('nvimpio.boilerplate')
local boilerplate_gen = boilerplate.boilerplate_gen

local target_file = vim.fs.find(function(name)
  return name:match('%.cpp$') or name:match('%.c$')
end, { limit = 1, path = vim.uv.cwd() .. '/src' })[1]

if not target_file then
  boilerplate_gen([[main.cpp]], vim.uv.cwd() .. '/src')
  boilerplate_gen([[main.hpp]], vim.uv.cwd() .. '/include')
  target_file = vim.uv.cwd() .. '/src/main.cpp'
end

if target_file then
  -- 1. Use Neovim's URI converter to locate the hidden memory buffer for the path
  local target_uri = vim.uri_from_fname(target_file)
  local target_bufnr = vim.uri_to_bufnr(target_uri)
  -- 2. Query Neovim's diagnostic tracking pool for this specific buffer
  local raw_diagnostics = vim.diagnostic.get(target_bufnr)
  -- 3. Feed the results straight into your clean file pipeline core
  print(vim.inspect(raw_diagnostics))
  M.clean_file_path_pipeline(target_file, raw_diagnostics)
end

-- stylua: ignore end
return M
