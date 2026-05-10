local uv = vim.uv or vim.loop
--INFO: pioGitIgnore
------------------------------------------------------
-- stylua: ignore
local function pioGitIgnore()
  local path = vim.fs.joinpath(uv.cwd(), '.gitignore')
  local ignored = {}

  -- 1. Read existing ignores
  local f = io.open(path, 'r')
  if f then
    for line in f:lines() do
      local clean = vim.trim(line)
      if clean ~= '' then table.insert(ignored, clean) end
    end
    f:close()
  end

  -- 2. Normalize and Filter
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

  -- 3. Prepare Display Lines
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

  -- 4. Create Floating Window
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  local width, height = 55, math.min(#lines + 2, 25)
  local win = vim.api.nvim_open_win(buf, false, {
    relative = 'editor', width = width, height = height,
    col = (vim.o.columns - width) / 2, row = (vim.o.lines - height) / 2,
    style = 'minimal', border = 'rounded', title = ' GitIgnore ', title_pos = 'center',
  })

  -- 5. Prompt for Input
  vim.defer_fn(function()
    vim.ui.input({ prompt = 'Action (e.g. +1-3,5-7,-8-9,11): ' }, function(input)
      if vim.api.nvim_win_is_valid(win) then vim.api.nvim_win_close(win, true) end
      if not input or input == '' or input:lower() == 'q' then
        vim.cmd("redraw")
        return
      end

      -- STEP 1: Normalize signs to prevent range-dash collision
      -- We replace the operator minus with a symbol like '_' so range '-' stays safe
      local normalized = input:gsub(",%s*%-", ",_"):gsub("^%-", "_")

      -- STEP 2: Iterate through blocks like "+1-3,5-7" or "_8-9,11"
      for action, segment in normalized:gmatch('([%+%%_])([^%+%%_%s\r\n]+)') do
        -- STEP 3: Expand all ranges in the segment (e.g. 1-3 -> 1,2,3)
        local expanded = segment:gsub('(%d+)%s*-%s*(%d+)', function(s, e)
          local t, start_n, end_n = {}, tonumber(s), tonumber(e)
          if start_n > end_n then start_n, end_n = end_n, start_n end
          for i = start_n, end_n do table.insert(t, i) end
          return table.concat(t, ',')
        end)

        -- STEP 4: Apply commands strictly to indices
        for num_str in expanded:gmatch('%d+') do
          local n = tonumber(num_str)
          if action == '+' and not_ignored[n] then
            local p = not_ignored[n] .. (vim.fn.isdirectory(not_ignored[n]) == 1 and '/' or '')
            table.insert(ignored, p)
          elseif action == '_' then -- This was our escaped '-' sign
            local idx = n - #not_ignored
            if ignored[idx] then ignored[idx] = '__DELETE__' end
          end
        end
      end

      -- 6. Cleanup and Save
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
--       local current_mode = nil
--       -- Split into segments by looking for + or -
--       -- This handles "+1,2-4" and "-5,7" properly
--       for action, segment in input:gmatch('([%+%-])([^%+%-\r\n]+)') do
--         current_mode = action
--
--         -- Expand ranges: "1-4" -> "1,2,3,4"
--         local expanded = segment:gsub('(%d+)%s*-%s*(%d+)', function(s, e)
--           local t = {}
--           local start_n, end_n = tonumber(s), tonumber(e)
--           if start_n > end_n then start_n, end_n = end_n, start_n end
--           for i = start_n, end_n do table.insert(t, i) end
--           return table.concat(t, ',')
--         end)
--
--         -- Apply action to every valid number in segment
--         for num_str in expanded:gmatch('%d+') do
--           local n = tonumber(num_str)
--           if current_mode == '+' then
--             -- Only add if it exists in the top list
--             if not_ignored[n] then
--               local p = not_ignored[n] .. (vim.fn.isdirectory(not_ignored[n]) == 1 and '/' or '')
--               table.insert(ignored, p)
--             end
--           elseif current_mode == '-' then
--             -- Only remove if it exists in the bottom list
--             local idx = n - #not_ignored
--             if ignored[idx] then ignored[idx] = '__DELETE__' end
--           end
--         end
--       end
--
--       -- 6. Cleanup and Save
--       local final_list = {}
--       for _, val in ipairs(ignored) do
--         if val ~= '__DELETE__' then table.insert(final_list, val) end
--       end
--
--       -- Write file only if changes were made
--       local out = io.open(path, 'w')
--       if out then
--         out:write(table.concat(final_list, '\n') .. '\n')
--         out:close()
--       end
--
--       pioGitIgnore()
--     end)
--   end, 20)
-- end
--
-- return { pioGitIgnore = pioGitIgnore }
--
-- -- local uv = vim.uv or vim.loop
-- -- --INFO: pioGitIgnore
-- -- ------------------------------------------------------
-- -- -- stylua: ignore
-- -- local function pioGitIgnore()
-- --   local path = vim.fs.joinpath(uv.cwd(), '.gitignore')
-- --   local ignored = {}
-- --
-- --   local f = io.open(path, 'r')
-- --   if f then
-- --     for line in f:lines() do
-- --       local clean = vim.trim(line)
-- --       if clean ~= '' then table.insert(ignored, clean) end
-- --     end
-- --     f:close()
-- --   end
-- --
-- --   local ignored_lookup = {}
-- --   for _, p in ipairs(ignored) do
-- --     ignored_lookup[p:gsub('^%s*/?', ''):gsub('/?%s*$', '')] = true
-- --   end
-- --
-- --   local ok, files = pcall(vim.fn.readdir, vim.fn.getcwd())
-- --   if not ok then return end
-- --
-- --   local not_ignored = {}
-- --   for _, file in ipairs(files) do
-- --     if file ~= '.gitignore' then
-- --       local norm = file:gsub('^/?', ''):gsub('/?$', '')
-- --       if not ignored_lookup[norm] then table.insert(not_ignored, file) end
-- --     end
-- --   end
-- --
-- --   local lines = { '   GITIGNORE MANAGER', ' ESC/Enter (empty) to exit | +add / -remove', string.rep('─', 45) }
-- --   for i, file in ipairs(not_ignored) do
-- --     local icon = vim.fn.isdirectory(file) == 1 and '📁 ' or '📄 '
-- --     table.insert(lines, string.format(' [%d] %s%s', i, icon, file))
-- --   end
-- --   table.insert(lines, '')
-- --   table.insert(lines, ' --- Current Ignores ---')
-- --   for i, pattern in ipairs(ignored) do
-- --     table.insert(lines, string.format(' [%d] 🚫 %s', i + #not_ignored, pattern))
-- --   end
-- --
-- --   local buf = vim.api.nvim_create_buf(false, true)
-- --   vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
-- --   local width, height = 55, math.min(#lines + 2, 25)
-- --   local win = vim.api.nvim_open_win(buf, false, {
-- --     relative = 'editor', width = width, height = height,
-- --     col = (vim.o.columns - width) / 2, row = (vim.o.lines - height) / 2,
-- --     style = 'minimal', border = 'rounded', title = ' GitIgnore ', title_pos = 'center',
-- --   })
-- --
-- --   vim.defer_fn(function()
-- --     vim.ui.input({ prompt = 'Action (e.g. +1,2-4,-10): ' }, function(input)
-- --       if vim.api.nvim_win_is_valid(win) then vim.api.nvim_win_close(win, true) end
-- --       if not input or input == '' or input:lower() == 'q' then
-- --         vim.cmd("redraw")
-- --         return
-- --       end
-- --
-- --       -- 1. If it's a manual entry (no numbers at all), just add it
-- --       if not input:find('%d') then
-- --         table.insert(ignored, input)
-- --       else
-- --         -- 2. ROBUST PARSER
-- --         local mode = nil -- '+' or '-'
-- --         -- Split by any character that is NOT a number or a range hyphen
-- --         -- but preserve the + and - signs as separate segments
-- --         for part in input:gmatch("([^,%s]+)") do
-- --           -- If the part starts with a sign, update the mode
-- --           local first_char = part:sub(1,1)
-- --           if first_char == '+' or first_char == '-' then
-- --             mode = first_char
-- --             part = part:sub(2) -- Remove the sign from the number part
-- --           end
-- --
-- --           if mode and part ~= "" then
-- --             -- Expand range if exists (e.g. 1-4)
-- --             local s_str, e_str = part:match("(%d+)%-(%d+)")
-- --             local targets = {}
-- --             if s_str and e_str then
-- --               local s, e = tonumber(s_str), tonumber(e_str)
-- --               if s > e then s, e = e, s end
-- --               for i = s, e do table.insert(targets, i) end
-- --             else
-- --               -- Check for single numbers in this segment
-- --               for n in part:gmatch("%d+") do table.insert(targets, tonumber(n)) end
-- --             end
-- --
-- --             -- Apply mode to found indices
-- --             for _, n in ipairs(targets) do
-- --               if mode == '+' and not_ignored[n] then
-- --                 local p = not_ignored[n] .. (vim.fn.isdirectory(not_ignored[n]) == 1 and '/' or '')
-- --                 table.insert(ignored, p)
-- --               elseif mode == '-' then
-- --                 local idx = n - #not_ignored
-- --                 if ignored[idx] then ignored[idx] = '__DELETE__' end
-- --               end
-- --             end
-- --           end
-- --         end
-- --       end
-- --
-- --       -- 3. Cleanup and Save
-- --       local final_list = {}
-- --       for _, val in ipairs(ignored) do
-- --         if val ~= "__DELETE__" then table.insert(final_list, val) end
-- --       end
-- --
-- --       local out = io.open(path, 'w')
-- --       if out then out:write(table.concat(final_list, '\n') .. '\n') out:close() end
-- --       pioGitIgnore()
-- --     end)
-- --   end, 20)
-- -- end
-- --
-- -- return { pioGitIgnore = pioGitIgnore }
