local M = {}

-- 1. High-speed hot-memory registers (Simple key-value lookups)
M.blocked_codes = {}
M.removed_flags = {}

-- Load your persistent .filter.json on plugin initialization
local json_file = vim.fs.root(0, { 'platformio.ini', '.git' }) .. '/.filter.json'
local function load_db()
  local f = io.open(json_file, 'r')
  if not f then
    return
  end
  local data = vim.json.decode(f:read('*all') or '{}')
  M.blocked_codes = data.codes or {}
  M.removed_flags = data.flags or {}
  f:close()
end
load_db()

-- 2. THE PROFESSIONAL CORE: Intercept and filter data instantly in memory
function M.setup_diagnostic_filter()
  vim.diagnostic.config({
    virtual_text = {
      filter = function(diagnostic)
        -- Ignore it instantly if the short code matches your blocked list
        if M.blocked_codes[diagnostic.code] then
          return false
        end

        -- Ignore it if the message text references a blocked compiler argument
        local msg = diagnostic.message or ''
        for flag, _ in pairs(M.removed_flags) do
          if msg:find(flag, 1, true) then
            return false
          end
        end

        return true -- Let all valid code typos pass through cleanly
      end,
    },
    underlines = {
      filter = function(diagnostic)
        if M.blocked_codes[diagnostic.code] then
          return false
        end
        -- (Repeat the message check flag filter here)
        return true
      end,
    },
    signs = {
      filter = function(diagnostic)
        if M.blocked_codes[diagnostic.code] then
          return false
        end
        return true
      end,
    },
  })
end

-- 3. INTERACTIVE DASHBOARD: Zero Restarts Needed
function M.manage_file_diagnostics_interactive()
  -- Pull diagnostics from the active screen window
  local current_buf = vim.api.nvim_get_current_buf()
  local raw_diagnostics = vim.diagnostic.get(current_buf)
  local dashboard_items = {}

  -- (Populate your menu options by looping over raw_diagnostics just like before...)

  vim.ui.select(dashboard_items, { prompt = 'Compiler Interceptor Dashboard' }, function(choice)
    if not choice then
      return
    end

    if choice.action == 'block_flag' then
      M.removed_flags[choice.id] = true
    elseif choice.action == 'block_code' then
      M.blocked_codes[choice.id] = true
    end

    -- Save to json database quietly
    local f = io.open(json_file, 'w')
    if f then
      f:write(vim.json.encode({ codes = M.blocked_codes, flags = M.removed_flags }))
      f:close()
    end

    -- RE-RENDER INSTANTLY WITHOUT RESTARTING THE LSP
    vim.diagnostic.show(nil, current_buf)
  end)
end

return M
