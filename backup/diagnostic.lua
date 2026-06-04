--- stylua: ignore start
local M = {}
local misc = require('nvimpio.utils.misc')

-- State preservation layers track cross-file automated sessions safely
M.manual_blocked_codes = M.manual_blocked_codes or {}
M.removed_flags = M.removed_flags or {}
M.session_discovered_codes = M.session_discovered_codes or {}

local markers = { 'platformio.ini', '.git' }

-- ===================================================================
-- 📁 STORAGE CONTROLLER (PURE DIRECT DISK STREAM ENGINE)
-- ===================================================================
local function get_db_path(source)
  local f = ''
  if type(source) == 'string' then
    f = source
  elseif type(source) == 'number' or source == nil then
    local bufnr = source or vim.api.nvim_get_current_buf()
    f = vim.api.nvim_buf_get_name(bufnr)
  end

  local root_dir = (f ~= '') and vim.fs.root(f, markers) or nil
  if not root_dir or root_dir:match('%.platformio') then
    local cwd_path = vim.uv.cwd()
    if type(cwd_path) == 'string' and cwd_path ~= '' then
      root_dir = vim.fs.root(cwd_path, markers) or cwd_path
    else
      root_dir = '.'
    end
  end
  return vim.fs.joinpath(root_dir, '.filter.json')
end

local function load_db(db_path)
  -- Automatically seed a default configuration template if file is missing
  local stat = vim.uv.fs_stat(db_path)
  if not stat then
    local default_template = { codes = {}, flags = {} }
    local f = io.open(db_path, 'wb')
    if f then
      f:write(misc.jsonFormat(default_template))
      f:close()
    end
    return default_template
  end

  local file = io.open(db_path, 'r')
  if not file then
    return { codes = {}, flags = {} }
  end
  local content = file:read('*all')
  file:close()

  local ok, data = pcall(vim.json.decode, content)
  if ok and data then
    data.codes = data.codes or {}
    data.flags = data.flags or {}
    return data
  end
  return { codes = {}, flags = {} }
end

local function save_filter_database(project_root, active_codes, active_flags)
  local db_path = get_db_path(project_root)
  local f = io.open(db_path, 'wb')
  if f then
    local payload = { codes = active_codes, flags = active_flags }
    f:write(misc.jsonFormat(payload))
    f:close()
  end

  local boiler = require('nvimpio.boilerplate')
  if boiler and boiler.boilerplate_gen then
    pcall(boiler.boilerplate_gen, '.clangd', project_root)
  end
end

-- ===================================================================
-- 🛠️ RUNTIME DIAGNOSTIC INTERCEPTORS (THE RE-ROUTING GATEWAYS)
-- ===================================================================
function M.clean_project_wide_flags(project_root, diagnostics)
  if not diagnostics or #diagnostics == 0 then
    return
  end

  local db_path = get_db_path(project_root)
  local db = load_db(db_path)
  local updated = false

  for _, diag in ipairs(diagnostics) do
    local code = diag.code
    local msg = diag.message or ''
    if type(code) == 'string' and (code:match('^drv_') or code:match('^fatal_') or msg:lower():match('argument')) then
      local flag = msg:match('(%-[fmWOdsx][%w%-%.%*]+)')
      if flag and not db.flags[flag] then
        db.flags[flag] = true
        M.removed_flags[flag] = true -- Keep RAM cache synced
        updated = true
      end
    end
  end

  if updated then
    save_filter_database(project_root, db.codes, M.removed_flags)
  end
end

function M.clean_file_path_pipeline(absolute_file_path, diagnostics)
  if not diagnostics or #diagnostics == 0 then
    return diagnostics
  end

  local filter_db_path = get_db_path(absolute_file_path)
  local project_root = vim.fs.dirname(filter_db_path)
  local db = load_db(filter_db_path)

  -- Re-hydrate memory pointers for cross-file consistency
  M.manual_blocked_codes = db.codes
  for flag, state in pairs(db.flags) do
    M.removed_flags[flag] = state
  end

  local clean_list = {}
  for _, diag in ipairs(diagnostics) do
    local keep = true
    if diag.code and db.codes[diag.code] then
      keep = false
    end
    if keep then
      table.insert(clean_list, diag)
    end
  end
  return clean_list
end

-- ===================================================================
-- 💻 THE INTERACTIVE DYNAMIC CHECKBOX PICKER PANEL (STATE MACHINE)
-- ===================================================================
function M.manage_file_diagnostics_interactive(state_override)
  local bufnr = vim.api.nvim_get_current_buf()
  local filter_db_path = get_db_path(bufnr)
  local project_root = vim.fs.dirname(filter_db_path)

  local db = load_db(filter_db_path)
  local active_file_blocked = state_override or db.codes

  M.session_discovered_codes = M.session_discovered_codes or {}
  for c_key, is_true in pairs(active_file_blocked) do
    if is_true then
      M.session_discovered_codes[c_key] = true
    end
  end

  local raw_diagnostics = vim.diagnostic.get(bufnr)
  for _, d in ipairs(raw_diagnostics) do
    local c = d.code or ''
    if c ~= '' and type(c) == 'string' and not c:match('[A-Z_]') and not c:match('%s') then
      M.session_discovered_codes[c] = true
    end
  end

  local registered_keys = {}
  for k, _ in pairs(M.session_discovered_codes) do
    table.insert(registered_keys, k)
  end
  table.sort(registered_keys)

  local items = {}
  if next(active_file_blocked) then
    table.insert(items, { action = 'reset', text = '💥 Reset All Filters' })
  end

  for _, c in ipairs(registered_keys) do
    local is_blocked = active_file_blocked[c] == true
    local mark = is_blocked and '[*]' or '[ ]'
    local status = is_blocked and 'Restore' or 'Suppress'
    table.insert(items, {
      action = is_blocked and 'unblock' or 'block',
      id = c,
      text = string.format('  %s %s Code: [%s]', mark, status, c),
    })
  end

  if #items == 0 then
    vim.notify('✅ Clean Slate: No active lints.', vim.log.levels.INFO)
    return
  end

  local block_count = 0
  for _ in pairs(active_file_blocked) do
    block_count = block_count + 1
  end

  vim.ui.select(items, {
    prompt = string.format('📁 %s | Blocked: %d', vim.fs.basename(filter_db_path), block_count),
    format_item = function(item)
      return item.text
    end,
  }, function(choice)
    if not choice then
      -- User pressed Escape: Commit selections and flush to disk
      M.manual_blocked_codes = active_file_blocked
      save_filter_database(project_root, active_file_blocked, M.removed_flags)
      M.session_discovered_codes = nil

      vim.schedule(function()
        if vim.api.nvim_buf_is_valid(bufnr) then
          vim.api.nvim_buf_call(bufnr, function()
            local old = vim.o.shortmess
            vim.o.shortmess = old .. 'F'
            vim.cmd('silent! checktime | silent! edit!')
            vim.o.shortmess = old
          end)
        end
      end)
      return
    end

    if choice.action == 'reset' then
      active_file_blocked = {}
    elseif choice.action == 'block' then
      active_file_blocked[choice.id] = true
    elseif choice.action == 'unblock' then
      active_file_blocked[choice.id] = nil
    end

    M.manage_file_diagnostics_interactive(active_file_blocked)
  end)
end

return M
