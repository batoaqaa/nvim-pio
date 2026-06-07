local M = {}

-- Background memory tracking slots for running shell terminal process buffers
local pio_cli_buf = nil
local pio_mon_buf = nil

-- Display window handles (Kept global inside the file scope)
local pio_cli_win = nil
local pio_mon_win = nil

-- Memory slots to track the active job channel IDs for streaming commands
local pio_cli_chan = nil
local pio_mon_chan = nil

-- Track the previous standard layout window handle to exit floating terminals cleanly
local last_active_editor_win = nil

----------------------------------------------------------------------------------------
-- INFO: Safe Window Closure Logic (Triggered on 'q' or when toggling off)
local function HideTerminalWindow(terminal_type)
  local win_id = (terminal_type == 'monitor') and pio_mon_win or pio_cli_win
  if win_id and vim.api.nvim_win_is_valid(win_id) then
    vim.api.nvim_win_close(win_id, true)
  end
  if terminal_type == 'monitor' then
    pio_mon_win = nil
  else
    pio_cli_win = nil
  end

  -- Restore focus back to the code editor frame upon terminal window closure
  if last_active_editor_win and vim.api.nvim_win_is_valid(last_active_editor_win) then
    vim.api.nvim_set_current_win(last_active_editor_win)
  end
end

----------------------------------------------------------------------------------------
-- INFO: Core Layout Spawner (Global Canvas Layer Architecture)
function M.ToggleTerminal(command, terminal_type)
  -- Cache active focus coordinate anchors before altering editor layouts
  local active_win = vim.api.nvim_get_current_win()
  if active_win ~= pio_cli_win and active_win ~= pio_mon_win then
    last_active_editor_win = active_win
  end

  -- 1. Enforce strict title header assignments immediately at the top
  local title = ''
  if terminal_type == 'monitor' or (command and string.find(command, ' monitor')) then
    title = 'Pio Monitor'
    terminal_type = 'monitor'
  else
    title = 'Pio CLI>'
    terminal_type = 'cli'
  end

  local target_win = (terminal_type == 'monitor') and pio_mon_win or pio_cli_win
  local other_win = (terminal_type == 'monitor') and pio_cli_win or pio_mon_win
  local target_buf = (terminal_type == 'monitor') and pio_mon_buf or pio_cli_buf

  -- 2. MUTUAL EXCLUSION: If the opponent window is visible, hide it first
  if other_win and vim.api.nvim_win_is_valid(other_win) then
    vim.api.nvim_win_close(other_win, true)
    if terminal_type == 'monitor' then
      pio_cli_win = nil
    else
      pio_mon_win = nil
    end
  end

  -- 3. TOGGLE WINDOW ACTION: If this window is open, hide it
  if target_win and vim.api.nvim_win_is_valid(target_win) then
    HideTerminalWindow(terminal_type)
    return
  end

  -- 4. NEW MODERN PROCESS PERSISTENCE LAYER: Completely free of deprecated APIs
  if not target_buf or not vim.api.nvim_buf_is_valid(target_buf) then
    target_buf = vim.api.nvim_create_buf(false, true) -- Unlisted scratch buffer
    if terminal_type == 'monitor' then
      pio_mon_buf = target_buf
    else
      pio_cli_buf = target_buf
    end

    -- Open a modern terminal channel stream natively on the buffer
    local chan_id = vim.api.nvim_open_term(target_buf, {
      on_input = function(_, _, _, data)
        local active_job = (terminal_type == 'monitor') and pio_mon_chan or pio_cli_chan
        if active_job then
          vim.api.nvim_chan_send(active_job, data)
        end
      end,
    })

    -- Compile system execution arguments safely based on OS context
    local cmd_args = {}
    if vim.fn.has('win32') == 1 then
      cmd_args = { vim.o.shell, '/c', command }
    else
      cmd_args = { vim.o.shell, '-c', command }
    end

    -- Start the background process directly running the active command string variable
    local job_id = vim.fn.jobstart(cmd_args, {
      on_stdout = function(_, data)
        if vim.api.nvim_buf_is_valid(target_buf) and data then
          local lines = {}
          for _, line in ipairs(data) do
            -- Stream-safe filtering layer: Skips garbage outputs before they hit the stream
            local is_garbage = line:find('|| Processing')
              or line:find('--- forcing')
              or line:find('--- Terminal')
              or line:find('--- Available filters')
              or line:find('--- More details')
              or line:find('--- Quit:')

            if not is_garbage and line ~= '' then
              table.insert(lines, line)
            end
          end
          if #lines > 0 then
            local output = table.concat(lines, '\r\n') .. '\r\n'
            vim.api.nvim_chan_send(chan_id, output)
          end
        end
      end,
      on_stderr = function(_, data)
        if vim.api.nvim_buf_is_valid(target_buf) and data then
          local output = table.concat(data, '\r\n') .. '\r\n'
          vim.api.nvim_chan_send(chan_id, output)
        end
      end,
      on_exit = function()
        if terminal_type == 'monitor' then
          pio_mon_chan = nil
        else
          pio_cli_chan = nil
        end
      end,
    })

    -- Cache channel pointers globally for execution sending paths
    if terminal_type == 'monitor' then
      pio_mon_chan = job_id
    else
      pio_cli_chan = job_id
    end
  end

  -- 5. ABSOLUTE GEOMETRIC GRID CONFIGURATION:
  local target_height = math.ceil(vim.o.lines * 0.28)
  local cmdheight = vim.o.cmdheight or 1

  local win_opts = {
    relative = 'editor',
    style = 'minimal',
    focusable = true,
    width = vim.o.columns,
    height = target_height,
    row = vim.o.lines - target_height - cmdheight - 1,
    col = 0,
  }

  -- 6. DRAW THE RECTANGLE VIEWPORT OVERLAY
  local new_win = vim.api.nvim_open_win(target_buf, true, win_opts)
  if terminal_type == 'monitor' then
    pio_mon_win = new_win
  else
    pio_cli_win = new_win
  end

  -- 7. PANE OPTION DECORATIONS
  vim.cmd('setlocal nonumber norelativenumber signcolumn=no')
  vim.api.nvim_set_option_value('winfixheight', true, { scope = 'local', win = new_win })

  -- 8. VISUAL WINBAR DECORATIONS
  local hl = { bg = '#80a3d4', fg = '#000000' }
  vim.api.nvim_set_hl(0, 'MyWinBar', { bg = hl.bg, fg = hl.fg })
  local winBartitle = '%#MyWinBar# ' .. title .. ' [Press ;; to Switch | Press q to hide]%*'
  vim.api.nvim_set_option_value('winbar', winBartitle, { scope = 'local', win = new_win })

  -----------------------------------------------------------------------------
  -- LOCAL MAPS (Scoped strictly to this terminal buffer)
  -----------------------------------------------------------------------------
  vim.keymap.set('t', '<Esc>', [[<C-\><C-n>]], { buffer = target_buf })
  vim.keymap.set('n', 'q', function()
    HideTerminalWindow(terminal_type)
  end, { buffer = target_buf })

  -- CRASH-FREE UPWARD NAVIGATION SHORTCUT (Escapes Float Context Cleanly)
  vim.keymap.set({ 'n', 't' }, '<C-k>', function()
    if vim.api.nvim_get_mode().mode == 't' then
      local esc = vim.api.nvim_replace_termcodes([[<C-\><C-n>]], true, true, true)
      vim.api.nvim_feedkeys(esc, 'n', false)
    end
    vim.schedule(function()
      if last_active_editor_win and vim.api.nvim_win_is_valid(last_active_editor_win) then
        vim.api.nvim_set_current_win(last_active_editor_win)
      end
    end)
  end, { buffer = target_buf, silent = true })

  -- DUAL PANEL HOME ROW CROSS SWITCHER (;;)
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

  -- Pass PlatformIO command strings directly through the modern background channel
  if command and command ~= '' then
    local active_chan = (terminal_type == 'monitor') and pio_mon_chan or pio_cli_chan
    if active_chan then
      vim.api.nvim_chan_send(active_chan, command .. (vim.fn.has('win32') == 1 and '\r\n' or '\n'))
    end
  end

  vim.cmd('startinsert')
end

-----------------------------------------------------------------------------
-- ONE-TIME GLOBAL SHORTCUT INITIALIZATIONS (Prevents mapping registry leaks)
-----------------------------------------------------------------------------
vim.keymap.set('n', '<C-h>', '<C-w>h')
vim.keymap.set('n', '<C-l>', '<C-w>l')

vim.keymap.set('n', '<C-j>', function()
  if pio_cli_win and vim.api.nvim_win_is_valid(pio_cli_win) then
    vim.api.nvim_set_current_win(pio_cli_win)
    vim.cmd('startinsert')
  elseif pio_mon_win and vim.api.nvim_win_is_valid(pio_mon_win) then
    vim.api.nvim_set_current_win(pio_mon_win)
    vim.cmd('startinsert')
  else
    vim.cmd('wincmd j')
  end
end, { silent = true })

vim.keymap.set('n', [[<leader>\gm]], function()
  M.ToggleTerminal('', 'monitor')
end, { silent = true })

vim.keymap.set('n', [[<leader>\t]], function()
  M.ToggleTerminal('', 'cli')
end, { silent = true })

return M
