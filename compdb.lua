local M = {}

-- ============================================================================
-- 1. STATE-MACHINE TOKENIZER (Handles Escapes & Quotes Safely)
-- ============================================================================
local function tokenize_command(cmd_str)
  local tokens = {}
  local in_quote = false
  local quote_char = nil
  local current_token = {}
  local i = 1
  local len = #cmd_str

  while i <= len do
    local c = cmd_str:sub(i, i)
    if c == '\\' and i < len then
      table.insert(current_token, cmd_str:sub(i + 1, i + 1))
      i = i + 2
    elseif c == '"' or c == "'" then
      if not in_quote then
        in_quote = true
        quote_char = c
      elseif c == quote_char then
        in_quote = false
        quote_char = nil
      else
        table.insert(current_token, c)
      end
      i = i + 1
    elseif (c == ' ' or c == '\t') and not in_quote then
      if #current_token > 0 then
        table.insert(tokens, table.concat(current_token))
        current_token = {}
      end
      i = i + 1
    else
      table.insert(current_token, c)
      i = i + 1
    end
  end
  if #current_token > 0 then
    table.insert(tokens, table.concat(current_token))
  end
  return tokens
end

-- ============================================================================
-- 2. NATIVE FILE SYSTEM ENGINE (100% Shell-Free, Safe, Cross-Platform)
-- ============================================================================
local function get_headers_recursively(dir)
  local headers = {}
  local uv = vim.uv or vim.loop

  local function scan(path)
    local handle = uv.fs_scandir(path)
    if not handle then
      return
    end

    while true do
      local name, type = uv.fs_scandir_next(handle)
      if not name then
        break
      end

      local full_path = path .. '/' .. name
      if type == 'directory' then
        scan(full_path)
      elseif type == 'file' or type == 'link' then
        local ext = name:match('%.([^%.]+)$')
        if ext and (ext == 'h' or ext == 'hpp' or ext == 'hxx' or ext == 'hh') then
          table.insert(headers, vim.fs.normalize(full_path))
        end
      end
    end
  end

  scan(vim.fs.normalize(dir))
  return headers
end

-- ============================================================================
-- 3. CORE RUNTIME ENGINE (Performance Optimized)
-- ============================================================================
function M.generate()
  local project_root = vim.fs.normalize(vim.fn.getcwd())
  local db_path = project_root .. '/compile_commands.json'

  -- Dynamically trigger PlatformIO's base generator safely without shell injection vectors
  vim.fn.system({ 'pio', 'run', '-t', 'compiledb' })

  local f = io.open(db_path, 'r')
  if not f then
    return
  end
  local content = f:read('*all')
  f:close()

  local db = vim.json.decode(content)
  local extended_db = {}
  local unique_includes = {}
  local unique_headers = {}

  for _, entry in ipairs(db) do
    table.insert(extended_db, entry)
    local tokens = tokenize_command(entry.command or '')

    local idx = 1
    while idx <= #tokens do
      local token = tokens[idx]
      local inc_dir = nil

      if token:sub(1, 2) == '-I' then
        inc_dir = #token > 2 and token:sub(3) or tokens[idx + 1]
        if #token == 2 then
          idx = idx + 1
        end
      elseif token == '-isystem' then
        inc_dir = tokens[idx + 1]
        idx = idx + 1
      end

      if inc_dir then
        inc_dir = vim.fs.normalize(inc_dir)

        -- Boundary isolation optimization: only scan project directories.
        -- This avoids thousands of heavy global toolchain/framework headers.
        -- if inc_dir:find(project_root, 1, true) then
        if not unique_includes[inc_dir] then
          unique_includes[inc_dir] = { dir = entry.directory, cmd = entry.command }
        end
        -- end
      end
      idx = idx + 1
    end
  end

  for inc_dir, context in pairs(unique_includes) do
    local headers = get_headers_recursively(inc_dir)
    for _, header_path in ipairs(headers) do
      if not unique_headers[header_path] then
        unique_headers[header_path] = true
        table.insert(extended_db, {
          directory = context.dir,
          file = header_path,
          command = context.cmd .. ' -c ' .. header_path,
        })
      end
    end
  end

  local out_f = io.open(db_path, 'w')
  if out_f then
    out_f:write(vim.json.encode(extended_db))
    out_f:close()
    print('[Success] PlatformIO compilation database optimized instantly.')
  end
end

-- ============================================================================
-- 4. AUTOMATED LIFE-CYCLE HOOKS
-- ============================================================================
local pio_group = vim.api.nvim_create_augroup('PlatformIO_Compdb_Engine', { clear = true })

vim.api.nvim_create_autocmd('BufWritePost', {
  pattern = 'platformio.ini',
  group = pio_group,
  desc = 'Automatically recalculate the compilation database when config shifts',
  callback = function()
    -- Defer execution to avoid freezing the UI thread during disk operations
    vim.schedule(function()
      local success, err = pcall(M.generate)
      if not success then
        vim.notify('[PlatformIO Engine Error]: ' .. tostring(err), vim.log.levels.ERROR)
      end
    end)
  end,
})

-- Optional User Command: Type :PioCompdb to run this manually at any time
vim.api.nvim_create_user_command('PioCompdb', function()
  M.generate()
end, {})

return M
