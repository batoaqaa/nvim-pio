local M = {}

-- Background tracking slots for running buffers and window handles
local pio_cli_buf = nil
local pio_mon_buf = nil
local pio_cli_win = nil
local pio_mon_win = nil
local last_active_editor_win = nil

-- Memory slots to track active job channel IDs for clean input sending
local pio_cli_chan = nil
local pio_mon_chan = nil

----------------------------------------------------------------------------------------
-- CLEAN EXIT LOGIC: Disarms hardware protection shields and closes layout splits cleanly
local function HideTerminalWindow(terminal_type)
  local win_id = (terminal_type == 'monitor') and pio_mon_win or pio_cli_win
  if win_id and vim.api.nvim_win_is_valid(win_id) then
    -- Lower the shield right before closing to prevent layout validation engine panic
    vim.api.nvim_set_option_value('winfixbuf', false, { scope = 'local', win = win_id })
    vim.api.nvim_win_close(win_id, true)
  end
  if terminal_type == 'monitor' then
    pio_mon_win = nil
  else
    pio_cli_win = nil
  end

  if last_active_editor_win and vim.api.nvim_win_is_valid(last_active_editor_win) then
    vim.api.nvim_set_current_win(last_active_editor_win)
  end
end

----------------------------------------------------------------------------------------
-- CORE STRUCTURAL RUNNER
function M.ToggleTerminal(command, terminal_type)
  local active_win = vim.api.nvim_get_current_win()
  if active_win ~= pio_cli_win and active_win ~= pio_mon_win then
    last_active_editor_win = active_win
  end

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

  -- 1. MUTUAL EXCLUSION: Close opposition split instantly
  if other_win and vim.api.nvim_win_is_valid(other_win) then
    vim.api.nvim_set_option_value('winfixbuf', false, { scope = 'local', win = other_win })
    vim.api.nvim_win_close(other_win, true)
    if terminal_type == 'monitor' then
      pio_cli_win = nil
    else
      pio_mon_win = nil
    end
  end

  -- 2. TOGGLE LOGIC: Close active pane if requested
  if target_win and vim.api.nvim_win_is_valid(target_win) then
    HideTerminalWindow(terminal_type)
    return
  end

  -- 3. INTERACTIVE PTY EMULATION ENGINE
  if not target_buf or not vim.api.nvim_buf_is_valid(target_buf) then
    target_buf = vim.api.nvim_create_buf(false, true)
    if terminal_type == 'monitor' then
      pio_mon_buf = target_buf
    else
      pio_cli_buf = target_buf
    end

    local term_chan_id = vim.api.nvim_open_term(target_buf, {
      on_input = function(_, _, _, data)
        local active_job = (terminal_type == 'monitor') and pio_mon_chan or pio_cli_chan
        if active_job then
          vim.api.nvim_chan_send(active_job, data)
        end
      end,
    })

    local shell_cmd = vim.fn.has('win32') == 1 and { 'powershell.exe', '-NoLogo', '-ExecutionPolicy', 'Bypass' } or { vim.o.shell }

    local job_id = vim.fn.jobstart(shell_cmd, {
      pty = true,
      on_stdout = function(_, data)
        if vim.api.nvim_buf_is_valid(target_buf) and data then
          local lines = {}
          for _, line in ipairs(data) do
            if not (line:find('|| Processing') or line:find('--- forcing') or line:find('--- Terminal')) then
              table.insert(lines, line)
            end
          end
          if #lines > 0 then
            vim.api.nvim_chan_send(term_chan_id, table.concat(lines, '\r\n'))
          end
        end
      end,
      on_exit = function()
        if terminal_type == 'monitor' then
          pio_mon_chan = nil
          pio_mon_buf = nil
        else
          pio_cli_chan = nil
          pio_cli_buf = nil
        end
      end,
    })

    if terminal_type == 'monitor' then
      pio_mon_chan = job_id
    else
      pio_cli_chan = job_id
    end
  end

  -- 4. 🥇 THE NATIVE CORE NESTING INJECTION
  local target_height = math.ceil(vim.o.lines * 0.28)

  -- Save your active editing split before changing focus
  local prev_win = vim.api.nvim_get_current_win()

  -- Force Neovim's layout engine to create a global split spanning the full horizontal width
  vim.cmd('botright split')
  local new_win = vim.api.nvim_get_current_win()

  -- Assign your custom tracking buffer cleanly to this newly minted global bottom frame
  vim.api.nvim_win_set_buf(new_win, target_buf)
  vim.api.nvim_win_set_height(new_win, target_height)

  if terminal_type == 'monitor' then
    pio_mon_win = new_win
  else
    pio_cli_win = new_win
  end

  -- 5. WINDOW PANE DECORATIONS & PROTECTION SHIELDS
  vim.cmd('setlocal nonumber norelativenumber signcolumn=no')

  -- Lock layout dimension footprints so splits above cannot shift or alter the window size
  vim.api.nvim_set_option_value('winfixheight', true, { scope = 'local', win = new_win })
  vim.api.nvim_set_option_value('winfixbuf', true, { scope = 'local', win = new_win })

  local hl = { bg = '#80a3d4', fg = '#000000' }
  vim.api.nvim_set_hl(0, 'MyWinBar', { bg = hl.bg, fg = hl.fg })
  local winBartitle = '%#MyWinBar# ' .. title .. ' [Press ;; to Switch | Press q to hide]%*'
  vim.api.nvim_set_option_value('winbar', winBartitle, { scope = 'local', win = new_win })

  -- 6. BUFFER SPECIFIC MAPS
  vim.keymap.set('t', '<Esc>', [[<C-\><C-n>]], { buffer = target_buf })
  vim.keymap.set('n', 'q', function()
    HideTerminalWindow(terminal_type)
  end, { buffer = target_buf })

  vim.keymap.set({ 'n', 't' }, '<C-k>', function()
    if vim.api.nvim_get_mode().mode == 't' then
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes([[<C-\><C-n>]], true, true, true), 'n', false)
    end
    vim.schedule(function()
      vim.cmd('wincmd k')
    end)
  end, { buffer = target_buf, silent = true })

  vim.keymap.set({ 'n', 't' }, ';;', function()
    if vim.api.nvim_get_mode().mode == 't' then
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes([[<C-\><C-n>]], true, true, true), 'n', false)
    end
    local next_type = (terminal_type == 'monitor') and 'cli' or 'monitor'
    vim.schedule(function()
      M.ToggleTerminal('', next_type)
    end)
  end, { buffer = target_buf, silent = true })

  if command and command ~= '' then
    local active_chan = (terminal_type == 'monitor') and pio_mon_chan or pio_cli_chan
    if active_chan then
      vim.api.nvim_chan_send(active_chan, command .. '\r\n')
    end
  end

  vim.cmd('startinsert')
end

----------------------------------------------------------------------------------------
-- GLOBAL KEYMAP REGISTRY (Saves memory allocations by executing exactly once)
----------------------------------------------------------------------------------------
vim.keymap.set('n', '<C-h>', '<C-w>h', { silent = true })
vim.keymap.set('n', '<C-l>', '<C-w>l', { silent = true })

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

----------------------------------------------------------------------------------------
-- HARD ENFORCEMENT INTERCEPTOR (Prevents Neo-tree/Aerial Window Inversions)
----------------------------------------------------------------------------------------
local group = vim.api.nvim_create_augroup('PioTerminalSplitGuard', { clear = true })

vim.api.nvim_create_autocmd({ 'BufWinEnter', 'BufEnter' }, {
  group = group,
  callback = function(args)
    local current_buf = args.buf

    -- Rule 1: Ignore structural buffers, terminals, tree items, or utility popups
    local bt = vim.bo[current_buf].buftype
    local ft = vim.bo[current_buf].filetype
    if bt ~= '' or ft == 'neo-tree' or ft == 'aerial' then
      return
    end

    -- Identify if either of your custom Pio terminals are currently open and valid
    local pio_win = nil
    local pio_buf = nil
    if pio_cli_win and vim.api.nvim_win_is_valid(pio_cli_win) then
      pio_win = pio_cli_win
      pio_buf = pio_cli_buf
    elseif pio_mon_win and vim.api.nvim_win_is_valid(pio_mon_win) then
      pio_win = pio_mon_win
      pio_buf = pio_mon_buf
    end

    -- Rule 2: Exit immediately if your bottom terminal panel is closed
    if not pio_win or not pio_buf then
      return
    end

    -- Check if Neovim is actively forcing or holding a code file inside the terminal frame window
    local file_leaked_into_terminal_win = (vim.api.nvim_win_get_buf(pio_win) == current_buf)
    local active_win = vim.api.nvim_get_current_win()

    if active_win == pio_win or file_leaked_into_terminal_win then
      -- 1. HARD RESET: Lock down the terminal buffer immediately to prevent the layout from shifting
      vim.api.nvim_win_set_buf(pio_win, pio_buf)

      -- 2. Prevent the layout engine from drawing the split inside the terminal frame
      vim.schedule(function()
        local target_code_win = nil

        -- Verify if your last active editor tracking split is a valid target up top
        if last_active_editor_win and vim.api.nvim_win_is_valid(last_active_editor_win) and last_active_editor_win ~= pio_win then
          local last_ft = vim.bo[vim.api.nvim_win_get_buf(last_active_editor_win)].filetype
          if last_ft ~= 'neo-tree' and last_ft ~= 'aerial' then
            target_code_win = last_active_editor_win
          end
        end

        -- Layout Scan Fallback: Find an available editor slot that isn't a sidebar plugin
        if not target_code_win then
          for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
            if win ~= pio_win and vim.api.nvim_win_is_valid(win) then
              local win_buf = vim.api.nvim_win_get_buf(win)
              local win_ft = vim.bo[win_buf].filetype
              local win_bt = vim.bo[win_buf].buftype

              -- Select only true editing workspace slots
              if win_ft ~= 'neo-tree' and win_ft ~= 'aerial' and win_bt == '' then
                target_code_win = win
                break
              end
            end
          end
        end

        -- 3. Move the file up to your primary workspace columns cleanly
        if target_code_win then
          vim.api.nvim_set_current_win(target_code_win)
          vim.api.nvim_set_current_buf(current_buf)
        else
          -- Universal Fallback: If layout is entirely frozen, force focus upwards out of the terminal block
          if vim.api.nvim_win_is_valid(pio_win) then
            vim.api.nvim_set_current_win(pio_win)
          end
          vim.cmd('wincmd k')
          if vim.api.nvim_get_current_win() ~= pio_win then
            vim.api.nvim_set_current_buf(current_buf)
          else
            vim.cmd('split')
            vim.api.nvim_set_current_buf(current_buf)
          end
        end

        -- 4. Re-enforce and maintain your exact 28% vertical layout floor size profile
        if vim.api.nvim_win_is_valid(pio_win) then
          local target_height = math.ceil(vim.o.lines * 0.28)
          vim.api.nvim_win_set_height(pio_win, target_height)
        end
      end)
    end
  end,
})

return M

-- local M = {}
--
-- -- Background tracking slots for running buffers and window handles
-- local pio_cli_buf = nil
-- local pio_mon_buf = nil
-- local pio_cli_win = nil
-- local pio_mon_win = nil
-- local last_active_editor_win = nil
--
-- -- Memory slots to track active job channel IDs for clean input sending
-- local pio_cli_chan = nil
-- local pio_mon_chan = nil
--
-- ----------------------------------------------------------------------------------------
-- -- SAFELY ESCAPE SIDEBARS: Finds a normal code window to preserve layout geometry
-- local function find_valid_editor_window()
--   local wins = vim.api.nvim_tabpage_list_wins(0)
--   for _, win in ipairs(wins) do
--     if vim.api.nvim_win_is_valid(win) and win ~= pio_cli_win and win ~= pio_mon_win then
--       local buf = vim.api.nvim_win_get_buf(win)
--       local ft = vim.api.nvim_get_option_value('filetype', { buf = buf })
--       local bt = vim.api.nvim_get_option_value('buftype', { buf = buf })
--       if ft ~= 'neo-tree' and ft ~= 'aerial' and bt ~= 'terminal' and bt ~= 'nofile' then
--         return win
--       end
--     end
--   end
--   return nil
-- end
--
-- ----------------------------------------------------------------------------------------
-- -- CLEAN EXIT LOGIC: Closes structural split viewports cleanly and restores focus
-- local function HideTerminalWindow(terminal_type)
--   local win_id = (terminal_type == 'monitor') and pio_mon_win or pio_cli_win
--   if win_id and vim.api.nvim_win_is_valid(win_id) then
--     vim.api.nvim_win_close(win_id, true)
--   end
--   if terminal_type == 'monitor' then
--     pio_mon_win = nil
--   else
--     pio_cli_win = nil
--   end
--
--   if last_active_editor_win and vim.api.nvim_win_is_valid(last_active_editor_win) then
--     vim.api.nvim_set_current_win(last_active_editor_win)
--   end
-- end
--
-- ----------------------------------------------------------------------------------------
-- -- CORE STRUCTURAL RUNNER
-- function M.ToggleTerminal(command, terminal_type)
--   local active_win = vim.api.nvim_get_current_win()
--   if active_win ~= pio_cli_win and active_win ~= pio_mon_win then
--     last_active_editor_win = active_win
--   end
--
--   local title = ''
--   if terminal_type == 'monitor' or (command and string.find(command, ' monitor')) then
--     title = 'Pio Monitor'
--     terminal_type = 'monitor'
--   else
--     title = 'Pio CLI>'
--     terminal_type = 'cli'
--   end
--
--   local target_win = (terminal_type == 'monitor') and pio_mon_win or pio_cli_win
--   local other_win = (terminal_type == 'monitor') and pio_cli_win or pio_mon_win
--   local target_buf = (terminal_type == 'monitor') and pio_mon_buf or pio_cli_buf
--
--   -- 1. MUTUAL EXCLUSION: Close opposition split instantly
--   if other_win and vim.api.nvim_win_is_valid(other_win) then
--     vim.api.nvim_win_close(other_win, true)
--     if terminal_type == 'monitor' then
--       pio_cli_win = nil
--     else
--       pio_mon_win = nil
--     end
--   end
--
--   -- 2. TOGGLE LOGIC: If split panel is currently open, hide it
--   if target_win and vim.api.nvim_win_is_valid(target_win) then
--     HideTerminalWindow(terminal_type)
--     return
--   end
--
--   -- 3. MODERN UNLISTED INTERACTIVE PTY TERMINAL (DEPRECATION FREE)
--   if not target_buf or not vim.api.nvim_buf_is_valid(target_buf) then
--     target_buf = vim.api.nvim_create_buf(false, true)
--     if terminal_type == 'monitor' then
--       pio_mon_buf = target_buf
--     else
--       pio_cli_buf = target_buf
--     end
--
--     local term_chan_id = vim.api.nvim_open_term(target_buf, {
--       on_input = function(_, _, _, data)
--         local active_job = (terminal_type == 'monitor') and pio_mon_chan or pio_cli_chan
--         if active_job then
--           vim.api.nvim_chan_send(active_job, data)
--         end
--       end,
--     })
--
--     local shell_cmd = { vim.o.shell }
--     if vim.fn.has('win32') == 1 then
--       shell_cmd = { 'powershell.exe', '-NoLogo', '-ExecutionPolicy', 'Bypass' }
--     end
--
--     local job_id = vim.fn.jobstart(shell_cmd, {
--       pty = true,
--       on_stdout = function(_, data)
--         if vim.api.nvim_buf_is_valid(target_buf) and data then
--           local lines = {}
--           for _, line in ipairs(data) do
--             local is_garbage = line:find('|| Processing')
--               or line:find('--- forcing')
--               or line:find('--- Terminal')
--               or line:find('--- Available filters')
--               or line:find('--- More details')
--               or line:find('--- Quit:')
--
--             if not is_garbage then
--               table.insert(lines, line)
--             end
--           end
--           if #lines > 0 then
--             local output = table.concat(lines, '\r\n')
--             vim.api.nvim_chan_send(term_chan_id, output)
--           end
--         end
--       end,
--       on_stderr = function(_, data)
--         if vim.api.nvim_buf_is_valid(target_buf) and data then
--           vim.api.nvim_chan_send(term_chan_id, table.concat(data, '\r\n'))
--         end
--       end,
--       on_exit = function()
--         if terminal_type == 'monitor' then
--           pio_mon_chan = nil
--           pio_mon_buf = nil
--         else
--           pio_cli_chan = nil
--           pio_cli_buf = nil
--         end
--       end,
--     })
--
--     if terminal_type == 'monitor' then
--       pio_mon_chan = job_id
--     else
--       pio_cli_chan = job_id
--     end
--   end
--
--   -- 4. THE UNBEATABLE BOTTOM PANEL TILE ANCHOR
--   local target_height = math.ceil(vim.o.lines * 0.28)
--
--   local neutral_win = find_valid_editor_window()
--   if neutral_win then
--     vim.api.nvim_set_current_win(neutral_win)
--   end
--
--   vim.cmd('new')
--   local new_win = vim.api.nvim_get_current_win()
--   vim.api.nvim_win_set_buf(new_win, target_buf)
--
--   vim.cmd('wincmd J')
--   vim.api.nvim_win_set_height(new_win, target_height)
--
--   if terminal_type == 'monitor' then
--     pio_mon_win = new_win
--   else
--     pio_cli_win = new_win
--   end
--
--   -- 5. WINDOW PANE DECORATIONS
--   vim.cmd('setlocal nonumber norelativenumber signcolumn=no')
--   vim.api.nvim_set_option_value('winfixheight', true, { scope = 'local', win = new_win })
--
--   local hl = { bg = '#80a3d4', fg = '#000000' }
--   vim.api.nvim_set_hl(0, 'MyWinBar', { bg = hl.bg, fg = hl.fg })
--   local winBartitle = '%#MyWinBar# ' .. title .. ' [Press ;; to Switch | Press q to hide]%*'
--   vim.api.nvim_set_option_value('winbar', winBartitle, { scope = 'local', win = new_win })
--
--   -- 6. LOCAL SHORTCUTS BOUND ONLY TO THIS BUFFER
--   vim.keymap.set('t', '<Esc>', [[<C-\><C-n>]], { buffer = target_buf })
--   vim.keymap.set('n', 'q', function()
--     HideTerminalWindow(terminal_type)
--   end, { buffer = target_buf })
--
--   vim.keymap.set({ 'n', 't' }, '<C-k>', function()
--     if vim.api.nvim_get_mode().mode == 't' then
--       vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes([[<C-\><C-n>]], true, true, true), 'n', false)
--     end
--     vim.schedule(function()
--       local target = find_valid_editor_window() or last_active_editor_win
--       if target and vim.api.nvim_win_is_valid(target) then
--         vim.api.nvim_set_current_win(target)
--       else
--         vim.cmd('wincmd k')
--       end
--     end)
--   end, { buffer = target_buf, silent = true })
--
--   vim.keymap.set({ 'n', 't' }, ';;', function()
--     if vim.api.nvim_get_mode().mode == 't' then
--       vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes([[<C-\><C-n>]], true, true, true), 'n', false)
--     end
--     local next_type = (terminal_type == 'monitor') and 'cli' or 'monitor'
--     vim.schedule(function()
--       M.ToggleTerminal('', next_type)
--     end)
--   end, { buffer = target_buf, silent = true })
--
--   -- 7. EXECUTE COMMAND STRING IF PRESENT
--   if command and command ~= '' then
--     local active_chan = (terminal_type == 'monitor') and pio_mon_chan or pio_cli_chan
--     if active_chan then
--       vim.api.nvim_chan_send(active_chan, command .. '\r\n')
--     end
--   end
--
--   vim.cmd('startinsert')
-- end
--
-- ----------------------------------------------------------------------------------------
-- -- 🛡️ UNBREAKABLE RE-ENFORCEMENT SHIELD LOOP (FORCES HORIZONTAL BOTTOM)
-- ----------------------------------------------------------------------------------------
-- local layout_shield_group = vim.api.nvim_create_augroup('PioTerminalLayoutShield', { clear = true })
-- vim.api.nvim_create_autocmd({ 'WinNew', 'BufWinEnter' }, {
--   group = layout_shield_group,
--   callback = function()
--     vim.schedule(function()
--       local active_term_win = pio_cli_win or pio_mon_win
--       if active_term_win and vim.api.nvim_win_is_valid(active_term_win) then
--         local target_height = math.ceil(vim.o.lines * 0.28)
--         local current_width = vim.api.nvim_win_get_width(active_term_win)
--
--         if current_width < vim.o.columns then
--           local cur_win = vim.api.nvim_get_current_win()
--           if cur_win == active_term_win or vim.api.nvim_win_get_buf(cur_win) ~= (pio_cli_buf or pio_mon_buf) then
--             local rogue_buf = vim.api.nvim_win_get_buf(cur_win)
--             local valid_editor = find_valid_editor_window()
--
--             if valid_editor then
--               vim.api.nvim_win_set_buf(valid_editor, rogue_buf)
--               vim.api.nvim_set_current_win(valid_editor)
--               vim.api.nvim_win_close(cur_win, true)
--             end
--           end
--
--           vim.api.nvim_set_current_win(active_term_win)
--           vim.cmd('wincmd J')
--           vim.api.nvim_win_set_height(active_term_win, target_height)
--
--           local restored_editor = find_valid_editor_window()
--           if restored_editor then
--             vim.api.nvim_set_current_win(restored_editor)
--           end
--         end
--       end
--     end)
--   end,
-- })
--
-- ----------------------------------------------------------------------------------------
-- -- GLOBAL SHORTCUT INITIALIZATIONS
-- ----------------------------------------------------------------------------------------
-- vim.keymap.set('n', '<C-h>', '<C-w>h', { silent = true })
-- vim.keymap.set('n', '<C-l>', '<C-w>l', { silent = true })
--
-- vim.keymap.set('n', '<C-j>', function()
--   if pio_cli_win and vim.api.nvim_win_is_valid(pio_cli_win) then
--     vim.api.nvim_set_current_win(pio_cli_win)
--     vim.cmd('startinsert')
--   elseif pio_mon_win and vim.api.nvim_win_is_valid(pio_mon_win) then
--     vim.api.nvim_set_current_win(pio_mon_win)
--     vim.cmd('startinsert')
--   else
--     vim.cmd('wincmd j')
--   end
-- end, { silent = true })
--
-- vim.keymap.set('n', [[\gm]], function()
--   M.ToggleTerminal('', 'monitor')
-- end, { silent = true })
-- vim.keymap.set('n', [[\t]], function()
--   M.ToggleTerminal('', 'cli')
-- end, { silent = true })
-- return M
