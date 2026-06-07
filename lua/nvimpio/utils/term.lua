---stylua: ignore start
local M = {}

local config = require('nvimpio').config

-- to fix require loop, toggleterm is using stdout_callback function in 'platformio.utils.pio'
-- M.stdout_callback will be assigned by 'platformio.utils.pio'
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

-- 1. Tell the LSP what a "Terminal" object looks like (simplified)
---@class Terminal
---@field id number
---@field bufnr number
---@field window number
---@field close function
---@field toggle function
-- INFO: get previous window
local function getPreviousWindow(orig_window)
  -- 2. Define your context class
  ---@class PioPrevContext
  ---@field term Terminal|nil  -- Handle for horizontal terminal
  ---@field mon Terminal|nil
  ---@field cli Terminal|nil
  ---@field float boolean      -- flag float terminal
  ---@field orig_window number|nil
  local prev = {
    orig_window = orig_window,
    term = nil, --active terminal
    cli = nil, --cli terminal
    mon = nil, --mon terminal
    float = false, --is active terminal direction float
  }
  local terms = require('toggleterm.terminal').get_all(true)
  if #terms ~= 0 then
    for i = 1, #terms do
      if terms[i].display_name and terms[i].display_name ~= '' and terms[i].display_name:find('pio', 1) then
        local name_splt = M.strsplit(terms[i].display_name, ':')
        if name_splt[1] == 'piocli' then
          prev.cli = terms[i]
          if terms[i].window == orig_window then
            ---@diagnostic disable-next-line: cast-local-type
            prev.orig_window = tonumber(name_splt[2]) -- set orig_window to the previous terminal onrig_window
            prev.term = terms[i]
          end
          if terms[i].direction == 'float' then
            prev.float = true
          end
        elseif name_splt[1] == 'piomon' then
          prev.mon = terms[i]
          if terms[i].window == orig_window then
            ---@diagnostic disable-next-line: cast-local-type
            prev.orig_window = tonumber(name_splt[2]) -- set orig_window to the previous terminal onrig_window
            prev.term = terms[i]
          end
          if terms[i].direction == 'float' then
            prev.float = true
          end
        end
      end
    end
  end
  return prev
end

------------------------------------------------------
-- INFO: Send command
local function send(term, cmd)
  vim.fn.chansend(term.job_id, cmd .. OS.eol)
  if vim.api.nvim_buf_is_loaded(term.bufnr) and vim.api.nvim_buf_is_valid(term.bufnr) then
    if term.window and vim.api.nvim_win_is_valid(term.window) then --vim.ui.term_has_open_win(term) then
      vim.api.nvim_set_current_win(term.window) -- terminal focus
      vim.api.nvim_buf_call(term.bufnr, function()
        local mode = vim.api.nvim_get_mode().mode
        if mode == 'n' or mode == 'nt' then
          vim.cmd('normal! G') -- normal command to Goto bottom of buffer (scroll)
        end
      end)
    end
  end
end

------------------------------------------------------
-- INFO: PioTermClose
local function PioTermClose(t)
  local orig_window = tonumber(M.strsplit(t.display_name, ':')[2])
  -- close terminal window
  vim.api.nvim_win_close(t.window, true)

  -- go back to previous window
  if orig_window and vim.api.nvim_win_is_valid(orig_window) then
    vim.api.nvim_set_current_win(orig_window)
  else
    vim.api.nvim_set_current_win(0)
  end
end

------------------------------------------------------
-- INFO: ToggleTerminal

function M.ToggleTerminal(command, direction)
  local status_ok, _ = pcall(require, 'toggleterm')
  if not status_ok then
    vim.api.nvim_echo({ { 'toggleterm not found!', 'ErrorMsg' } }, true, {})
    return
  end

  local title = ''
  local pioOpts = {}

  local prev = getPreviousWindow(vim.api.nvim_get_current_win())
  local orig_window = prev.orig_window

  if string.find(command, ' monitor') then
    if prev.mon then
      if prev.cli then
        prev.cli:close()
      end
      prev.mon.display_name = 'piomon:' .. orig_window

      -- FORCE NATIVE SEPARATION: We explicitly tell Neovim to split horizontally
      -- using a native layout weight rather than letting toggleterm pick.
      prev.mon:open(math.ceil(vim.o.lines * 0.30), 'horizontal')
      return prev.mon
    end
    if prev.cli then
      prev.cli:close()
    end

    title = 'Pio Monitor'
    pioOpts.display_name = 'piomon:' .. orig_window
    pioOpts.id = 98
    pioOpts.on_stdout = nil
  else
    if prev.cli then
      if prev.mon then
        prev.mon:close()
      end
      prev.cli.display_name = 'piocli:' .. orig_window

      -- FORCE NATIVE SEPARATION HERE TOO:
      prev.cli:open(math.ceil(vim.o.lines * 0.30), 'horizontal')
      return prev.cli
    end
    if prev.mon then
      prev.mon:close()
    end

    title = 'Pio CLI>'
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

  -- CONFIGURATION HARD-LOCK
  local termConfig = {
    hidden = true,
    hide_numbers = true,

    -- 1. HARD-LOCK HARDWARE ENGINE TO HORIZONTAL SPLITS ONLY
    direction = 'horizontal',
    size = function()
      return math.ceil(vim.o.lines * 0.30)
    end,
    close_on_exit = false,

    on_open = function(t)
      vim.api.nvim_set_option_value('winfixheight', true, { scope = 'local', win = t.window })

      -- Balance other splits smoothly without causing layout shifts
      vim.cmd('wincmd =')
      -- 2. HARD-LOCK VISUAL BARS: Forces the window pane layout to structural bottom constraints
      vim.cmd('wincmd J')
      vim.api.nvim_set_option_value('winfixheight', true, { scope = 'local', win = t.window })

      -- 3. THE RE-ALIGNMENT HOOK FOR MULTI-SIDEBARS (Aerial, Neo-tree, symbols-outline)
      -- The exact millisecond any plugin tries to squish this workspace column,
      -- this background routine re-locks the terminal horizontally to the base screen grid layer.
      vim.schedule(function()
        if vim.api.nvim_win_is_valid(t.window) then
          local current_focused_win = vim.api.nvim_get_current_win()
          vim.api.nvim_set_current_win(t.window)

          -- Forces the window to stay flat under Aerial and Neo-tree
          vim.cmd('wincmd J')

          if vim.api.nvim_win_is_valid(current_focused_win) then
            vim.api.nvim_set_current_win(current_focused_win)
          end
        end
      end)

      local hl = { bg = '#80a3d4', fg = '#000000' }
      if hl then
        vim.api.nvim_set_hl(0, 'MyWinBar', { bg = hl.bg, fg = hl.fg })
        local winBartitle = '%#MyWinBar#' .. title .. '%*'
        vim.api.nvim_set_option_value('winbar', winBartitle, { scope = 'local', win = t.window })
      end

      vim.keymap.set('t', '<Esc>', [[<C-\><C-n>k]], { buffer = t.bufnr })
      vim.keymap.set('n', '<Esc>', [[<C-\><C-n>a]], { buffer = t.bufnr })
      vim.keymap.set('n', 'q', function()
        PioTermClose(t)
      end, { buffer = t.bufnr })
    end,

    on_close = function(t)
      orig_window = tonumber(M.strsplit(t.display_name, ':'))
      if orig_window and vim.api.nvim_win_is_valid(orig_window) then
        vim.api.nvim_set_current_win(orig_window)
      else
        vim.api.nvim_set_current_win(0)
      end
    end,

    on_create = function(t)
      local platformio = vim.api.nvim_create_augroup(M.strsplit(t.display_name, ':')[1], { clear = true })

      vim.api.nvim_create_autocmd('CmdlineLeave', {
        group = platformio,
        buffer = t.bufnr,
        callback = function()
          if vim.v.event and not vim.v.event.abort and vim.v.event.cmdtype == ':' then
            local quit = vim.fn.getcmdline() == 'q'
            local quitbang = vim.fn.getcmdline() == 'q!'
            if quitbang or quit then
              local name_splt = M.strsplit(t.display_name, ':')
              if quitbang then
                if name_splt == 'piomon' then
                  local exit = vim.api.nvim_replace_termcodes('<C-C>exit', true, true, true)
                  send(t, exit)
                else
                  send(t, 'exit')
                end
              end
              orig_window = tonumber(name_splt)
              vim.schedule(function()
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
          vim.keymap.del('t', '<Esc>', { buffer = args.buf })
          vim.keymap.del('n', '<Esc>', { buffer = args.buf })
          vim.api.nvim_clear_autocmds({ group = M.strsplit(t.display_name, ':')[1] })
        end,
      })
    end,
  }

  termConfig = vim.tbl_deep_extend('force', termConfig, pioOpts or {})
  local terminal = require('toggleterm.terminal').Terminal:new(termConfig)
  if prev.term and prev.float then
    prev.term.close()
  end
  terminal:toggle()
  vim.defer_fn(function()
    if command and command ~= '' then
      send(terminal, command)
    end
  end, 50)
  return terminal
end

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
--   -- INFO: set orig_window to current window, or if available get current toggleterm previous window
--   local prev = getPreviousWindow(vim.api.nvim_get_current_win())
--   local orig_window = prev.orig_window
--
--   if string.find(command, ' monitor') then
--     if prev.mon then -- INFO: if previous monitor terminal already opened ==> reopen
--       prev.mon.display_name = 'piomon:' .. orig_window
--       local win_type = vim.fn.win_gettype(prev.mon.window)
--       local win_open = win_type == '' or win_type == 'popup'
--       if prev.mon.window and (win_open and vim.api.nvim_win_get_buf(prev.mon.window) == prev.mon.bufnr) then
--         vim.api.nvim_set_current_win(prev.mon.window)
--       else prev.mon:open() end
--       return prev.mon
--     end
--     title = 'Pio Monitor: [In normal mode press: q or :q to hide; :q! to quit; :PioTermList to list terminals]'
--     pioOpts.display_name = 'piomon:' .. orig_window
--     pioOpts.id = 98
--     pioOpts.on_stdout = nil
--   else -- INFO: if previous cli terminal already opened ==> reopen
--     if prev.cli then
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
--       end, 50) -- 50ms delay, adjust as needed
--       return prev.cli
--     end
--     title = 'Pio CLI> [In normal mode press: q or :q to hide; :q! to quit; :PioTermList to list terminals]'
--     pioOpts.display_name = 'piocli:' .. orig_window
--     pioOpts.id = 99
--
--     -- INFO: on_stdout
--     pioOpts.on_stdout = function(terminal, job, data, name)
--       if type(M.stdout_callback) == 'function' then
--         M.stdout_callback(terminal, job, data, name)
--       end
--     end
--
--     -- INFO: on_stdout
--     pioOpts.on_stderr = function(terminal, job, data, name)
--       if type(M.stdout_callback) == 'function' then
--         M.stdout_callback(terminal, job, data, name)
--       end
--     end
--   end
--   pioOpts.direction = direction
--   ------------------------------------------------------
--
--   -- INFO: termConfig table start
--   local termConfig = {
--     hidden = true, -- Start hidden, we'll open it explicitly
--     hide_numbers = true,
--
--     -- 1. SWITCH TO GLOBAL FLOATING LAYOUT: This removes the terminal from Neovim's split grid,
--     -- completely protecting it from being pushed or squished by Aerial or Neo-tree.
--     direction = 'float',
--
--     float_opts = {
--       border = 'none', -- Keeps a clean edge--edge terminal look
--
--       -- 2. LOCK HORIZONTAL WIDTH: Forces the float to stretch across 100% of the monitor columns
--       width = function()
--         return vim.o.columns
--       end,
--
--       -- 3. LOCK HEIGHT: Give it a stable height at the bottom of the monitor
--       height = function()
--         return math.ceil(vim.o.lines * 0.30)
--       end,
--
--       -- 4. HARD-LOCK PLACEMENT COORDINATES:
--       row = function()
--         -- Anchors the float exactly to the bottom line of the editor view grid
--         local cmdheight = vim.o.cmdheight or 1
--         return vim.o.lines - math.ceil(vim.o.lines * 0.30) - cmdheight - 1
--         -- return vim.o.lines - math.ceil(vim.o.lines * 0.30) - 2
--       end,
--       col = function()
--         -- Starts at the very left edge of the screen (0)
--         return 0
--       end,
--     },
--     close_on_exit = false, --closeOnexit,
--
--     -- INFO: on_open()
--     on_open = function(t)
--       local hl = { bg = '#80a3d4', fg = '#000000' }
--
--       if hl then
--         vim.api.nvim_set_hl(0, 'MyWinBar', { bg = hl.bg, fg = hl.fg })
--
--         local winBartitle = '%#MyWinBar#' .. title .. '%*'
--         vim.api.nvim_set_option_value('winbar', winBartitle, { scope = 'local', win = t.window })
--
--         -- Following necessary to solve that some time winbar not showing
--         vim.schedule(function()
--           vim.api.nvim_set_option_value('winbar', winBartitle, { scope = 'local', win = t.window })
--         end)
--       end
--       vim.keymap.set('t', '<Esc>', [[<C-\><C-n>k]], { buffer = t.bufnr })
--       vim.keymap.set('n', '<Esc>', [[<C-\><C-n>a]], { buffer = t.bufnr })
--       vim.keymap.set('n', 'q', function() PioTermClose(t) end, { desc = 'PioTermClose', buffer = t.bufnr })
--
--       if config.debug then
--         local name_splt = M.strsplit(t.display_name, ':')
--         vim.api.nvim_echo({
--           { 'ToggleTerm ', 'MoreMsg' },
--           { '(Term name: ' .. name_splt[1] .. ')', 'MoreMsg' },
--           { '(Prev win ID: ' .. name_splt[2] .. ')', 'MoreMsg' },
--           { '(Term Win ID: ' .. t.window .. ')', 'MoreMsg' },
--           { '(Term Buffer#: ' .. t.bufnr .. ')', 'MoreMsg' },
--           { '(Term id: ' .. t.id .. ')', 'MoreMsg' },
--           { '(Job ID: ' .. t.job_id .. ')', 'MoreMsg' },
--         }, true, {})
--       end
--     end,
--
--     -- INFO: on_close()
--     on_close = function(t)
--       orig_window = tonumber(M.strsplit(t.display_name, ':')[2])
--       ---@diagnostic disable-next-line: param-type-mismatch
--       if orig_window and vim.api.nvim_win_is_valid(orig_window) then
--         vim.api.nvim_set_current_win(orig_window)
--       else
--         vim.api.nvim_set_current_win(0)
--       end
--     end,
--
--     -- -- INFO: on_exit()
--     -- on_exit = function(_)
--     --   exit_callback()
--     -- end,
--
--     -- INFO: on_create() {
--     on_create = function(t)
--       -- Form an isolated workspace event group string name
--       local parts = M.strsplit(t.display_name, ':')[1]
--       local group_name = parts[1] or 'pio'
--       local platformio = vim.api.nvim_create_augroup(group_name .. '_layout_guard', { clear = true })
--       -- local platformio = vim.api.nvim_create_augroup(M.strsplit(t.display_name, ':')[1], { clear = true })
--
--       -- PLUGIN ARCHITECTURE PROTECTION ENGINES:
--       -- Catch any new window generation event on screen to enforce bottom boundaries
--       vim.api.nvim_create_autocmd({ "WinNew", "VimResized" }, {
--         group = platformio,
--         callback = function()
--           -- Look up if our specific terminal window handle is visible right now
--           local term_win = vim.fn.bufwinid(t.bufnr)
--           if term_win and term_win ~= -1 and vim.api.nvim_win_is_valid(term_win) then
--
--             -- Micro-schedule ensures we wait until the unknown sidebar finishes drawing
--             vim.schedule(function()
--               if vim.api.nvim_win_is_valid(term_win) then
--                 -- 1. Get total monitor width available in this session
--                 local global_screen_width = vim.o.columns
--
--                 -- 2. SAFE FORCE WIDTH: Instead of running screen-blocking layout shifts (wincmd J),
--                 -- we directly rewrite the window's physical width properties to stretch edge-to-edge.
--                 vim.api.nvim_win_set_width(term_win, global_screen_width)
--
--                 -- 3. Lock the height flag again to secure the top-bottom layout barrier
--                 vim.api.nvim_set_option_value("winfixheight", true, { scope = "local", win = term_win })
--               end
--             end)
--
--           end
--         end,
--       })
--
--       -- INFO: CmdlineLeave
--       vim.api.nvim_create_autocmd('CmdlineLeave', {
--         group = platformio,
--         -- pattern = ':',
--         buffer = t.bufnr,
--         callback = function()
--           if vim.v.event and not vim.v.event.abort and vim.v.event.cmdtype == ':' then
--             local quit = vim.fn.getcmdline() == 'q'
--             local quitbang = vim.fn.getcmdline() == 'q!'
--             if quitbang or quit then
--               local name_splt = M.strsplit(t.display_name, ':')
--               if quitbang then
--                 if name_splt[1] == 'piomon' then -- monitor terminal
--                   local exit = vim.api.nvim_replace_termcodes('<C-C>exit', true, true, true)
--                   send(t, exit)
--                 else -- cli terminal
--                   send(t, 'exit')
--                 end
--               end
--
--               orig_window = tonumber(name_splt[2])
--               vim.schedule(function()
--                 -- go back to previous window
--                 if orig_window and vim.api.nvim_win_is_valid(orig_window) then
--                   vim.api.nvim_set_current_win(orig_window)
--                 else
--                   vim.api.nvim_set_current_win(0)
--                 end
--               end)
--             end
--           end
--         end,
--       })
--
--       -- INFO: BufUnload
--       vim.api.nvim_create_autocmd('BufUnload', {
--         group = platformio,
--         desc = 'toggleterm buffer unloaded',
--         buffer = t.bufnr,
--         callback = function(args)
--           vim.keymap.del('t', '<Esc>', { buffer = args.buf })
--           vim.keymap.del('n', '<Esc>', { buffer = args.buf })
--
--           -- clear autommmand when quit
--           vim.api.nvim_clear_autocmds({ group = M.strsplit(t.display_name, ':')[1] })
--         end,
--       })
--     end,
--   }
--   -- INFO: termConfig table end
--
--   termConfig = vim.tbl_deep_extend('force', termConfig, pioOpts or {})
--
--   -- INFO: create new terminal
--   local terminal = require('toggleterm.terminal').Terminal:new(termConfig)
--   if prev.term and prev.float then
--     prev.term.close()
--   end
--   terminal:toggle()
--   vim.defer_fn(function()
--     if command and command ~= '' then
--       send(terminal, command)
--     end
--   end, 50) -- 50ms delay, adjust as needed sgget
--   return terminal
-- end

return M
----------------------------------------------------------------------------------------
