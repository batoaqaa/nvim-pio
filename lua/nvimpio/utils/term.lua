local M = {}

-- Track background process job IDs
local pio_cli_job = nil
local pio_mon_job = nil

-- Keep a history log of outputs so switching views doesn't lose data
local pio_cli_lines = {}
local pio_mon_lines = {}

----------------------------------------------------------------------------------------
-- INFO: Appends process stream logs into the Quickfix window dynamically
local function AppendToQuickfix(lines, terminal_type)
  -- Filter and clean carriage returns from raw terminal output streams
  local clean_lines = {}
  for _, line in ipairs(lines) do
    local clean = line:gsub('\r', '')
    table.insert(clean_lines, { text = clean })
  end

  -- Append to the global quickfix list
  vim.fn.setqflist({}, 'a', {
    title = (terminal_type == 'monitor') and 'PlatformIO Device Monitor' or 'PlatformIO CLI',
    items = clean_lines,
  })
end

----------------------------------------------------------------------------------------
-- INFO: Unified Background Process Pipeline (Pure Global Grid Architecture)
function M.ToggleTerminal(command, terminal_type)
  -- Normalize layout headers and flags
  if terminal_type == 'monitor' or (command and string.find(command, ' monitor')) then
    terminal_type = 'monitor'
  else
    terminal_type = 'cli'
  end

  -- Check if the quickfix window is currently open on screen
  local qf_win = vim.fn.getqflist({ winid = 0 }).winid
  local is_qf_open = qf_win and qf_win ~= 0 and vim.api.nvim_win_is_valid(qf_win)

  -- TOGGLE ACTION: If open, close it and stop execution loop
  if is_qf_open then
    vim.cmd('cclose')
    return
  end

  -- Clear old quickfix entries to display fresh compilation records
  vim.fn.setqflist({}, 'r', {
    title = (terminal_type == 'monitor') and 'PlatformIO Device Monitor' or 'PlatformIO CLI',
    items = {},
  })

  -- Clear memory buffers for the fresh run
  if terminal_type == 'monitor' then
    pio_mon_lines = {}
  else
    pio_cli_lines = {}
  end

  -- Spawn a clean async background thread worker. Requires zero user setups!
  local cmd_to_run = (command and command ~= '') and command or vim.o.shell
  local job_id = vim.fn.jobstart(cmd_to_run, {
    stdout_buffered = false,
    on_stdout = function(_, data)
      if data then
        if terminal_type == 'monitor' then
          for _, l in ipairs(data) do
            table.insert(pio_mon_lines, l)
          end
          AppendToQuickfix(data, 'monitor')
        else
          for _, l in ipairs(data) do
            table.insert(pio_cli_lines, l)
          end
          AppendToQuickfix(data, 'cli')
        end
      end
    end,
    on_stderr = function(_, data)
      if data then
        AppendToQuickfix(data, terminal_type)
      end
    end,
    on_exit = function()
      if terminal_type == 'monitor' then
        pio_mon_job = nil
      else
        pio_cli_job = nil
      end
    end,
  })

  if terminal_type == 'monitor' then
    pio_mon_job = job_id
  else
    pio_cli_job = job_id
  end

  -- Open the native full-width bottom Quickfix panel layout
  local target_height = math.ceil(vim.o.lines * 0.25)
  vim.cmd('botright copen ' .. target_height)
  local new_qf_win = vim.fn.getqflist({ winid = 0 }).winid

  -- Hard-lock the height boundary so Aerial or Neo-tree cannot distort it
  if new_qf_win and new_qf_win ~= 0 then
    vim.api.nvim_set_option_value('winfixheight', true, { scope = 'local', win = new_qf_win })
  end

  -----------------------------------------------------------------------------
  -- LOCAL MAPS & SHORTCUT OVERRIDES (Registered dynamically inside the module)
  -----------------------------------------------------------------------------
  vim.keymap.set('n', '<C-h>', '<C-w>h')
  vim.keymap.set('n', '<C-l>', '<C-w>l')
  vim.keymap.set('n', '<C-j>', '<C-w>j')
  vim.keymap.set('n', '<C-k>', '<C-w>k')

  -- DOUBLE SEMI-COLON CROSS SWITCHER LOGIC
  -- Swaps the quickfix log pipeline between your CLI stream and Monitor stream instantly
  vim.keymap.set('n', ';;', function()
    local next_type = (terminal_type == 'monitor') and 'cli' or 'monitor'
    vim.cmd('cclose') -- Close current pane layout
    vim.schedule(function()
      -- Recall the other stream view layer cleanly
      local cached_items = (next_type == 'monitor') and pio_mon_lines or pio_cli_lines
      vim.fn.setqflist({}, 'r', {
        title = (next_type == 'monitor') and 'PlatformIO Device Monitor' or 'PlatformIO CLI',
        items = cached_items,
      })
      vim.cmd('botright copen ' .. target_height)
    end)
  end, { silent = true, desc = 'Switch between PlatformIO logs' })

  if terminal_type == 'monitor' then
    vim.keymap.set('n', [[<leader>\gm]], function()
      M.ToggleTerminal('', 'monitor')
    end, { silent = true })
  else
    vim.keymap.set('n', [[<leader>\t]], function()
      M.ToggleTerminal('', 'cli')
    end, { silent = true })
  end
end

return M
