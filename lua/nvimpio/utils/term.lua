local M = {}

-- Memory slots to preserve running terminal process background buffers
local pio_cli_buf = nil
local pio_mon_buf = nil

-- Memory trackers for the floating window handles
local pio_cli_win = nil
local pio_mon_win = nil

----------------------------------------------------------------------------------------
-- INFO: Safe Hide Engine (Tied to pressing 'q' inside normal mode)
local function HideTerminalWindow(terminal_type)
  local target_win = (terminal_type == 'monitor') and pio_mon_win or pio_cli_win
  if target_win and vim.api.nvim_win_is_valid(target_win) then
    vim.api.nvim_win_close(target_win, true)
  end
  if terminal_type == 'monitor' then
    pio_mon_win = nil
  else
    pio_cli_win = nil
  end
end

----------------------------------------------------------------------------------------
-- INFO: Production-Ready Floating Window Engine Anchored to the Monitor Grid
function M.ToggleTerminal(command, terminal_type)
  local target_win = (terminal_type == 'monitor') and pio_mon_win or pio_cli_win
  local other_win = (terminal_type == 'monitor') and pio_cli_win or pio_mon_win
  local target_buf = (terminal_type == 'monitor') and pio_mon_buf or pio_cli_buf

  -- 1. MUTUAL EXCLUSION: If the other terminal panel is visible, clear it out first
  if other_win and vim.api.nvim_win_is_valid(other_win) then
    vim.api.nvim_win_close(other_win, true)
    if terminal_type == 'monitor' then
      pio_cli_win = nil
    else
      pio_mon_win = nil
    end
  end

  -- 2. TOGGLE ACTION: If our target window is already open, hide it
  if target_win and vim.api.nvim_win_is_valid(target_win) then
    vim.api.nvim_win_close(target_win, true)
    if terminal_type == 'monitor' then
      pio_mon_win = nil
    else
      pio_cli_win = nil
    end
    return
  end

  -- 3. VALIDATE BACKGROUND BUFFER: Reuse existing shell or generate a fresh process
  if not target_buf or not vim.api.nvim_buf_is_valid(target_buf) then
    target_buf = vim.api.nvim_create_buf(false, true) -- Creates unlisted background buffer
    if terminal_type == 'monitor' then
      pio_mon_buf = target_buf
    else
      pio_cli_buf = target_buf
    end

    -- Load the native shell thread process into our background slot
    vim.api.nvim_buf_call(target_buf, function()
      vim.fn.termopen(vim.o.shell)
    end)
  end

  -- 4. ABSOLUTE GEOMETRIC CONFIGURATION BOUNDS:
  local target_height = math.ceil(vim.o.lines * 0.28)
  local cmdheight = vim.o.cmdheight or 1

  local win_opts = {
    relative = 'editor', -- Anchors calculation bounds to your monitor frame grid
    style = 'minimal', -- Strips borders, gutters, and native layout overhead
    focusable = true, -- Keeps terminal responsive to user text inputs
    width = vim.o.columns,
    height = target_height,
    row = vim.o.lines - target_height - cmdheight - 1,
    col = 0,
  }

  -- 5. DRAW THE STABLE HORIZONTAL BOTTOM ROW
  local new_win = vim.api.nvim_open_win(target_buf, true, win_opts)
  if terminal_type == 'monitor' then
    pio_mon_win = new_win
  else
    pio_cli_win = new_win
  end

  -- 6. LAYOUT PROTECTION HOOK: Force the window to remain drawn when focus shifts away!
  local platformio = vim.api.nvim_create_augroup('PioL_Guard_' .. terminal_type, { clear = true })

  -- If the user clicks into Neo-tree, a C++ file, or Aerial, this keeps the view intact
  vim.api.nvim_create_autocmd({ 'BufLeave', 'WinLeave' }, {
    group = platformio,
    buffer = target_buf,
    callback = function()
      -- Micro-schedule prevents Neovim from executing unexpected automated hide tasks
      vim.schedule(function()
        if vim.api.nvim_win_is_valid(new_win) then
          -- Re-enforce layout configurations to hold position above background shifts
          pcall(vim.api.nvim_win_set_config, new_win, win_opts)
        end
      end)
    end,
  })

  -- 7. VISUAL CUSTOM WINBAR STYLING
  local hl = { bg = '#80a3d4', fg = '#000000' }
  vim.api.nvim_set_hl(0, 'MyWinBar', { bg = hl.bg, fg = hl.fg })
  local title = (terminal_type == 'monitor') and 'Pio Monitor' or 'Pio CLI>'
  local winBartitle = '%#MyWinBar# ' .. title .. ' [Press q to hide]%*'
  vim.api.nvim_set_option_value('winbar', winBartitle, { scope = 'local', win = new_win })

  -- 8. LOCAL WORKSPACE KEYMAPS
  vim.keymap.set('t', '<Esc>', [[<C-\><C-n>]], { buffer = target_buf })
  vim.keymap.set('n', 'q', function()
    HideTerminalWindow(terminal_type)
  end, { buffer = target_buf })

  -- 9. EXECUTE PENDING PLATFORMIO COMMAND STRINGS
  if command and command ~= '' then
    local job_id = vim.b[target_buf].terminal_job_id
    if job_id then
      vim.fn.chansend(job_id, command .. (vim.fn.has('win32') == 1 and '\r\n' or '\n'))
    end
  end

  -- Drop cursor directly into terminal typing mode
  vim.cmd('startinsert')
end

return M
