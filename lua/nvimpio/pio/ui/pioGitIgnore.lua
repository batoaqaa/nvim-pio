local uv = vim.uv or vim.loop
--INFO: pioGitIgnore
------------------------------------------------------
-- stylua: ignore
local function pioGitIgnore()
  local path = vim.fs.joinpath(uv.cwd(), '.gitignore')
  local ignored = {}

  local f = io.open(path, 'r')
  if f then
    for line in f:lines() do
      local clean = vim.trim(line)
      if clean ~= '' then
        table.insert(ignored, clean)
      end
    end
    f:close()
  end

  local ignored_lookup = {}
  for _, p in ipairs(ignored) do
    ignored_lookup[p:gsub('^%s*/?', ''):gsub('/?%s*$', '')] = true
  end

  local ok, files = pcall(vim.fn.readdir, vim.uv.cwd())
  if not ok then
    return
  end

  local not_ignored = {}
  for _, file in ipairs(files) do
    if file ~= '.gitignore' then
      local norm = file:gsub('^/?', ''):gsub('/?$', '')
      if not ignored_lookup[norm] then
        table.insert(not_ignored, file)
      end
    end
  end

  -- 3. Prepare Display Lines
  local lines = { '   GITIGNORE MANAGER', ' ESC/Enter (empty) to exit | +add / -remove', string.rep('─', 45) }
  local hls = {}

  local function add_line_with_icon(idx, name, is_ignored)
    -- FIX: Ensure isdirectory receives exactly one string argument
    local check_path = tostring(name):gsub('/$', '')
    local is_dir = vim.fn.isdirectory(check_path) == 1 or name:match('/$')

    local icon = is_dir and '📁 ' or '📄 '
    local prefix = is_ignored and '🚫 ' or ''
    local line_idx = #lines

    local line_text = string.format(' [%d] %s%s%s', idx, prefix, icon, name)
    table.insert(lines, line_text)

    -- Find icon position (handle multibyte correctly)
    local start_col = line_text:find(icon) - 1
    table.insert(hls, { line = line_idx, start_col = start_col, is_dir = is_dir })
  end

  for i, file in ipairs(not_ignored) do
    add_line_with_icon(i, file, false)
  end
  table.insert(lines, '')
  table.insert(lines, ' --- Current Ignores ---')
  for i, pattern in ipairs(ignored) do
    add_line_with_icon(i + #not_ignored, pattern, true)
  end

  -- 4. Create Window and Buffer
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

  local ns = vim.api.nvim_create_namespace('pio_git_icons')
  for _, hl in ipairs(hls) do
    vim.api.nvim_buf_set_extmark(buf, ns, hl.line, hl.start_col, {
      end_col = hl.start_col + 4,
      hl_group = hl.is_dir and 'Directory' or 'Identifier',
    })
  end

  local width, height = 55, math.min(#lines + 2, 25)
  local win = vim.api.nvim_open_win(buf, false, {
    relative = 'editor',
    width = width,
    height = height,
    col = (vim.o.columns - width) / 2,
    row = (vim.o.lines - height) / 2,
    style = 'minimal',
    border = 'rounded',
    title = ' GitIgnore ',
    title_pos = 'center',
  })

  -- 5. Prompt for Input
  vim.defer_fn(function()
    vim.ui.input({ prompt = 'Action (e.g. +1-3,-7-9): ' }, function(input)
      if vim.api.nvim_win_is_valid(win) then
        vim.api.nvim_win_close(win, true)
      end
      if not input or input == '' then
        vim.cmd('redraw')
        return
      end

      local normalized = input:gsub(',%s*%-', ',_'):gsub('^%-', '_')
      for action, segment in normalized:gmatch('([%+%%_])([^%+%%_%s\r\n]+)') do
        local expanded = segment:gsub('(%d+)%s*-%s*(%d+)', function(s, e)
          local t, sn, en = {}, tonumber(s), tonumber(e)
          if sn > en then
            sn, en = en, sn
          end
          for j = sn, en do
            table.insert(t, j)
          end
          return table.concat(t, ',')
        end)
        for num_str in expanded:gmatch('%d+') do
          local n = tonumber(num_str)
          if action == '+' and not_ignored[n] then
            local p = not_ignored[n] .. (vim.fn.isdirectory(not_ignored[n]) == 1 and '/' or '')
            table.insert(ignored, p)
          elseif action == '_' then
            local idx = n - #not_ignored
            if ignored[idx] then
              ignored[idx] = '__DELETE__'
            end
          end
        end
      end

      local final_list = {}
      for _, val in ipairs(ignored) do
        if val ~= '__DELETE__' then
          table.insert(final_list, val)
        end
      end

      local out = io.open(path, 'w')
      if out then
        out:write(table.concat(final_list, '\n') .. '\n')
        out:close()
      end
      pioGitIgnore()
    end)
  end, 20)
end

return { pioGitIgnore = pioGitIgnore }

-- local uv = vim.uv or vim.loop
-- --INFO: pioGitIgnore
-- ------------------------------------------------------
-- -- stylua: ignore
-- local function pioGitIgnore()
--   local path = vim.fs.joinpath(uv.cwd(), '.gitignore')
--   local ignored = {}
--
--   -- 1. Read existing ignores
--   local f = io.open(path, 'r')
--   if f then
--     for line in f:lines() do
--       local clean = vim.trim(line)
--       if clean ~= '' then table.insert(ignored, clean) end
--     end
--     f:close()
--   end
--
--   -- 2. Normalize and Filter (Strict)
--   local ignored_lookup = {}
--   for _, p in ipairs(ignored) do
--     ignored_lookup[p:gsub('^%s*/?', ''):gsub('/?%s*$', '')] = true
--   end
--
--   local ok, files = pcall(vim.fn.readdir, vim.fn.getcwd())
--   if not ok then return end
--
--   local not_ignored = {}
--   for _, file in ipairs(files) do
--     if file ~= '.gitignore' then
--       local norm = file:gsub('^/?', ''):gsub('/?$', '')
--       if not ignored_lookup[norm] then table.insert(not_ignored, file) end
--     end
--   end
--
--   -- 3. Prepare Display Lines
--   local lines = { '   GITIGNORE MANAGER', ' ESC/Enter (empty) to exit | +add / -remove', string.rep('─', 45) }
--
--   -- Section 1: Files/Folders NOT ignored
--   for i, file in ipairs(not_ignored) do
--     local icon = vim.fn.isdirectory(file) == 1 and '📁 ' or '📄 '
--     table.insert(lines, string.format(' [%d] %s%s', i, icon, file))
--   end
--
--   table.insert(lines, '')
--   table.insert(lines, ' --- Current Ignores ---')
--
--   -- Section 2: Current Ignores with Dynamic Icons
--   for i, pattern in ipairs(ignored) do
--     -- Determine icon by checking if the path exists as a directory
--     -- We strip the leading/trailing slashes to check the path correctly
--     local clean_path = pattern:gsub('^/', ''):gsub('/$', '')
--     local icon = '📄 ' -- Default to file
--     if vim.fn.isdirectory(clean_path) == 1 then
--       icon = '📁 '
--     elseif pattern:match('/$') then
--       -- If the folder doesn't exist locally anymore but has a trailing slash, still show folder icon
--       icon = '📁 '
--     end
--
--     table.insert(lines, string.format(' [%d] %s %s', i + #not_ignored, icon, pattern))
--   end
--
--   -- 4. Create Floating Window
--   local buf = vim.api.nvim_create_buf(false, true)
--   vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
--   local width, height = 55, math.min(#lines + 2, 25)
--   local win = vim.api.nvim_open_win(buf, false, {
--     relative = 'editor', width = width, height = height,
--     col = (vim.o.columns - width) / 2, row = (vim.o.lines - height) / 2,
--     style = 'minimal', border = 'rounded', title = ' GitIgnore ', title_pos = 'center',
--   })
--
--   -- 5. Prompt for Input (using your multi-range batch logic)
--   vim.defer_fn(function()
--     vim.ui.input({ prompt = 'Action (e.g. +1-3,-7-9): ' }, function(input)
--       if vim.api.nvim_win_is_valid(win) then vim.api.nvim_win_close(win, true) end
--       if not input or input == "" then
--         vim.cmd("redraw")
--         return
--       end
--
--       -- Normalize minus signs to avoid range collision
--       local normalized = input:gsub(",%s*%-", ",_"):gsub("^%-", "_")
--
--       for action, segment in normalized:gmatch('([%+%%_])([^%+%%_%s\r\n]+)') do
--         local expanded = segment:gsub('(%d+)%s*-%s*(%d+)', function(s, e)
--           local t, sn, en = {}, tonumber(s), tonumber(e)
--           if sn > en then sn, en = en, sn end
--           for i = sn, en do table.insert(t, i) end
--           return table.concat(t, ',')
--         end)
--
--         for num_str in expanded:gmatch('%d+') do
--           local n = tonumber(num_str)
--           if action == '+' and not_ignored[n] then
--             local p = not_ignored[n] .. (vim.fn.isdirectory(not_ignored[n]) == 1 and '/' or '')
--             table.insert(ignored, p)
--           elseif action == '_' then
--             local idx = n - #not_ignored
--             if ignored[idx] then ignored[idx] = '__DELETE__' end
--           end
--         end
--       end
--
--       local final_list = {}
--       for _, val in ipairs(ignored) do
--         if val ~= '__DELETE__' then table.insert(final_list, val) end
--       end
--
--       local out = io.open(path, 'w')
--       if out then
--         out:write(table.concat(final_list, '\n') .. '\n')
--         out:close()
--       end
--       pioGitIgnore()
--     end)
--   end, 20)
-- end
--
-- return { pioGitIgnore = pioGitIgnore }
--
