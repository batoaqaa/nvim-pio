-- File: lua/nvimpio/utils/term.lua
local M = {}

-- Legacy State Variables for Backwards Compatibility
M.p_mon_b = nil
M.p_cli_b = nil
M.p_mon_c = nil
M.p_cli_c = nil

-- Master Floating State Registry
local portal_state = {
  monitor = { buf = nil, win = nil, chan = nil },
  cli = { buf = nil, win = nil, chan = nil },
}

local layout_group = vim.api.nvim_create_augroup('NvimPioWindowPortalLock', { clear = true })

---High-precision calculation engine to map our layout across the absolute edge grid
local function calculate_bottom_portal_geometry()
  local total_columns = vim.o.columns
  local total_lines = vim.o.lines
  local statusline_height = (vim.o.laststatus > 0) and 1 or 0
  local cmdline_height = vim.o.cmdheight or 1
  local target_height = 15

  local vertical_row_offset = total_lines - target_height - statusline_height - cmdline_height

  return {
    relative = 'editor',
    row = vertical_row_offset,
    col = 0,
    width = total_columns,
    height = target_height,
    style = 'minimal',
    focusable = true,
  }
end

---FIXED: Safely adjusts ONLY the currently focused window line to prevent the 4/5 sizing panic
---@param should_shrink boolean True to shrink the code window, False to restore it
local function adjust_active_workspace_pane(should_shrink)
  local target_height = 15
  local current_win = vim.api.nvim_get_current_win()

  if current_win and vim.api.nvim_win_is_valid(current_win) then
    local config = vim.api.nvim_win_get_config(current_win)
    -- Verify this is a real code window panel and not a pre-existing float
    if config.relative == '' then
      local current_height = vim.api.nvim_win_get_height(current_win)
      if should_shrink then
        -- Gently compress the active window down to leave exactly 15 rows clear
        local new_height = math.max(5, current_height - target_height)
        pcall(vim.api.nvim_win_set_height, current_win, new_height)
      else
        -- Restore it back to full size when the terminal closes
        pcall(vim.api.nvim_win_set_height, current_win, current_height + target_height)
      end
    end
  end
end

---Internal processing engine to toggle the custom floating window layer
local function toggle_terminal_portal(track_type, shell_cmd)
  local track = portal_state[track_type]

  -- 1. IF VISIBLE: Close window layout frame and restore file viewing geometries cleanly
  if track.win and vim.api.nvim_win_is_valid(track.win) then
    pcall(vim.api.nvim_win_close, track.win, true)
    track.win = nil
    adjust_active_workspace_pane(false) -- Restore the active code layout panel full screen
    return
  end

  -- 2. BUFFER INTEGRITY FILTER: Recycle active text buffer space safely
  if not track.buf or not vim.api.nvim_buf_is_valid(track.buf) then
    track.buf = vim.api.nvim_create_buf(false, true)
    vim.bo[track.buf].filetype = 'nvimpio-terminal'
    track.chan = nil
  end

  -- Shrink the coding view split line BEFORE popping the float window onto the screen
  adjust_active_workspace_pane(true)

  -- 3. RENDER PORTAL LAYOUT: Open the absolute positioned overlay frame
  local geometry = calculate_bottom_portal_geometry()
  track.win = vim.api.nvim_open_win(track.buf, true, geometry)

  -- HARD CONFIG RESIZE GUARD: Force local options to lock the container size
  -- This tells Neovim's layout engine to freeze this window at 15 lines permanently!
  vim.wo[track.win].winfixheight = true
  vim.wo[track.win].winfixwidth = true
  vim.wo[track.win].wrap = true
  pcall(vim.api.nvim_win_set_height, track.win, 15) -- Enforce exact row geometry height

  -- 4. SPAWN TERMINAL CHANNEL: Run instructions strictly inside fresh buffer streams
  if (not track.chan or track.chan <= 0) and shell_cmd and shell_cmd ~= '' then
    track.chan = vim.fn.termopen(shell_cmd, {
      on_exit = function(_, exit_code)
        vim.schedule(function()
          if track_type == 'cli' and exit_code == 0 then
            if track.win and vim.api.nvim_win_is_valid(track.win) then
              pcall(vim.api.nvim_win_close, track.win, true)
              track.win = nil
              adjust_active_workspace_pane(false)
            end
          end
        end)
      end,
    })
  end

  vim.cmd('startinsert')
end

---The master backwards-compatible gateway function called everywhere in your plugin
---@param command_string string The absolute PlatformIO command instructions string
function M.ToggleTerminal(command_string)
  if not command_string or type(command_string) ~= 'string' or vim.trim(command_string) == '' then
    return false
  end

  local clean_cmd = vim.trim(command_string)
  local track_type = 'cli'

  if clean_cmd:find('monitor') or clean_cmd:find('device list') then
    track_type = 'monitor'
  end

  if not clean_cmd:match('^pio%s') and clean_cmd ~= 'pio' then
    clean_cmd = 'pio ' .. clean_cmd
  end

  toggle_terminal_portal(track_type, clean_cmd)

  local active = portal_state[track_type]
  if track_type == 'monitor' then
    M.p_mon_b = active.buf
    M.p_mon_c = active.chan
  else
    M.p_cli_b = active.buf
    M.p_cli_c = active.chan
  end

  return true
end

-- Re-adjust coordinates dynamically if the user resizes their screen shell
vim.api.nvim_create_autocmd('VimResized', {
  group = layout_group,
  callback = function()
    vim.schedule(function()
      local fresh_geometry = calculate_bottom_portal_geometry()
      for _, track in pairs(portal_state) do
        if track.win and vim.api.nvim_win_is_valid(track.win) then
          pcall(vim.api.nvim_win_set_config, track.win, {
            row = fresh_geometry.row,
            col = fresh_geometry.col,
            width = fresh_geometry.width,
            height = fresh_geometry.height,
          })
          pcall(vim.api.nvim_win_set_height, track.win, 15)
        end
      end
    end)
  end,
})

return M
-- local M = {}
--
-- local pio_cli_buf = nil
-- local pio_mon_buf = nil
-- local pio_cli_win = nil
-- local pio_mon_win = nil
-- local last_active_editor_win = nil
-- local pio_cli_chan = nil
-- local pio_mon_chan = nil
-- local pio_scratch_buf = nil
--
-- local function get_target_height()
--   return math.ceil(vim.o.lines * 0.28)
-- end
--
-- local function GetOrCreateScratch()
--   if not pio_scratch_buf or not vim.api.nvim_buf_is_valid(pio_scratch_buf) then
--     pio_scratch_buf = vim.api.nvim_create_buf(false, true)
--     vim.api.nvim_buf_set_name(pio_scratch_buf, 'PioHiddenCanvas')
--     vim.api.nvim_set_option_value('buftype', 'nofile', { buf = pio_scratch_buf })
--     vim.api.nvim_set_option_value('bufhidden', 'hide', { buf = pio_scratch_buf })
--     vim.api.nvim_set_option_value('swapfile', false, { buf = pio_scratch_buf })
--   end
--   return pio_scratch_buf
-- end
--
-- local function HideTerminalWindow(terminal_type)
--   local win_id = (terminal_type == 'monitor') and pio_mon_win or pio_cli_win
--
--   if not win_id or not vim.api.nvim_win_is_valid(win_id) then
--     local target_buf = (terminal_type == 'monitor') and pio_mon_buf or pio_cli_buf
--     for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
--       if vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) == target_buf then
--         win_id = win
--         break
--       end
--     end
--   end
--
--   if win_id and vim.api.nvim_win_is_valid(win_id) then
--     local scratch = GetOrCreateScratch()
--
--     vim.api.nvim_set_option_value('winfixbuf', false, { scope = 'local', win = win_id })
--     vim.api.nvim_win_set_buf(win_id, scratch)
--     vim.api.nvim_win_set_height(win_id, 0)
--     vim.api.nvim_set_option_value('winbar', '', { scope = 'local', win = win_id })
--     vim.api.nvim_set_option_value('winfixbuf', true, { scope = 'local', win = win_id })
--
--     local safe_target_win = nil
--     if last_active_editor_win and vim.api.nvim_win_is_valid(last_active_editor_win) and last_active_editor_win ~= win_id then
--       local b = vim.api.nvim_win_get_buf(last_active_editor_win)
--       if vim.bo[b].filetype ~= 'neo-tree' and vim.bo[b].filetype ~= 'aerial' then
--         safe_target_win = last_active_editor_win
--       end
--     end
--
--     if not safe_target_win then
--       for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
--         if win ~= win_id and vim.api.nvim_win_is_valid(win) then
--           local buf = vim.api.nvim_win_get_buf(win)
--           if vim.bo[buf].filetype ~= 'neo-tree' and vim.bo[buf].filetype ~= 'aerial' and vim.bo[buf].buftype == '' then
--             safe_target_win = win
--             break
--           end
--         end
--       end
--     end
--
--     if safe_target_win then
--       vim.api.nvim_set_current_win(safe_target_win)
--     end
--   end
--
--   if terminal_type == 'monitor' then
--     pio_mon_win = nil
--   else
--     pio_cli_win = nil
--   end
-- end
--
-- function M.ToggleTerminal(command, terminal_type)
--   local active_win = vim.api.nvim_get_current_win()
--   if active_win ~= pio_cli_win and active_win ~= pio_mon_win then
--     local cur_ft = vim.bo.filetype
--     if cur_ft ~= 'neo-tree' and cur_ft ~= 'aerial' then
--       last_active_editor_win = active_win
--     end
--   end
--
--   if terminal_type == 'monitor' or (command and string.find(command, ' monitor')) then
--     terminal_type = 'monitor'
--   else
--     terminal_type = 'cli'
--   end
--
--   local shared_win = nil
--   local scratch = GetOrCreateScratch()
--   for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
--     if vim.api.nvim_win_is_valid(win) then
--       local b = vim.api.nvim_win_get_buf(win)
--       if b == pio_cli_buf or b == pio_mon_buf or b == scratch then
--         shared_win = win
--         break
--       end
--     end
--   end
--
--   if shared_win then
--     local active_buf = vim.api.nvim_win_get_buf(shared_win)
--     local target_buf = (terminal_type == 'monitor') and pio_mon_buf or pio_cli_buf
--
--     if active_buf == target_buf and vim.api.nvim_win_get_height(shared_win) > 0 then
--       HideTerminalWindow(terminal_type)
--       return
--     end
--   end
--
--   if terminal_type == 'monitor' then
--     pio_cli_win = nil
--   else
--     pio_mon_win = nil
--   end
--
--   local target_buf = (terminal_type == 'monitor') and pio_mon_buf or pio_cli_buf
--
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
--     local shell_cmd = vim.fn.has('win32') == 1 and { 'powershell.exe', '-NoLogo', '-ExecutionPolicy', 'Bypass' } or { vim.o.shell }
--     local job_id = vim.fn.jobstart(shell_cmd, {
--       pty = true,
--       on_stdout = function(_, data)
--         if vim.api.nvim_buf_is_valid(target_buf) and data then
--           local lines = {}
--           for _, line in ipairs(data) do
--             if not (line:find('|| Processing') or line:find('--- forcing') or line:find('--- Terminal')) then
--               table.insert(lines, line)
--             end
--           end
--           if #lines > 0 then
--             vim.api.nvim_chan_send(term_chan_id, table.concat(lines, '\r\n'))
--           end
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
--   local safe_editor_win = nil
--   if last_active_editor_win and vim.api.nvim_win_is_valid(last_active_editor_win) then
--     safe_editor_win = last_active_editor_win
--   else
--     for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
--       if vim.api.nvim_win_is_valid(win) and win ~= shared_win then
--         local b = vim.api.nvim_win_get_buf(win)
--         if vim.bo[b].filetype ~= 'neo-tree' and vim.bo[b].filetype ~= 'aerial' and vim.bo[b].buftype == '' then
--           safe_editor_win = win
--           break
--         end
--       end
--     end
--   end
--
--   if safe_editor_win then
--     vim.api.nvim_set_current_win(safe_editor_win)
--   end
--
--   local final_win = shared_win
--
--   if not final_win or not vim.api.nvim_win_is_valid(final_win) then
--     local old_splitbelow = vim.o.splitbelow
--     vim.o.splitbelow = true
--
--     final_win = vim.api.nvim_open_win(target_buf, true, {
--       split = 'below',
--       win = 0,
--       height = get_target_height(),
--     })
--
--     vim.o.splitbelow = old_splitbelow
--   else
--     vim.api.nvim_set_option_value('winfixbuf', false, { scope = 'local', win = final_win })
--     vim.api.nvim_win_set_buf(final_win, target_buf)
--     vim.api.nvim_win_set_height(final_win, get_target_height())
--     vim.api.nvim_set_current_win(final_win)
--   end
--
--   if terminal_type == 'monitor' then
--     pio_mon_win = final_win
--   else
--     pio_cli_win = final_win
--   end
--
--   vim.cmd('setlocal nonumber norelativenumber signcolumn=no')
--   vim.api.nvim_set_option_value('winfixheight', true, { scope = 'local', win = final_win })
--   vim.api.nvim_set_option_value('winfixbuf', true, { scope = 'local', win = final_win })
--
--   local title = (terminal_type == 'monitor') and 'Pio Monitor' or 'Pio CLI>'
--   local hl = { bg = '#80a3d4', fg = '#000000' }
--   vim.api.nvim_set_hl(0, 'MyWinBar', { bg = hl.bg, fg = '#000000' })
--   local winBartitle = '%#MyWinBar# ' .. title .. ' [Press ;; to Switch | Press q to hide]%*'
--   vim.api.nvim_set_option_value('winbar', winBartitle, { scope = 'local', win = final_win })
--
--   vim.api.nvim_set_current_win(final_win)
--   vim.cmd('noautocmd wincmd J')
--
--   if safe_editor_win and vim.api.nvim_win_is_valid(safe_editor_win) then
--     vim.api.nvim_set_current_win(safe_editor_win)
--   end
--
--   vim.keymap.set('t', '<Esc>', [[<C-\><C-n>]], { buffer = target_buf })
--   vim.keymap.set('n', 'q', function()
--     HideTerminalWindow(terminal_type)
--   end, { buffer = target_buf })
--   vim.keymap.set({ 'n', 't' }, '<C-k>', function()
--     if vim.api.nvim_get_mode().mode == 't' then
--       vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes([[<C-\><C-n>]], true, true, true), 'n', false)
--     end
--     vim.schedule(function()
--       vim.cmd('wincmd k')
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
--   if command and command ~= '' then
--     local active_chan = (terminal_type == 'monitor') and pio_mon_chan or pio_cli_chan
--     if active_chan then
--       vim.api.nvim_chan_send(active_chan, command .. '\r\n')
--     end
--   end
--
--   vim.api.nvim_set_current_win(final_win)
--   vim.cmd('startinsert')
-- end
--
-- vim.keymap.set('n', '<C-h>', '<C-w>h', { silent = true })
-- vim.keymap.set('n', '<C-l>', '<C-w>l', { silent = true })
--
-- vim.keymap.set('n', '<C-j>', function()
--   local cur = vim.api.nvim_get_current_win()
--   if cur ~= pio_cli_win and cur ~= pio_mon_win then
--     local target = pio_cli_win or pio_mon_win
--     if target and vim.api.nvim_win_is_valid(target) and vim.api.nvim_win_get_height(target) > 0 then
--       vim.api.nvim_set_current_win(target)
--       vim.cmd('startinsert')
--       return
--     end
--   end
--   vim.cmd('wincmd j')
-- end, { silent = true })
--
-- vim.keymap.set('n', [[<leader>\gm]], function()
--   M.ToggleTerminal('', 'monitor')
-- end, { silent = true })
-- vim.keymap.set('n', [[<leader>\t]], function()
--   M.ToggleTerminal('', 'cli')
-- end, { silent = true })
--
-- return M
