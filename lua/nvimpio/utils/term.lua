local M = {}

local config = require('nvimpio').config

-- Assigned dynamically by external sub-modules like 'platformio.utils.pio'
M.stdout_callback = nil
M.exit_callback = nil

-- Persistent background storage buffers for running shell processes
local pio_cli_buf = nil
local pio_mon_buf = nil

-- Display window tracking handles
local pio_cli_win = nil
local pio_mon_win = nil

-- HARD-LOCK HEIGHT PROFILE METRIC: Stores the static target height globally
local target_panel_height = 0

-- Text history buffer accumulators scoped safely at the module file-level
local pio_buffer = ''
local content = ''

----------------------------------------------------------------------------------------
-- INFO: Safe terminal exit routine (Tied to pressing 'q' inside normal mode)
local function SafeCloseTerminal(buf_id)
  if buf_id and vim.api.nvim_buf_is_valid(buf_id) then
    local win_id = vim.fn.bufwinid(buf_id)
    if win_id and win_id ~= -1 and vim.api.nvim_win_is_valid(win_id) then
      vim.api.nvim_win_close(win_id, true)
      -- Force standard workspace windows to balance their layout spacing evenly once on close
      vim.schedule(function()
        vim.cmd('wincmd =')
      end)
    end
  end
end

----------------------------------------------------------------------------------------
-- INFO: Core Layout Spawner (Global Edge-Anchored Window Partition Architecture)
function M.ToggleTerminal(command, terminal_type)
  -- 1. Enforce strict title header assignments immediately at the top
  local title = ''
  if terminal_type == 'monitor' or (command and string.find(command, ' monitor')) then
    title = ' Pio Monitor '
    terminal_type = 'monitor'
  else
    title = ' Pio CLI> '
    terminal_type = 'cli'
  end

  local target_win = (terminal_type == 'monitor') and pio_mon_win or pio_cli_win
  local other_win = (terminal_type == 'monitor') and pio_cli_win or pio_mon_win
  local target_buf = (terminal_type == 'monitor') and pio_mon_buf or pio_cli_buf
  local other_buf = (terminal_type == 'monitor') and pio_cli_buf or pio_mon_buf

  -- 2. MUTUAL EXCLUSION ASYNC BRIDGE:
  -- FIXED: If the other terminal panel window is visible, close it and delay the creation
  -- of the new window inside a scheduled callback wrapper. This lets Neovim wipe out
  -- the old window root nodes completely, preventing panels from stacking on top of each other!
  if other_win and vim.api.nvim_win_is_valid(other_win) then
    SafeCloseTerminal(other_buf)
    if terminal_type == 'monitor' then
      pio_cli_win = nil
    else
      pio_mon_win = nil
    end

    -- Defer layout calculations to the next event loop tick to clear space cleanly [INDEX]
    vim.schedule(function()
      M.ToggleTerminal(command, terminal_type)
    end)
    return
  end

  -- 3. ALWAYS-OPEN TARGET ENGINE:
  if target_win and vim.api.nvim_win_is_valid(target_win) then
    vim.api.nvim_set_current_win(target_win)
    pcall(vim.api.nvim_win_set_height, target_win, target_panel_height)

    -- If an execution string macro was explicitly passed, process it immediately
    if command and command ~= '' then
      local job_id = vim.b[target_buf].terminal_job_id
      if job_id then
        vim.fn.chansend(job_id, command .. (vim.fn.has('win32') == 1 and '\r\n' or '\n'))
      end
    end
    return
  end

  -- 4. CLEAN BUFFER PROVISION: Instantiates an unlisted scratch buffer cleanly
  local is_new_buffer = false
  if not target_buf or not vim.api.nvim_buf_is_valid(target_buf) then
    target_buf = vim.api.nvim_create_buf(false, true)
    is_new_buffer = true
    if terminal_type == 'monitor' then
      pio_mon_buf = target_buf
    else
      pio_cli_buf = target_buf
    end
  end

  -- 5. ABSOLUTE GLOBAL GRID TREE CONFIGURATION:
  target_panel_height = math.ceil(vim.o.lines * 0.28)

  local win_opts = {
    split = 'below', -- Directions token to open the partition beneath upper nodes [INDEX]
    win = -1, -- HARDLOCK GRID: Breaks out of local columns into top-level monitor screen frame [INDEX]
    height = target_panel_height,
  }

  -- 6. RENDER THE STABLE WINDOW PANE
  local new_win = vim.api.nvim_open_win(target_buf, true, win_opts)
  if terminal_type == 'monitor' then
    pio_mon_win = new_win
  else
    pio_cli_win = new_win
  end

  -- 7. PROCESS LAUNCHER: Spawns the shell thread strictly after the layout window is alive
  if is_new_buffer then
    -- Detect shell path natively (Prefers pwsh.exe on modern Windows setups)
    local target_shell = vim.o.shell
    if vim.fn.has('win32') == 1 then
      if vim.fn.executable('pwsh.exe') == 1 then
        target_shell = 'pwsh.exe'
      else
        target_shell = 'powershell.exe'
      end
    end

    -- Running jobstart natively while inside the active terminal window context
    vim.fn.jobstart(target_shell, {
      term = true,
      on_stdout = function(job_id, data, event)
        if type(M.stdout_callback) == 'function' then
          M.stdout_callback(job_id, data, event)
        end
      end,
      on_stderr = function(job_id, data, event)
        if type(M.stdout_callback) == 'function' then
          M.stdout_callback(job_id, data, event)
        end
      end,
      on_exit = function()
        if type(M.exit_callback) == 'function' then
          M.exit_callback()
        end
      end,
    })

    -- AUTOMATED VIEWPORT SCROLL REFLOW ENGINE:
    local scroll_group = vim.api.nvim_create_augroup('PioAutoScroll_' .. target_buf, { clear = true })
    vim.api.nvim_create_autocmd({ 'TextChanged', 'TextChangedI' }, {
      group = scroll_group,
      buffer = target_buf,
      callback = function()
        local active_term_win = vim.fn.bufwinid(target_buf)
        if active_term_win and active_term_win ~= -1 and vim.api.nvim_win_is_valid(active_term_win) then
          vim.schedule(function()
            if vim.api.nvim_win_is_valid(active_term_win) then
              vim.api.nvim_win_call(active_term_win, function()
                local mode = vim.api.nvim_get_mode().mode
                if mode == 'n' or mode == 'nt' then
                  vim.cmd('normal! G')
                end
              end)
            end
          end)
        end
      end,
    })
  end

  -- 8. CLEAN SYSTEM WINDOW FLAGS
  vim.cmd('setlocal nonumber norelativenumber signcolumn=no')
  vim.api.nvim_set_option_value('winfixheight', true, { scope = 'local', win = new_win })

  -- 9. FIXED ANTI-SHRINKING VIEWPORT GUARD WITH RACE-CONDITION EXCLUSION
  local pio_group = vim.api.nvim_create_augroup('PioFocusGuard_' .. target_buf, { clear = true })
  vim.api.nvim_create_autocmd('WinEnter', {
    group = pio_group,
    buffer = target_buf,
    callback = function()
      vim.schedule(function()
        local term_win = (terminal_type == 'monitor') and pio_mon_win or pio_cli_win
        if term_win and vim.api.nvim_win_is_valid(term_win) then
          pcall(vim.api.nvim_win_set_height, term_win, target_panel_height)
          local mode = vim.api.nvim_get_mode().mode
          if mode == 'n' or mode == 'nt' then
            vim.cmd('normal! G')
          end
        end
      end)
    end,
  })

  -- 10. VISUAL CUSTOM WINBAR STYLING
  local hl = { bg = '#80a3d4', fg = '#000000' }
  vim.api.nvim_set_hl(0, 'MyWinBar', { bg = hl.bg, fg = hl.fg })
  local winBartitle = '%#MyWinBar#' .. title .. '%*'
  vim.api.nvim_set_option_value('winbar', winBartitle, { scope = 'local', win = new_win })

  -----------------------------------------------------------------------------
  -- LOCAL MAPS (Scoped strictly to this terminal buffer layer instance)
  -----------------------------------------------------------------------------
  vim.keymap.set('t', '<Esc>', [[<C-\><C-n>]], { buffer = target_buf })
  vim.keymap.set('n', 'q', function()
    SafeCloseTerminal(target_buf)
  end, { buffer = target_buf })

  -- CRASH-FREE UPWARD NAVIGATION KEYMAP
  vim.keymap.set({ 'n', 't' }, '<C-k>', function()
    if vim.api.nvim_get_mode().mode == 't' then
      local esc = vim.api.nvim_replace_termcodes([[<C-\><C-n>]], true, true, true)
      vim.api.nvim_feedkeys(esc, 'n', false)
    end
    vim.schedule(function()
      vim.cmd('wincmd k')
    end)
  end, { buffer = target_buf, silent = true })

  -- DOUBLE SEMI-COLON CROSS SWITCHER LOGIC
  vim.keymap.set({ 'n', 't' }, ';;', function()
    if vim.api.nvim_get_mode().mode == 't' then
      local esc = vim.api.nvim_replace_termcodes([[<C-\><C-n>]], true, true, true)
      vim.api.nvim_feedkeys(esc, 'n', false)
    end

    local next_type = (terminal_type == 'monitor') and 'cli' or 'monitor'
    vim.schedule(function()
      M.ToggleTerminal('', next_type)
    end)
  end, { buffer = target_buf, silent = true, desc = 'Switch between PlatformIO terminals' })

  -----------------------------------------------------------------------------
  -- GLOBAL NAVIGATION & RECALL SHORTCUTS
  -----------------------------------------------------------------------------
  vim.keymap.set('n', '<C-h>', '<C-w>h')
  vim.keymap.set('n', '<C-l>', '<C-w>l')

  -- GLOBAL INTERCEPT DOWNWARD MOVEMENT HOOK:
  vim.keymap.set('n', '<C-j>', function()
    vim.schedule(function()
      local cur_win = (terminal_type == 'monitor') and pio_mon_win or pio_cli_win
      if cur_win and vim.api.nvim_win_is_valid(cur_win) then
        vim.api.nvim_set_current_win(cur_win)
        pcall(vim.api.nvim_win_set_height, cur_win, target_panel_height)
        local mode = vim.api.nvim_get_mode().mode
        if mode == 'n' or mode == 'nt' then
          vim.cmd('normal! G')
        end
      else
        vim.cmd('wincmd j')
      end
    end)
  end, { silent = true })

  if terminal_type == 'monitor' then
    vim.keymap.set('n', [[<leader>\gm]], function()
      M.ToggleTerminal('', 'monitor')
    end, { silent = true })
  else
    vim.keymap.set('n', [[<leader>\t]], function()
      M.ToggleTerminal('', 'cli')
    end, { silent = true })
  end
  -----------------------------------------------------------------------------

  -- Automatically run passed command strings via your platformio job channels
  if command and command ~= '' then
    local job_id = vim.b[target_buf].terminal_job_id
    if job_id then
      vim.fn.chansend(job_id, command .. (vim.fn.has('win32') == 1 and '\r\n' or '\n'))
    end
  end
end

return M
-- INFO: Your unmodified parser logic block remains safely out here
