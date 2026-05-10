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

  -- 2. Normalize and Filter (Strict)
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

  -- 3. Prepare Display Lines (i starts at 1 in ipairs)
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
    vim.ui.input({ prompt = 'Action (e.g. +1-4,-5-7): ' }, function(input)
      if vim.api.nvim_win_is_valid(win) then vim.api.nvim_win_close(win, true) end
      if not input or input == '' or input:lower() == 'q' then
        vim.cmd("redraw")
        return
      end

      -- STEP 1: Handle Manual Entries (No +/- prefix)
      if not input:find('^[%%+%%-]') then
        table.insert(ignored, input)
      else
        -- STEP 2: Process Batch (+1-4 or -10,12)
        -- Split input into segments by looking for + or -
        for action, segment in input:gmatch('([%+%-])([^%+%-\r\n]+)') do
          -- Expand ranges like "1-4" into "1,2,3,4"
          local expanded = segment:gsub('(%d+)%s*-%s*(%d+)', function(s, e)
            local t = {}
            for i = tonumber(s), tonumber(e) do table.insert(t, i) end
            return table.concat(t, ',')
          end)

          -- Process every number in the expanded segment
          for num_str in expanded:gmatch('%d+') do
            local n = tonumber(num_str)
            if action == '+' then
              -- n matches [i] in the not_ignored list
              if not_ignored[n] then
                local p = not_ignored[n] .. (vim.fn.isdirectory(not_ignored[n]) == 1 and '/' or '')
                table.insert(ignored, p)
              end
            elseif action == '-' then
              -- n matches the [i + #not_ignored] in the ignored list
              local idx = n - #not_ignored
              if ignored[idx] then
                ignored[idx] = '__DELETE__'
              end
            end
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
      
      pioGitIgnore() -- Refresh UI
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
--   -- 2. Normalize and Filter (Exclude .gitignore itself)
--   local ignored_lookup = {}
--   for _, p in ipairs(ignored) do ignored_lookup[p:gsub('^%s*/?', ''):gsub('/?%s*$', '')] = true end
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
--   local lines = { '   GITIGNORE MANAGER', ' ESC or ENTER (empty) to exit', string.rep('─', 45) }
--   for i, file in ipairs(not_ignored) do
--     local icon = vim.fn.isdirectory(file) == 1 and '📁 ' or '📄 '
--     table.insert(lines, string.format(' [%d] %s%s', i, icon, file))
--   end
--   table.insert(lines, '')
--   table.insert(lines, ' --- Current Ignores ---')
--   for i, pattern in ipairs(ignored) do table.insert(lines, string.format(' [%d] 🚫 %s', i + #not_ignored, pattern)) end
--
--   -- 4. Create Floating Window
--   local buf = vim.api.nvim_create_buf(false, true)
--   vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
--
--   local width, height = 55, math.min(#lines + 2, 25)
--   local win = vim.api.nvim_open_win(buf, false, {
--     relative = 'editor',
--     width = width,
--     height = height,
--     col = (vim.o.columns - width) / 2,
--     row = (vim.o.lines - height) / 2,
--     style = 'minimal',
--     border = 'rounded',
--     title = ' GitIgnore ',
--     title_pos = 'center',
--   })
--
--   -- 5. Prompt for Input
--   vim.defer_fn(function()
--     vim.ui.input({ prompt = 'Action (e.g. +1,2-5): ' }, function(input)
--       -- If Esc or Enter on empty, close and stop
--       if not input or input == '' or input:lower() == 'q' then
--         if vim.api.nvim_win_is_valid(win) then vim.api.nvim_win_close(win, true) end
--         vim.cmd("redraw")
--         return
--       end
--
--       local found_batch = false
--       for action, group in input:gmatch('([%+%-])([%d%s,]+)') do
--         found_batch = true
--         for num in group:gmatch('%d+') do
--           local n = tonumber(num)
--           if action == '+' and not_ignored[n] then
--             local p = not_ignored[n] .. (vim.fn.isdirectory(not_ignored[n]) == 1 and '/' or '')
--             table.insert(ignored, p)
--           elseif action == '-' then
--             local idx = n - #not_ignored
--             if ignored[idx] then ignored[idx] = '__DELETE__' end
--           end
--         end
--       end
--
--       -- If no +/-, treat as manual entry
--       if not found_batch then table.insert(ignored, input) end
--
--       local final_list = {}
--       for _, val in ipairs(ignored) do
--         if val ~= '__DELETE__' then table.insert(final_list, val) end
--       end
--
--       -- Write File
--       local out = io.open(path, 'w')
--       if out then
--         out:write(table.concat(final_list, '\n') .. '\n')
--         out:close()
--       end
--
--       -- Close window and RECURSE to refresh the list
--       if vim.api.nvim_win_is_valid(win) then vim.api.nvim_win_close(win, true) end
--       pioGitIgnore()
--     end)
--   end, 20)
-- end
--
-- return {
--   pioGitIgnore = pioGitIgnore,
-- }
