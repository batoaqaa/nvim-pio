local M = {}
local p_cli_b, p_mon_b, p_cli_w, p_mon_w, l_win, p_cli_c, p_mon_c

local function get_h()
  return math.ceil(vim.o.lines * 0.28)
end

local function is_term(w)
  if not w or not vim.api.nvim_win_is_valid(w) then
    return false
  end
  local b = vim.api.nvim_win_get_buf(w)
  return b == p_cli_b or b == p_mon_b
end

local function safe_w()
  if l_win and vim.api.nvim_win_is_valid(l_win) and not is_term(l_win) then
    return l_win
  end
  for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.api.nvim_win_is_valid(w) and not is_term(w) then
      if vim.bo[vim.api.nvim_win_get_buf(w)].buftype == '' then
        return w
      end
    end
  end
  return vim.api.nvim_get_current_win()
end

local function hide_w(t)
  local w = (t == 'monitor') and p_mon_w or p_cli_w
  if not w or not vim.api.nvim_win_is_valid(w) then
    local b = (t == 'monitor') and p_mon_b or p_cli_b
    for _, v in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
      if vim.api.nvim_win_is_valid(v) and vim.api.nvim_win_get_buf(v) == b then
        w = v
        break
      end
    end
  end
  if w and vim.api.nvim_win_is_valid(w) then
    local s = safe_w()
    if s and s ~= w then
      vim.api.nvim_set_current_win(s)
    end
    vim.api.nvim_win_close(w, true)
  end
  if t == 'monitor' then
    p_mon_w = nil
  else
    p_cli_w = nil
  end
end

function M.ToggleTerminal(cmd, t)
  local cur = vim.api.nvim_get_current_win()
  if not is_term(cur) then
    l_win = cur
  end
  t = (t == 'monitor' or (cmd and string.find(cmd, ' monitor'))) and 'monitor' or 'cli'
  for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.api.nvim_win_is_valid(w) then
      local b = vim.api.nvim_win_get_buf(w)
      if b == p_cli_b then
        p_cli_w = w
      elseif b == p_mon_b then
        p_mon_w = w
      end
    end
  end
  local tw = (t == 'monitor') and p_mon_w or p_cli_w
  local ow = (t == 'monitor') and p_cli_w or p_mon_w
  local tb = (t == 'monitor') and p_mon_b or p_cli_b
  if ow and vim.api.nvim_win_is_valid(ow) then
    hide_w((t == 'monitor') and 'cli' or 'monitor')
  end
  if tw and vim.api.nvim_win_is_valid(tw) then
    hide_w(t)
    return
  end
  if not tb or not vim.api.nvim_buf_is_valid(tb) then
    tb = vim.api.nvim_create_buf(false, true)
    if t == 'monitor' then
      p_mon_b = tb
    else
      p_cli_b = tb
    end
    local tc = vim.api.nvim_open_term(tb, {
      on_input = function(_, _, _, d)
        local j = (t == 'monitor') and p_mon_c or p_cli_c
        if j then
          vim.api.nvim_chan_send(j, d)
        end
      end,
    })
    local sh = vim.fn.has('win32') == 1 and { 'powershell.exe', '-NoLogo', '-ExecutionPolicy', 'Bypass' } or { vim.o.shell }
    local jid = vim.fn.jobstart(sh, {
      pty = true,
      on_stdout = function(_, d)
        if vim.api.nvim_buf_is_valid(tb) and d then
          local lines = {}
          for _, l in ipairs(d) do
            if not (l:find('|| Processing') or l:find('--- forcing') or l:find('--- Terminal')) then
              table.insert(lines, l)
            end
          end
          if #lines > 0 then
            vim.api.nvim_chan_send(tc, table.concat(lines, '\r\n'))
          end
        end
      end,
      on_exit = function()
        if t == 'monitor' then
          p_mon_c = nil
          p_mon_b = nil
        else
          p_cli_c = nil
          p_cli_b = nil
        end
      end,
    })
    if t == 'monitor' then
      p_mon_c = jid
    else
      p_cli_c = jid
    end
  end
  local th = get_h()
  local r = vim.o.lines - th - 2
  local fw = vim.api.nvim_open_win(tb, true, {
    relative = 'editor',
    row = r,
    col = 0,
    width = vim.o.columns,
    height = th,
    style = 'minimal',
    focusable = true,
  })
  if t == 'monitor' then
    p_mon_w = fw
  else
    p_cli_w = fw
  end
  vim.cmd('setlocal nonumber norelativenumber signcolumn=no')
  local name = (t == 'monitor') and 'Pio Monitor' or 'Pio CLI>'
  vim.api.nvim_set_hl(0, 'MyWinBar', { bg = '#80a3d4', fg = '#000000' })
  vim.api.nvim_set_option_value('winbar', '%#MyWinBar# ' .. name .. ' [Press ;; to Switch | Press q to hide]%*', { scope = 'local', win = fw })
  vim.keymap.set('t', '<Esc>', [[<C-\><C-n>]], { buffer = tb })
  vim.keymap.set('n', 'q', function()
    hide_w(t)
  end, { buffer = tb })
  vim.keymap.set({ 'n', 't' }, '<C-k>', function()
    if vim.api.nvim_get_mode().mode == 't' then
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes([[<C-\><C-n>]], true, true, true), 'n', false)
    end
    vim.schedule(function()
      hide_w(t)
    end)
  end, { buffer = tb, silent = true })
  vim.keymap.set({ 'n', 't' }, ';;', function()
    if vim.api.nvim_get_mode().mode == 't' then
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes([[<C-\><C-n>]], true, true, true), 'n', false)
    end
    vim.schedule(function()
      M.ToggleTerminal('', (t == 'monitor') and 'cli' or 'monitor')
    end)
  end, { buffer = tb, silent = true })
  if cmd and cmd ~= '' then
    local j = (t == 'monitor') and p_mon_c or p_cli_c
    if j then
      vim.api.nvim_chan_send(j, cmd .. '\r\n')
    end
  end
  vim.api.nvim_set_current_win(fw)
  vim.cmd('startinsert')
end

vim.keymap.set('n', '<C-j>', function()
  local target = pio_cli_win or pio_mon_win
  if target and vim.api.nvim_win_is_valid(target) then
    vim.api.nvim_set_current_win(target)
    vim.cmd('startinsert')
  else
    M.ToggleTerminal('', 'cli')
  end
end, { silent = true })
vim.keymap.set('n', '<leader>\\gm', function()
  M.ToggleTerminal('', 'monitor')
end, { silent = true })
vim.keymap.set('n', '<leader>\\t', function()
  M.ToggleTerminal('', 'cli')
end, { silent = true })
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
