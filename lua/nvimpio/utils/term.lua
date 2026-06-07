-- good ....
-- stylua: ignore start
local M = {}

local config = require('nvimpio').config

M.stdout_callback = nil
M.exit_callback = nil

------------------------------------------------------
function M.strsplit(inputstr, del)
  local t = {}
  if type(inputstr) == 'string' and inputstr and inputstr ~= '' then
    for str in string.gmatch(inputstr, '([^' .. del .. ']+)') do
      table.insert(t, str)
    end
  end
  return t
end

function M.check_prefix(str, prefix)
  return str:sub(1, #prefix) == prefix
end

------------------------------------------------------
---@class Terminal
---@field id number
---@field bufnr number
---@field window number
---@field display_name string
---@field job_id number
---@field close function
---@field toggle function
---@field open function
---@field spawn function
---@field direction string

---@class PioPrevContext
---@field term Terminal|nil
---@field mon Terminal|nil
---@field cli Terminal|nil
---@field float boolean
---@field orig_window number|nil
function M.getPreviousWindow(orig_window)
  local prev = {
    orig_window = orig_window,
    term = nil,
    cli = nil,
    mon = nil,
    float = false,
  }
  local terms = require('toggleterm.terminal').get_all(true)
  if #terms ~= 0 then
    for i = 1, #terms do
      local dname = terms[i].display_name
      if dname and dname ~= '' and string.find(dname, 'pio', 1) then
        -- SAFE MATCH: No array indices used, preventing code box breakages
        local name_type, win_id_str = string.match(dname, '([^:]+):([^:]+)')
        local win_id = tonumber(win_id_str)

        if name_type == 'piocli' then
          prev.cli = terms[i]
          if terms[i].window == orig_window then
            prev.orig_window = win_id
            prev.term = terms[i]
          end
        elseif name_type == 'piomon' then
          prev.mon = terms[i]
          if terms[i].window == orig_window then
            prev.orig_window = win_id
            prev.term = terms[i]
          end
        end
      end
    end
  end
  return prev
end

------------------------------------------------------
local function send(term, cmd)
  vim.fn.chansend(term.job_id, cmd .. OS.eol)
  if vim.api.nvim_buf_is_loaded(term.bufnr) and vim.api.nvim_buf_is_valid(term.bufnr) then
    if term.window and vim.api.nvim_win_is_valid(term.window) then
      vim.api.nvim_set_current_win(term.window)
      vim.api.nvim_buf_call(term.bufnr, function()
        local mode = vim.api.nvim_get_mode().mode
        if mode == 'n' or mode == 'nt' then
          vim.cmd('normal! G')
        end
      end)
    end
  end
end

------------------------------------------------------
local function PioTermClose(t)
  local name_type, win_id_str = string.match(t.display_name, '([^:]+):([^:]+)')
  local orig_window = tonumber(win_id_str)
  vim.api.nvim_win_close(t.window, true)

  vim.cmd('wincmd =')

  if orig_window and vim.api.nvim_win_is_valid(orig_window) then
    vim.api.nvim_set_current_win(orig_window)
  else
    vim.api.nvim_set_current_win(0)
  end
end

------------------------------------------------------
function M.ToggleTerminal(command, direction)
  local status_ok, _ = pcall(require, 'toggleterm')
  if not status_ok then
    vim.api.nvim_echo({ { 'toggleterm not found!', 'ErrorMsg' } }, true, {})
    return
  end
  -- 1. Get the current active terminal states upfront
  local prev = M.getPreviousWindow(vim.api.nvim_get_current_win())
  local orig_window = prev.orig_window

  -- 2. UNIFIED TOGGLE HOOK: Close the opponent window immediately before running any logic
  if string.find(command, ' monitor') then
    if prev.cli then prev.cli:close() end  -- If opening monitor, shut down CLI
  else
    if prev.mon then prev.mon:close() end  -- If opening CLI, shut down monitor
  end

  -- 3. Now your main logic stays clean, pure, and untouched
  local title = ''
  local pioOpts = {}


  if string.find(command, ' monitor') then
    if prev.mon then
      prev.mon.display_name = 'piomon:' .. orig_window
      local win_type = vim.fn.win_gettype(prev.mon.window)
      local win_open = win_type == '' or win_type == 'popup'
      if prev.mon.window and (win_open and vim.api.nvim_win_get_buf(prev.mon.window) == prev.mon.bufnr) then
        vim.api.nvim_set_current_win(prev.mon.window)
      else
        prev.mon:open()
        -- vim.cmd('wincmd =')
      end
      return prev.mon
    end
    title = 'Pio Monitor: [In normal mode press: q or :q to hide; :q! to quit]'
    pioOpts.display_name = 'piomon:' .. orig_window
    pioOpts.id = 98
    pioOpts.on_stdout = nil
  else
    if prev.cli then
      prev.cli.display_name = 'piocli:' .. orig_window
      local win_type = vim.fn.win_gettype(prev.cli.window)
      local win_open = win_type == '' or win_type == 'popup'
      if prev.cli.window and (win_open and vim.api.nvim_win_get_buf(prev.cli.window) == prev.cli.bufnr) then
        vim.api.nvim_set_current_win(prev.cli.window)
      else
        prev.cli:open()
        -- vim.cmd('wincmd =')
      end
      vim.defer_fn(function()
        if command and command ~= '' then send(prev.cli, command) end
      end, 50)
      return prev.cli
    end
    title = 'Pio CLI> [In normal mode press: q or :q to hide; :q! to quit]'
    pioOpts.display_name = 'piocli:' .. orig_window
    pioOpts.id = 99

    pioOpts.on_stdout = function(terminal, job, data, name)
      if type(M.stdout_callback) == 'function' then
        M.stdout_callback(terminal, job, data, name)
      end
    end

    pioOpts.on_stderr = function(terminal, job, data, name)
      if type(M.stdout_callback) == 'function' then
        M.stdout_callback(terminal, job, data, name)
      end
    end
  end

  local termConfig = {
    hidden = true,
    hide_numbers = true,
    direction = 'horizontal',
    size = function()
      -- return math.ceil(vim.o.columns * 0.68)
      return vim.api.nvim_win_get_width(0)
    end,
    close_on_exit = false,

    on_open = function(t)
      vim.cmd("wincmd J")
      -- vim.cmd('wincmd =')
      local hl = { bg = '#80a3d4', fg = '#000000' }

      if hl then
        vim.api.nvim_set_hl(0, 'MyWinBar', { bg = hl.bg, fg = hl.fg })
        local winBartitle = '%#MyWinBar#' .. title .. '%*'
        vim.api.nvim_set_option_value('winbar', winBartitle, { scope = 'local', win = t.window })

        vim.schedule(function()
          vim.api.nvim_set_option_value('winbar', winBartitle, { scope = 'local', win = t.window })
        end)
      end

      -- vim.cmd('wincmd =')

      vim.keymap.set('t', '<Esc>', [[<C-\><C-n>k]], { buffer = t.bufnr })
      vim.keymap.set('n', '<Esc>', [[<C-\><C-n>a]], { buffer = t.bufnr })

      vim.keymap.set('t', '<S-h>', [[<C-\><C-n><C-w>h]], { buffer = t.bufnr, silent = true })
      vim.keymap.set('t', '<S-l>', [[<C-\><C-n><C-w>l]], { buffer = t.bufnr, silent = true })

      vim.keymap.set('n', 'q', function()
        PioTermClose(t)
      end, { desc = 'PioTermClose', buffer = t.bufnr })

      if config.debug then
        local p_type, p_win = string.match(t.display_name, '([^:]+):([^:]+)')
        vim.api.nvim_echo({
          { 'ToggleTerm ', 'MoreMsg' },
          { '(Term name: ' .. p_type .. ')', 'MoreMsg' },
          { '(Prev win ID: ' .. p_win .. ')', 'MoreMsg' },
          { '(Term Win ID: ' .. t.window .. ')', 'MoreMsg' },
          { '(Term Buffer#: ' .. t.bufnr .. ')', 'MoreMsg' },
          { '(Term id: ' .. t.id .. ')', 'MoreMsg' },
          { '(Job ID: ' .. t.job_id .. ')', 'MoreMsg' },
        }, true, {})
      end
    end,

    on_close = function(t)
      local p_type, p_win = string.match(t.display_name, '([^:]+):([^:]+)')
      orig_window = tonumber(p_win)

      vim.cmd('wincmd =')

      if orig_window and vim.api.nvim_win_is_valid(orig_window) then
        vim.api.nvim_set_current_win(orig_window)
      else
        vim.api.nvim_set_current_win(0)
      end
    end,

    on_create = function(t)
      local p_type, p_win = string.match(t.display_name, '([^:]+):([^:]+)')
      local platformio = vim.api.nvim_create_augroup(p_type .. '_group', { clear = true })

      vim.api.nvim_create_autocmd('CmdlineLeave', {
        group = platformio,
        buffer = t.bufnr,
        callback = function()
          if vim.v.event and not vim.v.event.abort and vim.v.event.cmdtype == ':' then
            local quit = vim.fn.getcmdline() == 'q'
            local quitbang = vim.fn.getcmdline() == 'q!'
            if quitbang or quit then
              local ns_type, ns_win_str = string.match(t.display_name, '([^:]+):([^:]+)')
              if quitbang then
                if ns_type == 'piomon' then
                  local exit = vim.api.nvim_replace_termcodes('<C-C>exit', true, true, true)
                  send(t, exit)
                else
                  send(t, 'exit')
                end
              end

              orig_window = tonumber(ns_win_str)
              vim.schedule(function()
                vim.cmd('wincmd =')
                if orig_window and vim.api.nvim_win_is_valid(orig_window) then
                  vim.api.nvim_set_current_win(orig_window)
                else
                  vim.api.nvim_set_current_win(0)
                end
              end)
            end
          end
        end,
      })

      vim.api.nvim_create_autocmd('BufUnload', {
        group = platformio,
        desc = 'toggleterm buffer unloaded',
        buffer = t.bufnr,
        callback = function(args)
          pcall(vim.keymap.del, 't', '<Esc>', { buffer = args.buf })
          pcall(vim.keymap.del, 'n', '<Esc>', { buffer = args.buf })
          pcall(vim.keymap.del, 't', '<S-h>', { buffer = args.buf })
          pcall(vim.keymap.del, 't', '<S-l>', { buffer = args.buf })

          local ns_type = string.match(t.display_name, '([^:]+):')
          vim.api.nvim_clear_autocmds({ group = ns_type .. '_group' })
          vim.schedule(function()
            vim.cmd('wincmd =')
          end)
        end,
      })
    end,
  }

  termConfig = vim.tbl_deep_extend('force', termConfig, pioOpts or {})

  local terminal = require('toggleterm.terminal').Terminal:new(termConfig)
  terminal:toggle()

  vim.defer_fn(function()
    if command and command ~= '' then
      send(terminal, command)
    end
  end, 50)

  return terminal
end

------------------------------------------------------
function M.ToggleBoth()
  M.ToggleTerminal('', 'vertical')
  M.ToggleTerminal(' monitor', 'vertical')

  vim.schedule(function()
    vim.cmd('wincmd =')
  end)
end

return M

-- old good!
-- local M = {}
--
-- local config = require('nvimpio').config
--
-- -- to fix require loop, toggleterm is using stdout_callback function in 'platformio.utils.pio'
-- -- M.stdout_callback will be assigned by 'platformio.utils.pio'
-- M.stdout_callback = nil
-- M.exit_callback = nil
--
-- ------------------------------------------------------
-- function M.strsplit(inputstr, del)
--   local t = {}
--   if type(inputstr) == 'string' and inputstr and inputstr ~= '' then
--     for str in string.gmatch(inputstr, '([^' .. del .. ']+)') do
--       table.insert(t, str)
--     end
--   end
--   return t
-- end
--
-- function M.check_prefix(str, prefix)
--   return str:sub(1, #prefix) == prefix
-- end
--
-- -- Safely isolates the table components to stay inside the code box bounds
-- function M.get_part(str, index)
--   local parts = vim.split(str, ':')
--   return parts[index] or ''
-- end
--
-- ------------------------------------------------------
-- ---@class Terminal
-- ---@field id number
-- ---@field bufnr number
-- ---@field window number
-- ---@field display_name string
-- ---@field job_id number
-- ---@field close function
-- ---@field toggle function
-- ---@field open function
-- ---@field direction string
--
-- ---@class PioPrevContext
-- ---@field term Terminal|nil
-- ---@field mon Terminal|nil
-- ---@field cli Terminal|nil
-- ---@field float boolean
-- ---@field orig_window number|nil
-- local function getPreviousWindow(orig_window)
--   local prev = {
--     orig_window = orig_window,
--     term = nil,
--     cli = nil,
--     mon = nil,
--     float = false,
--   }
--   local terms = require('toggleterm.terminal').get_all(true)
--   if #terms ~= 0 then
--     for i = 1, #terms do
--       local dname = terms[i].display_name
--       if dname and dname ~= '' and dname:find('pio', 1) then
--         local term_type = M.get_part(dname, 1)
--         local win_id = tonumber(M.get_part(dname, 2))
--
--         if term_type == 'piocli' then
--           prev.cli = terms[i]
--           if terms[i].window == orig_window then
--             prev.orig_window = win_id
--             prev.term = terms[i]
--           end
--           if terms[i].direction == 'float' then
--             prev.float = true
--           end
--         elseif term_type == 'piomon' then
--           prev.mon = terms[i]
--           if terms[i].window == orig_window then
--             prev.orig_window = win_id
--             prev.term = terms[i]
--           end
--           if terms[i].direction == 'float' then
--             prev.float = true
--           end
--         end
--       end
--     end
--   end
--   return prev
-- end
--
-- ------------------------------------------------------
-- local function send(term, cmd)
--   vim.fn.chansend(term.job_id, cmd .. OS.eol)
--   if vim.api.nvim_buf_is_loaded(term.bufnr) and vim.api.nvim_buf_is_valid(term.bufnr) then
--     if term.window and vim.api.nvim_win_is_valid(term.window) then
--       vim.api.nvim_set_current_win(term.window)
--       vim.api.nvim_buf_call(term.bufnr, function()
--         local mode = vim.api.nvim_get_mode().mode
--         if mode == 'n' or mode == 'nt' then
--           vim.cmd('normal! G')
--         end
--       end)
--     end
--   end
-- end
--
-- ------------------------------------------------------
-- local function PioTermClose(t)
--   local orig_window = tonumber(M.get_part(t.display_name, 2))
--   vim.api.nvim_win_close(t.window, true)
--
--   if orig_window and vim.api.nvim_win_is_valid(orig_window) then
--     vim.api.nvim_set_current_win(orig_window)
--   else
--     vim.api.nvim_set_current_win(0)
--   end
-- end
--
-- -- Clean handler execution segment
-- local function spawn_terminal_instance(terminal, command)
--   terminal:toggle()
--   vim.defer_fn(function()
--     if command and command ~= '' then
--       send(terminal, command)
--     end
--   end, 50)
-- end
--
-- ------------------------------------------------------
-- function M.ToggleTerminal(command, direction)
--   local status_ok, _ = pcall(require, 'toggleterm')
--   if not status_ok then
--     vim.api.nvim_echo({ { 'toggleterm not found!', 'ErrorMsg' } }, true, {})
--     return
--   end
--
--   local title = ''
--   local pioOpts = {}
--
--   local prev = getPreviousWindow(vim.api.nvim_get_current_win())
--   local orig_window = prev.orig_window
--
--   if string.find(command, ' monitor') then
--     if prev.mon then
--       if prev.cli then
--         prev.cli:close()
--       end
--
--       prev.mon.display_name = 'piomon:' .. orig_window
--       local win_type = vim.fn.win_gettype(prev.mon.window)
--       local win_open = win_type == '' or win_type == 'popup'
--       if prev.mon.window and (win_open and vim.api.nvim_win_get_buf(prev.mon.window) == prev.mon.bufnr) then
--         vim.api.nvim_set_current_win(prev.mon.window)
--       else
--         prev.mon:open()
--       end
--       return prev.mon
--     end
--
--     if prev.cli then
--       prev.cli:close()
--     end
--
--     title = 'Pio Monitor: [In normal mode press: q or :q to hide; :q! to quit; :PioTermList to list terminals]'
--     pioOpts.display_name = 'piomon:' .. orig_window
--     pioOpts.id = 98
--     pioOpts.on_stdout = nil
--   else
--     if prev.cli then
--       if prev.mon then
--         prev.mon:close()
--       end
--
--       prev.cli.display_name = 'piocli:' .. orig_window
--       local win_type = vim.fn.win_gettype(prev.cli.window)
--       local win_open = win_type == '' or win_type == 'popup'
--       if prev.cli.window and (win_open and vim.api.nvim_win_get_buf(prev.cli.window) == prev.cli.bufnr) then
--         vim.api.nvim_set_current_win(prev.cli.window)
--       else
--         prev.cli:open()
--       end
--       vim.defer_fn(function()
--         if command and command ~= '' then
--           send(prev.cli, command)
--         end
--       end, 50)
--       return prev.cli
--     end
--
--     if prev.mon then
--       prev.mon:close()
--     end
--
--     title = 'Pio CLI> [In normal mode press: q or :q to hide; :q! to quit; :PioTermList to list terminals]'
--     pioOpts.display_name = 'piocli:' .. orig_window
--     pioOpts.id = 99
--
--     pioOpts.on_stdout = function(terminal, job, data, name)
--       if type(M.stdout_callback) == 'function' then
--         M.stdout_callback(terminal, job, data, name)
--       end
--     end
--
--     pioOpts.on_stderr = function(terminal, job, data, name)
--       if type(M.stdout_callback) == 'function' then
--         M.stdout_callback(terminal, job, data, name)
--       end
--     end
--   end
--   pioOpts.direction = direction
--
--   local termConfig = {
--     hidden = true,
--     hide_numbers = true,
--     float_opts = {
--       winblend = 0,
--       width = function()
--         return math.ceil(vim.o.columns * 0.85)
--       end,
--       height = function()
--         return math.ceil(vim.o.lines * 0.75)
--       end,
--       shell = OS.shell,
--       highlights = {
--         border = 'FloatBorder',
--         background = 'NormalFloat',
--       },
--     },
--     close_on_exit = false,
--
--     on_open = function(t)
--       local hl = { bg = '#80a3d4', fg = '#000000' }
--
--       if hl then
--         vim.api.nvim_set_hl(0, 'MyWinBar', { bg = hl.bg, fg = hl.fg })
--         local winBartitle = '%#MyWinBar#' .. title .. '%*'
--         vim.api.nvim_set_option_value('winbar', winBartitle, { scope = 'local', win = t.window })
--
--         vim.schedule(function()
--           vim.api.nvim_set_option_value('winbar', winBartitle, { scope = 'local', win = t.window })
--         end)
--       end
--       vim.keymap.set('t', '<Esc>', [[<C-\><C-n>k]], { buffer = t.bufnr })
--       vim.keymap.set('n', '<Esc>', [[<C-\><C-n>a]], { buffer = t.bufnr })
--
--       vim.keymap.set('n', 'q', function()
--         PioTermClose(t)
--       end, { desc = 'PioTermClose', buffer = t.bufnr })
--
--       if config.debug then
--         local p_type = M.get_part(t.display_name, 1)
--         local p_win = M.get_part(t.display_name, 2)
--         vim.api.nvim_echo({
--           { 'ToggleTerm ', 'MoreMsg' },
--           { '(Term name: ' .. p_type .. ')', 'MoreMsg' },
--           { '(Prev win ID: ' .. p_win .. ')', 'MoreMsg' },
--           { '(Term Win ID: ' .. t.window .. ')', 'MoreMsg' },
--           { '(Term Buffer#: ' .. t.bufnr .. ')', 'MoreMsg' },
--           { '(Term id: ' .. t.id .. ')', 'MoreMsg' },
--           { '(Job ID: ' .. t.job_id .. ')', 'MoreMsg' },
--         }, true, {})
--       end
--     end,
--
--     on_close = function(t)
--       local orig_win = tonumber(M.get_part(t.display_name, 2))
--       if orig_win and vim.api.nvim_win_is_valid(orig_win) then
--         vim.api.nvim_set_current_win(orig_win)
--       else
--         vim.api.nvim_set_current_win(0)
--       end
--     end,
--
--     -- FIXED GRAMMAR: Stripped the trailing open bracket block comment syntax crash
--     on_create = function(t)
--       local p_type = M.get_part(t.display_name, 1)
--       local platformio = vim.api.nvim_create_augroup(p_type .. '_group', { clear = true })
--
--       vim.api.nvim_create_autocmd('CmdlineLeave', {
--         group = platformio,
--         buffer = t.bufnr,
--         callback = function()
--           if vim.v.event and not vim.v.event.abort and vim.v.event.cmdtype == ':' then
--             local quit = vim.fn.getcmdline() == 'q'
--             local quitbang = vim.fn.getcmdline() == 'q!'
--             if quitbang or quit then
--               local ns_type = M.get_part(t.display_name, 1)
--               local ns_win_str = M.get_part(t.display_name, 2)
--               if quitbang then
--                 if ns_type == 'piomon' then
--                   local exit = vim.api.nvim_replace_termcodes('<C-C>exit', true, true, true)
--                   send(t, exit)
--                 else
--                   send(t, 'exit')
--                 end
--               end
--
--               local orig_win = tonumber(ns_win_str)
--               vim.schedule(function()
--                 if orig_win and vim.api.nvim_win_is_valid(orig_win) then
--                   vim.api.nvim_set_current_win(orig_win)
--                 else
--                   vim.api.nvim_set_current_win(0)
--                 end
--               end)
--             end
--           end
--         end,
--       })
--
--       vim.api.nvim_create_autocmd('BufUnload', {
--         group = platformio,
--         desc = 'toggleterm buffer unloaded',
--         buffer = t.bufnr,
--         callback = function(args)
--           pcall(vim.keymap.del, 't', '<Esc>', { buffer = args.buf })
--           pcall(vim.keymap.del, 'n', '<Esc>', { buffer = args.buf })
--
--           local ns_type = M.get_part(t.display_name, 1)
--           pcall(vim.api.nvim_clear_autocmds, { group = ns_type .. '_group' })
--         end,
--       })
--     end,
--   }
--
--   -- Merging configs safely
--   local final_opts = vim.tbl_deep_extend('force', termConfig, pioOpts or {})
--
--   -- Spawning the ToggleTerm instance via class creation parameters
--   local terminal = require('toggleterm.terminal').Terminal:new(final_opts)
--
--   if prev.term and prev.float then
--     prev.term:close()
--   end
--
--   -- Running the extracted layout igniter helper block cleanly
--   spawn_terminal_instance(terminal, command)
--
--   return terminal
-- end
--
-- return M
--
