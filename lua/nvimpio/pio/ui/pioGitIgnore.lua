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
      if clean ~= '' then table.insert(ignored, clean) end
    end
    f:close()
  end

  local ignored_lookup = {}
  for _, p in ipairs(ignored) do 
    ignored_lookup[p:gsub('^%s*/?', ''):gsub('/?%s*$', '')] = true 
  end

  local ok, files = pcall(vim.fn.readdir, vim.fn.getcwd())
  if not ok then return end

  local not_ignored = {}
  for _, file in ipairs(files) do
    if file ~= '.gitignore' then
      local norm = file:gsub('^/?', ''):gsub('/?$', '')
      if not ignored_lookup[norm] then table.insert(not_ignored, file) end
    end
  end

  local lines = { '   GITIGNORE MANAGER', ' ESC/Enter (empty) to exit | +add / -remove', string.rep('─', 45) }
  for i, file in ipairs(not_ignored) do
    local icon = vim.fn.isdirectory(file) == 1 and '📁 ' or '📄 '
    table.insert(lines, string.format(' [%d] %s%s', i, icon, file))
  end
  table.insert(lines, '')
  table.insert(lines, ' --- Current Ignores ---')
  for i, pattern in ipairs(ignored) do 
    table.insert(lines, string.format(' [%d] 🚫 %s', i + #not_ignored, pattern)) 
  end

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  local width, height = 55, math.min(#lines + 2, 25)
  local win = vim.api.nvim_open_win(buf, false, {
    relative = 'editor', width = width, height = height,
    col = (vim.o.columns - width) / 2, row = (vim.o.lines - height) / 2,
    style = 'minimal', border = 'rounded', title = ' GitIgnore ', title_pos = 'center',
  })

  vim.defer_fn(function()
    vim.ui.input({ prompt = 'Action (e.g. +2-4): ' }, function(input)
      if vim.api.nvim_win_is_valid(win) then vim.api.nvim_win_close(win, true) end
      if not input or input == '' or input:lower() == 'q' then
        vim.cmd("redraw")
        return
      end

      local processed = false
      -- 1. Improved Segment Capture: Don't stop at hyphens
      for action, segment in input:gmatch('([%+%-])([^%+%s\r\n]+)') do
        processed = true
        
        -- 2. Range Expansion: Explicitly inclusive (2-4 -> 2,3,4)
        local expanded = segment:gsub('(%d+)%s*-%s*(%d+)', function(s, e)
          local start_n, end_n = tonumber(s), tonumber(e)
          if start_n > end_n then start_n, end_n = end_n, start_n end
          
          local t = {}
          -- The loop is inclusive in Lua
          for i = start_n, end_n do 
            table.insert(t, i) 
          end
          return table.concat(t, ',')
        end)

        -- 3. Apply Actions
        for num_str in expanded:gmatch('%d+') do
          local n = tonumber(num_str)
          if action == '+' then
            if not_ignored[n] then
              local p = not_ignored[n] .. (vim.fn.isdirectory(not_ignored[n]) == 1 and '/' or '')
              table.insert(ignored, p)
            end
          elseif action == '-' then
            local idx = n - #not_ignored
            if ignored[idx] then 
              ignored[idx] = '__DELETE__' 
            end
          end
        end
      end

      if not processed and not input:match('^%d+$') then
        table.insert(ignored, input)
      end

      local final_list = {}
      for _, val in ipairs(ignored) do
        if val ~= '__DELETE__' then table.insert(final_list, val) end
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
--   local f = io.open(path, 'r')
--   if f then
--     for line in f:lines() do
--       local clean = vim.trim(line)
--       if clean ~= '' then table.insert(ignored, clean) end
--     end
--     f:close()
--   end
--
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
--   local lines = { '   GITIGNORE MANAGER', ' ESC/Enter (empty) to exit | +add / -remove', string.rep('─', 45) }
--   for i, file in ipairs(not_ignored) do
--     local icon = vim.fn.isdirectory(file) == 1 and '📁 ' or '📄 '
--     -- IMPORTANT: Indexing starts at 1 for ipairs
--     table.insert(lines, string.format(' [%d] %s%s', i, icon, file))
--   end
--   table.insert(lines, '')
--   table.insert(lines, ' --- Current Ignores ---')
--   for i, pattern in ipairs(ignored) do
--     table.insert(lines, string.format(' [%d] 🚫 %s', i + #not_ignored, pattern))
--   end
--
--   local buf = vim.api.nvim_create_buf(false, true)
--   vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
--   local width, height = 55, math.min(#lines + 2, 25)
--   local win = vim.api.nvim_open_win(buf, false, {
--     relative = 'editor', width = width, height = height,
--     col = (vim.o.columns - width) / 2, row = (vim.o.lines - height) / 2,
--     style = 'minimal', border = 'rounded', title = ' GitIgnore ', title_pos = 'center',
--   })
--
--   vim.defer_fn(function()
--     vim.ui.input({ prompt = 'Action (e.g. +1-3,-7-9): ' }, function(input)
--       if vim.api.nvim_win_is_valid(win) then vim.api.nvim_win_close(win, true) end
--       if not input or input == '' or input:lower() == 'q' then
--         vim.cmd("redraw")
--         return
--       end
--
--       local processed = false
--       -- 1. Identify segments.
--       -- We look for + or - followed by any digits, commas, OR internal dashes.
--       -- The [^%+%-\r\n] in the old code was stopping at the "1-3" dash!
--       for action, segment in input:gmatch('([%+%-])([^%+%s\r\n]+)') do
--         processed = true
--
--         -- 2. Expand ranges: "1-3" -> "1,2,3"
--         local expanded = segment:gsub('(%d+)%s*-%s*(%d+)', function(start_num, end_num)
--           local t = {}
--           local s, e = tonumber(start_num), tonumber(end_num)
--           if s > e then s, e = e, s end
--           for i = s, e do table.insert(t, i) end
--           return table.concat(t, ',')
--         end)
--
--         -- 3. Process indices
--         for num_str in expanded:gmatch('%d+') do
--           local n = tonumber(num_str)
--           if action == '+' then
--             if not_ignored[n] then
--               local p = not_ignored[n] .. (vim.fn.isdirectory(not_ignored[n]) == 1 and '/' or '')
--               table.insert(ignored, p)
--             end
--           elseif action == '-' then
--             local idx = n - #not_ignored
--             if ignored[idx] then
--               ignored[idx] = '__DELETE__'
--             end
--           end
--         end
--       end
--
--       -- Manual pattern fallback
--       if not processed and not input:match('^%d+$') then
--         table.insert(ignored, input)
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
