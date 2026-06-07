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

  -- INFO: set orig_window to current window, or if available get current toggleterm previous window
  local prev = getPreviousWindow(vim.api.nvim_get_current_win())
  local orig_window = prev.orig_window

  if string.find(command, ' monitor') then
    if prev.mon then -- INFO: if previous monitor terminal already opened ==> reopen
      prev.mon.display_name = 'piomon:' .. orig_window
      local win_type = vim.fn.win_gettype(prev.mon.window)
      local win_open = win_type == '' or win_type == 'popup'
      if prev.mon.window and (win_open and vim.api.nvim_win_get_buf(prev.mon.window) == prev.mon.bufnr) then
        vim.api.nvim_set_current_win(prev.mon.window)
      else
        prev.mon:open()
      end
      return prev.mon
    end
    title = 'Pio Monitor: [In normal mode press: q or :q to hide; :q! to quit; :PioTermList to list terminals]'
    pioOpts.display_name = 'piomon:' .. orig_window
    pioOpts.id = 98
    pioOpts.on_stdout = nil
  else -- INFO: if previous cli terminal already opened ==> reopen
    if prev.cli then
      prev.cli.display_name = 'piocli:' .. orig_window
      local win_type = vim.fn.win_gettype(prev.cli.window)
      local win_open = win_type == '' or win_type == 'popup'
      if prev.cli.window and (win_open and vim.api.nvim_win_get_buf(prev.cli.window) == prev.cli.bufnr) then
        vim.api.nvim_set_current_win(prev.cli.window)
      else
        prev.cli:open()
      end
      vim.defer_fn(function()
        if command and command ~= '' then
          send(prev.cli, command)
        end
      end, 50) -- 50ms delay, adjust as needed
      return prev.cli
    end
    title = 'Pio CLI> [In normal mode press: q or :q to hide; :q! to quit; :PioTermList to list terminals]'
    pioOpts.display_name = 'piocli:' .. orig_window
    pioOpts.id = 99

    -- INFO: on_stdout
    pioOpts.on_stdout = function(terminal, job, data, name)
      if type(M.stdout_callback) == 'function' then
        M.stdout_callback(terminal, job, data, name)
      end
    end

    -- INFO: on_stdout
    pioOpts.on_stderr = function(terminal, job, data, name)
      if type(M.stdout_callback) == 'function' then
        M.stdout_callback(terminal, job, data, name)
      end
    end
  end
  pioOpts.direction = direction
  ------------------------------------------------------

  -- INFO: termConfig table start
  local termConfig = {
    hidden = true, -- Start hidden, we'll open it explicitly
    hide_numbers = true,
    -- 1. FORCE HORIZONTAL ENGINE: Hard-lock the base layout to a bottom split layer
    direction = 'horizontal',
    size = function()
      return math.ceil(vim.o.lines * 0.32)
    end,

    -- env = { PATH = vim.env.PATH,},
    float_opts = {
      winblend = 0,
      width = function()
        return math.ceil(vim.o.columns * 0.85)
      end,
      height = function()
        return math.ceil(vim.o.lines * 0.75)
      end,
      -- shell = vim.o.shell,
      shell = OS.shell,
      highlights = {
        border = 'FloatBorder',
        background = 'NormalFloat',
      },
    },
    close_on_exit = false, --closeOnexit,

    -- INFO: on_open()
    on_open = function(t)
      -- 1. Lock the vertical height of this terminal window pane.
      -- This forces Neovim to preserve your horizontal bottom layout
      -- when plugins like Aerial split the workspace vertically above it.
      vim.api.nvim_set_option_value('winfixheight', true, { scope = 'local', win = t.window })

      -- 2. Clean highlight and title bar integration logic
      local hl = { bg = '#80a3d4', fg = '#000000' }

      if hl then
        vim.api.nvim_set_hl(0, 'MyWinBar', { bg = hl.bg, fg = hl.fg })

        local winBartitle = '%#MyWinBar#' .. title .. '%*'
        vim.api.nvim_set_option_value('winbar', winBartitle, { scope = 'local', win = t.window })

        -- Following necessary to solve that some time winbar not showing
        vim.schedule(function()
          vim.api.nvim_set_option_value('winbar', winBartitle, { scope = 'local', win = t.window })
        end)
      end
      vim.keymap.set('t', '<Esc>', [[<C-\><C-n>k]], { buffer = t.bufnr })
      vim.keymap.set('n', '<Esc>', [[<C-\><C-n>a]], { buffer = t.bufnr })
      vim.keymap.set('n', 'q', function()
        PioTermClose(t)
      end, { desc = 'PioTermClose', buffer = t.bufnr })

      if config.debug then
        local name_splt = M.strsplit(t.display_name, ':')
        vim.api.nvim_echo({
          { 'ToggleTerm ', 'MoreMsg' },
          { '(Term name: ' .. name_splt[1] .. ')', 'MoreMsg' },
          { '(Prev win ID: ' .. name_splt[2] .. ')', 'MoreMsg' },
          { '(Term Win ID: ' .. t.window .. ')', 'MoreMsg' },
          { '(Term Buffer#: ' .. t.bufnr .. ')', 'MoreMsg' },
          { '(Term id: ' .. t.id .. ')', 'MoreMsg' },
          { '(Job ID: ' .. t.job_id .. ')', 'MoreMsg' },
        }, true, {})
      end

      -- Optional: A gentle, local equalization check strictly for this window layout
      vim.schedule(function()
        if vim.api.nvim_win_is_valid(t.window) then
          vim.cmd('wincmd =')
        end
      end)
    end,

    -- INFO: on_close()
    on_close = function(t)
      orig_window = tonumber(M.strsplit(t.display_name, ':')[2])
      ---@diagnostic disable-next-line: param-type-mismatch
      if orig_window and vim.api.nvim_win_is_valid(orig_window) then
        vim.api.nvim_set_current_win(orig_window)
      else
        vim.api.nvim_set_current_win(0)
      end
    end,

    -- -- INFO: on_exit()
    -- on_exit = function(_)
    --   exit_callback()
    -- end,

    -- INFO: on_create() {
    on_create = function(t)
      -- Form an isolated workspace event group string name
      local p_type = M.strsplit(t.display_name, ':')[1]
      local splt_1 = p_type or 'pio'
      local platformio = vim.api.nvim_create_augroup(splt_1 .. '_layout_guard', { clear = true })
      -- local platformio = vim.api.nvim_create_augroup(M.strsplit(t.display_name, ':')[1], { clear = true })

      -- PLUGIN ARCHITECTURE PROTECTION ENGINES:
      -- Catch any new window generation event on screen to enforce bottom boundaries
      vim.api.nvim_create_autocmd({ 'WinNew', 'BufWinEnter' }, {
        group = platformio,
        callback = function()
          -- Verify if our terminal buffer is valid and running on screen somewhere
          local term_win = vim.fn.bufwinid(t.bufnr)
          if term_win and term_win ~= -1 and vim.api.nvim_win_is_valid(term_win) then
            -- Micro-schedule execution to wait until the sidebar (Aerial) finishes drawing
            vim.schedule(function()
              if vim.api.nvim_win_is_valid(term_win) then
                -- 1. Cache the user's current cursor window focus location
                local current_focused_win = vim.api.nvim_get_current_win()

                -- 2. Jump focus to our terminal window pane
                vim.api.nvim_set_current_win(term_win)

                -- 3. Hard-lock it to the absolute horizontal bottom edge across all columns
                vim.cmd('wincmd J')

                -- 4. Restore the user's cursor instantly back to where they were typing
                if vim.api.nvim_win_is_valid(current_focused_win) then
                  vim.api.nvim_set_current_win(current_focused_win)
                end
              end
            end)
          end
        end,
      })

      -- INFO: CmdlineLeave
      vim.api.nvim_create_autocmd('CmdlineLeave', {
        group = platformio,
        -- pattern = ':',
        buffer = t.bufnr,
        callback = function()
          if vim.v.event and not vim.v.event.abort and vim.v.event.cmdtype == ':' then
            local quit = vim.fn.getcmdline() == 'q'
            local quitbang = vim.fn.getcmdline() == 'q!'
            if quitbang or quit then
              local name_splt = M.strsplit(t.display_name, ':')
              if quitbang then
                if name_splt[1] == 'piomon' then -- monitor terminal
                  local exit = vim.api.nvim_replace_termcodes('<C-C>exit', true, true, true)
                  send(t, exit)
                else -- cli terminal
                  send(t, 'exit')
                end
              end

              orig_window = tonumber(name_splt[2])
              vim.schedule(function()
                -- go back to previous window
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

      -- INFO: BufUnload
      vim.api.nvim_create_autocmd('BufUnload', {
        group = platformio,
        desc = 'toggleterm buffer unloaded',
        buffer = t.bufnr,
        callback = function(args)
          vim.keymap.del('t', '<Esc>', { buffer = args.buf })
          vim.keymap.del('n', '<Esc>', { buffer = args.buf })

          -- clear autommmand when quit
          vim.api.nvim_clear_autocmds({ group = M.strsplit(t.display_name, ':')[1] })
        end,
      })
    end,
  }
  -- INFO: termConfig table end

  termConfig = vim.tbl_deep_extend('force', termConfig, pioOpts or {})

  -- INFO: create new terminal
  local terminal = require('toggleterm.terminal').Terminal:new(termConfig)
  if prev.term and prev.float then
    prev.term.close()
  end
  terminal:toggle()
  vim.defer_fn(function()
    if command and command ~= '' then
      send(terminal, command)
    end
  end, 50) -- 50ms delay, adjust as needed sgget
  return terminal
end

return M
----------------------------------------------------------------------------------------
