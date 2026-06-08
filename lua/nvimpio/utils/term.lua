-- File: lua/nvimpio/utils/term.lua
local M = {}

-- Legacy State Variables for Backwards Compatibility across your files
M.p_mon_b = nil
M.p_cli_b = nil
M.p_mon_c = nil
M.p_cli_c = nil

-- Edgy-Style Window & Buffer State Cache Registry
local pane_state = {
  monitor = { buf = nil, win = nil, chan = nil, spacer_win = nil, spacer_buf = nil },
  cli = { buf = nil, win = nil, chan = nil, spacer_win = nil, spacer_buf = nil },
}

local layout_group = vim.api.nvim_create_augroup('NvimPioProxyLayoutEngine', { clear = true })

---Helper to get exact screen coordinates of a specific window split pane
local function get_win_geometry(win_id)
  if not win_id or not vim.api.nvim_win_is_valid(win_id) then
    return nil
  end
  local pos = vim.api.nvim_win_get_position(win_id) -- returns {row, col}
  local width = vim.api.nvim_win_get_width(win_id)
  local height = vim.api.nvim_win_get_height(win_id)
  return { row = pos[1], col = pos[2], width = width, height = height }
end

---Internal processing engine to toggle the layout-locked proxy terminal pane cleanly
local function toggle_bottom_pane(track_type, shell_cmd)
  local track = pane_state[track_type]

  -- 1. IF PANE IS VISIBLE: Gracefully close both the float portal and the structural spacer split
  if track.win and vim.api.nvim_win_is_valid(track.win) then
    pcall(vim.api.nvim_win_close, track.win, true)
    track.win = nil
    if track.spacer_win and vim.api.nvim_win_is_valid(track.spacer_win) then
      pcall(vim.api.nvim_win_close, track.spacer_win, true)
      track.spacer_win = nil
    end
    return
  end

  -- Cache your active text writing cursor window context safely before any operations
  local initial_active_win = vim.api.nvim_get_current_win()

  -- 2. STAGE A: CREATE THE STRUCTURAL SPACER SPLIT
  -- This forces code windows to physically shrink up, ensuring code never overlaps!
  if not track.spacer_buf or not vim.api.nvim_buf_is_valid(track.spacer_buf) then
    track.spacer_buf = vim.api.nvim_create_buf(false, true)
    vim.bo[track.spacer_buf].buftype = 'nofile'
    vim.bo[track.spacer_buf].bufhidden = 'hide'
    vim.bo[track.spacer_buf].swapfile = false
    vim.api.nvim_buf_set_name(track.spacer_buf, 'PlatformIO_Dock_Spacer_' .. track_type)
  end

  -- Raise the safety shield flag to completely mute background upkeep scripts during mutations
  if _G.metadata then
    _G.metadata.isShiftingLayout = true
  end

  -- Spawn ordinary lower layout split box
  vim.cmd('botright split')
  track.spacer_win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(track.spacer_win, track.spacer_buf)
  vim.cmd('resize 15')

  -- Hard-lock spacer geometry parameters layout filters natively
  vim.wo[track.spacer_win].winfixheight = true
  vim.wo[track.winfixwidth] = true
  vim.wo[track.spacer_win].winhighlight = 'Normal:NormalSB,SignColumn:NormalSB'

  -- 3. STAGE B: CREATE THE ORE TERMINAL CHANNEL STREAM
  if not track.buf or not vim.api.nvim_buf_is_valid(track.buf) then
    track.buf = vim.api.nvim_create_buf(false, true)
    vim.bo[track.buf].filetype = 'nvimpio-terminal'
    track.chan = nil
  end

  -- 4. STAGE C: DROP OVERLAY PORTAL WINDOW EXACTLY ON TOP OF SPACER
  local geo = get_win_geometry(track.spacer_win)
  if geo then
    track.win = vim.api.nvim_open_win(track.buf, true, {
      relative = 'editor',
      row = geo.row,
      col = geo.col,
      width = geo.width,
      height = geo.height,
      style = 'minimal',
      focusable = true,
    })
  end

  -- Spawn the interactive terminal shell execution channel natively
  if (not track.chan or track.chan <= 0) and shell_cmd and shell_cmd ~= '' then
    track.chan = vim.fn.termopen(shell_cmd, {
      on_exit = function(_, exit_code)
        vim.schedule(function()
          if track_type == 'cli' and exit_code == 0 then
            if track.win and vim.api.nvim_win_is_valid(track.win) then
              pcall(vim.api.nvim_win_close, track.win, true)
              track.win = nil
            end
            if track.spacer_win and vim.api.nvim_win_is_valid(track.spacer_win) then
              pcall(vim.api.nvim_win_close, track.spacer_win, true)
              track.spacer_win = nil
            end
          end
        end)
      end,
    })
  end

  -- Release the layout state flag lock safely on the next loop tick
  vim.schedule(function()
    if _G.metadata then
      _G.metadata.isShiftingLayout = false
    end
  end)

  -- RESTORE FOCUS INSTANTLY: Return cursor smoothly to the active code file or sidebar tree
  if vim.api.nvim_win_is_valid(initial_active_win) then
    vim.api.nvim_set_current_win(initial_active_win)
  end
end

---The master backwards-compatible gateway function called everywhere in your plugin repository
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

  toggle_bottom_pane(track_type, clean_cmd)

  local active = pane_state[track_type]
  if track_type == 'monitor' then
    M.p_mon_b = active.buf
    M.p_mon_c = active.chan
  else
    M.p_cli_b = active.buf
    M.p_cli_c = active.chan
  end

  return true
end

-- =========================================================================
-- THE WORKSPACE WINDOW PROTECTION GUARD & LAYOUT LOCK
-- =========================================================================
vim.api.nvim_create_autocmd({ 'BufEnter', 'WinResized', 'VimResized' }, {
  group = layout_group,
  callback = function(args)
    local current_win = vim.api.nvim_get_current_win()

    for type_name, track in pairs(pane_state) do
      -- Synchronize Floating Overlay Geometry Bounds to perfectly match the underlying Spacer Pane
      if track.spacer_win and vim.api.nvim_win_is_valid(track.spacer_win) then
        pcall(vim.api.nvim_win_set_height, track.spacer_win, 15)

        local geo = get_win_geometry(track.spacer_win)
        if geo and track.win and vim.api.nvim_win_is_valid(track.win) then
          pcall(vim.api.nvim_win_set_config, track.win, {
            relative = 'editor',
            row = geo.row,
            col = geo.col,
            width = geo.width,
            height = geo.height,
          })
        end
      end

      -- HIJACK INTERCEPTOR GATEWAY:
      -- If Neo-tree attempts to open a file inside our underlying structural spacer split window slot,
      -- intercept it immediately, clear the console pane, and evict the code file up to editing view splits!
      if track.spacer_win and current_win == track.spacer_win and args.buf ~= track.spacer_buf then
        local leaked_buf = args.buf

        vim.schedule(function()
          -- Put the structural spacer buffer back into its proper window frame instantly
          if vim.api.nvim_win_is_valid(track.spacer_win) and vim.api.nvim_buf_is_valid(track.spacer_buf) then
            vim.api.nvim_win_set_buf(track.spacer_win, track.spacer_buf)
          end

          -- Evict the leaked file into a valid upper code window split pane
          local target_win = nil
          for _, w in ipairs(vim.api.nvim_list_wins()) do
            if w ~= track.spacer_win and w ~= track.win then
              local b = vim.api.nvim_win_get_buf(w)
              local ft = vim.bo[b].filetype
              local bt = vim.bo[b].buftype
              if bt == '' and ft ~= 'neo-tree' and ft ~= 'NvimTree' then
                target_win = w
                break
              end
            end
          end

          if target_win then
            vim.api.nvim_set_current_win(target_win)
            vim.api.nvim_win_set_buf(target_win, leaked_buf)
          else
            -- Empty Workspace Fix (Only Neo-Tree and Spacer are active)
            local neotree_win = nil
            for _, w in ipairs(vim.api.nvim_list_wins()) do
              if w ~= track.spacer_win and w ~= track.win then
                neotree_win = w
                break
              end
            end

            if neotree_win and vim.api.nvim_win_is_valid(neotree_win) then
              local code_win = vim.api.nvim_open_win(leaked_buf, true, { split = 'right', win = neotree_win })
              vim.api.nvim_set_current_win(code_win)
            else
              vim.cmd('new')
              pcall(vim.api.nvim_win_set_buf, 0, leaked_buf)
            end
          end
        end)
      end
    end
  end,
})
-- =========================================================================

return M
-- -- File: lua/nvimpio/utils/term.lua
-- local M = {}
--
-- -- Legacy State Variables for Backwards Compatibility across your files
-- M.p_mon_b = nil
-- M.p_cli_b = nil
-- M.p_mon_c = nil
-- M.p_cli_c = nil
--
-- -- Master Floating State Registry
-- local portal_state = {
--   monitor = { buf = nil, win = nil, chan = nil },
--   cli = { buf = nil, win = nil, chan = nil },
-- }
--
-- local layout_group = vim.api.nvim_create_augroup('NvimPioAbsoluteDockPortal', { clear = true })
--
-- ---High-precision calculation engine to map our layout across the absolute edge grid
-- local function calculate_bottom_portal_geometry()
--   local total_columns = vim.o.columns
--   local total_lines = vim.o.lines
--   local statusline_height = (vim.o.laststatus > 0) and 1 or 0
--   local cmdline_height = vim.o.cmdheight or 1
--   local target_height = 15
--
--   local vertical_row_offset = total_lines - target_height - statusline_height - cmdline_height
--
--   return {
--     relative = 'editor', -- Pins layout to the root screen, NOT individual tabs/splits
--     row = vertical_row_offset,
--     col = 0,
--     width = total_columns,
--     height = target_height,
--     style = 'minimal', -- Suppresses line numbers, sign columns, and fold gutters natively
--     focusable = true,
--   }
-- end
--
-- ---CRITICAL SHIELD MECHANISM: Toggles global rendering offsets so text never overlaps
-- ---@param active boolean True to inject padding spacing, False to clear it
-- local function toggle_workspace_viewport_bounds(active)
--   -- We use window-local options to shift text rows up by 15 lines safely
--   for _, win in ipairs(vim.api.nvim_list_wins()) do
--     if vim.api.nvim_win_is_valid(win) then
--       local config = vim.api.nvim_win_get_config(win)
--       if config.relative == '' then -- Only manipulate normal code window split panes
--         if active then
--           vim.wo[win].scrolloff = 15 -- Forces Neovim to push your active code text ABOVE the terminal float!
--         else
--           vim.wo[win].scrolloff = 0
--         end
--       end
--     end
--   end
-- end
--
-- ---Internal processing engine to toggle the custom floating window layer
-- local function toggle_terminal_portal(track_type, shell_cmd)
--   local track = portal_state[track_type]
--
--   -- 1. IF PORTAL IS CURRENTLY VISIBLE: Hide it safely by destroying ONLY the window border frame
--   if track.win and vim.api.nvim_win_is_valid(track.win) then
--     pcall(vim.api.nvim_win_close, track.win, true)
--     track.win = nil
--     toggle_workspace_viewport_bounds(false) -- Let code expand back down full screen
--     return
--   end
--
--   -- 2. BUFFER LIFECYCLE MANAGEMENT: Re-use the existing active buffer text stream if valid
--   if not track.buf or not vim.api.nvim_buf_is_valid(track.buf) then
--     track.buf = vim.api.nvim_create_buf(false, true) -- Unlisted scratchpad container
--     vim.bo[track.buf].filetype = 'nvimpio-terminal'
--
--     -- Tell Neovim's window coordinator that this buffer is a system panel
--     vim.bo[track.buf].buftype = 'nofile'
--     vim.bo[track.buf].bufhidden = 'hide'
--     track.chan = nil
--   end
--
--   -- Enforce text view restrictions before rendering the portal layout
--   toggle_workspace_viewport_bounds(true)
--
--   -- 3. GEOMETRY COMPILATION: Render the floating window portal pinned across the bottom edge
--   local geometry = calculate_bottom_portal_geometry()
--   track.win = vim.api.nvim_open_win(track.buf, true, geometry)
--
--   -- Apply sticky formatting properties to the local window structure profile
--   vim.wo[track.win].winfixheight = true
--   vim.wo[track.win].winfixwidth = true
--   vim.wo[track.win].wrap = true
--
--   -- 4. PROCESS INITIALIZATION: Spawn the shell task ONLY if it is a fresh stream
--   if (not track.chan or track.chan <= 0) and shell_cmd and shell_cmd ~= '' then
--     track.chan = vim.fn.termopen(shell_cmd, {
--       on_exit = function(_, exit_code)
--         -- Auto-Cleanup Event Hook: Destroy window structures if a CLI run finishes cleanly
--         vim.schedule(function()
--           if track_type == 'cli' and exit_code == 0 then
--             if track.win and vim.api.nvim_win_is_valid(track.win) then
--               pcall(vim.api.nvim_win_close, track.win, true)
--               track.win = nil
--               toggle_workspace_viewport_bounds(false)
--             end
--           end
--         end)
--       end,
--     })
--   end
--
--   -- Force terminal interface mode to capture keyboard navigation entries immediately
--   vim.cmd('startinsert')
-- end
--
-- ---The master backwards-compatible gateway function called everywhere in your plugin repository
-- ---@param command_string string The absolute PlatformIO command instructions string
-- function M.ToggleTerminal(command_string)
--   if not command_string or type(command_string) ~= 'string' or vim.trim(command_string) == '' then
--     return false
--   end
--
--   local clean_cmd = vim.trim(command_string)
--   local track_type = 'cli'
--
--   -- Automated Execution Router: Distinguish between compile runs and serial hardware streams
--   if clean_cmd:find('monitor') or clean_cmd:find('device list') then
--     track_type = 'monitor'
--   end
--
--   if not clean_cmd:match('^pio%s') and clean_cmd ~= 'pio' then
--     clean_cmd = 'pio ' .. clean_cmd
--   end
--
--   toggle_terminal_portal(track_type, clean_cmd)
--
--   -- Synchronize state changes back to your legacy global tracking variables safely
--   local active = portal_state[track_type]
--   if track_type == 'monitor' then
--     M.p_mon_b = active.buf
--     M.p_mon_c = active.chan
--   else
--     M.p_cli_b = active.buf
--     M.p_cli_c = active.chan
--   end
--
--   return true
-- end
--
-- -- =========================================================================
-- -- HIGH-PERFORMANCE WINDOW RE-ALIGNMENT RESIZE MONITOR
-- -- =========================================================================
-- vim.api.nvim_create_autocmd({ 'VimResized', 'BufEnter' }, {
--   group = layout_group,
--   callback = function()
--     vim.schedule(function()
--       local fresh_geometry = calculate_bottom_portal_geometry()
--
--       for _, track in pairs(portal_state) do
--         if track.win and vim.api.nvim_win_is_valid(track.win) then
--           pcall(vim.api.nvim_win_set_config, track.win, {
--             row = fresh_geometry.row,
--             col = fresh_geometry.col,
--             width = fresh_geometry.width,
--             height = fresh_geometry.height,
--           })
--           toggle_workspace_viewport_bounds(true)
--         end
--       end
--     end)
--   end,
-- })
-- -- =========================================================================
--
-- return M
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
