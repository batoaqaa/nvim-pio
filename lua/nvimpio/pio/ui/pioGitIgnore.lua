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
    vim.ui.input({ prompt = 'Action (e.g. +1-3,-7-9): ' }, function(input)
      if vim.api.nvim_win_is_valid(win) then vim.api.nvim_win_close(win, true) end
      if not input or input == '' or input:lower() == 'q' then
        vim.cmd("redraw")
        return
      end

      local processed = false
      -- 1. Identify segments like +1-3 or -7-9
      for action, segment in input:gmatch('([%+%-])([^%+%-\r\n]+)') do
        processed = true
        
        -- FIX: Inclusive range expansion
        local expanded = segment:gsub('(%d+)%s*-%s*(%d+)', function(start_num, end_num)
          local t = {}
          local s, e = tonumber(start_num), tonumber(end_num)
          -- Ensure s is smaller than e for the loop
          if s > e then s, e = e, s end 
          for i = s, e do table.insert(t, i) end
          return table.concat(t, ',')
        end)

        for num_str in expanded:gmatch('%d+') do
          local n = tonumber(num_str)
          if action == '+' then
            if not_ignored[n] then
              local p = not_ignored[n] .. (vim.fn.isdirectory(not_ignored[n]) == 1 and '/' or '')
              table.insert(ignored, p)
            end
          elseif action == '-' then
            -- Offset math: index in 'ignored' is choice minus count of top list
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
      if out then out:write(table.concat(final_list, '\n') .. '\n') out:close() end
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
--     vim.ui.input({ prompt = 'Action (e.g. +1-4,-5-7): ' }, function(input)
--       if vim.api.nvim_win_is_valid(win) then vim.api.nvim_win_close(win, true) end
--       if not input or input == '' or input:lower() == 'q' then
--         vim.cmd("redraw")
--         return
--       end
--
--       local processed = false
--       -- 1. Parse for commands like +1,2 or -4,5-7
--       for action, segment in input:gmatch('([%+%-])([^%+%-\r\n]+)') do
--         processed = true
--         local expanded = segment:gsub('(%d+)%s*-%s*(%d+)', function(s, e)
--           local t = {}
--           for i = tonumber(s), tonumber(e) do table.insert(t, i) end
--           return table.concat(t, ',')
--         end)
--
--         for num_str in expanded:gmatch('%d+') do
--           local n = tonumber(num_str)
--           if action == '+' then
--             -- VALIDATION: Only add if the file index exists
--             if not_ignored[n] then
--               local p = not_ignored[n] .. (vim.fn.isdirectory(not_ignored[n]) == 1 and '/' or '')
--               table.insert(ignored, p)
--             end
--           elseif action == '-' then
--             -- VALIDATION: Only remove if the ignore index exists
--             local idx = n - #not_ignored
--             if ignored[idx] then ignored[idx] = '__DELETE__' end
--           end
--         end
--       end
--
--       -- 2. Manual entry: Only if no +/- was used AND it's not just a stray number
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
--       if out then out:write(table.concat(final_list, '\n') .. '\n') out:close() end
--       pioGitIgnore()
--     end)
--   end, 20)
-- end
--
-- return { pioGitIgnore = pioGitIgnore }
