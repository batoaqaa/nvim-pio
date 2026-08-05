-- stylua: ignore start
-- nvimpio/device/terminal.lua

local M = {}

-- 1. INSULATED TYPE ALIGNMENT MATCH MATRIX
local OS = _G.OS or (pcall(require, 'nvimpio.osInfo') and _G.OS or {})
local native_shell = OS.shell or (vim.fn.has('win32') == 1 and 'pwsh' or 'sh')
local native_eol = OS.eol or '\n'

---@class TerminalKeymaps Specification mapping for all interface operations
---@field hide_pane string Action shortcut to hide the window panel split layout frame
---@field switch_pane string Action shortcut to switch horizontally between terminal tabs
---@field escape_term string Action shortcut to escape interactive terminal input mode
---@field move_up string Boundary navigation focus router shortcut
---@field move_down string Boundary navigation focus router shortcut
---@field move_left string Boundary navigation focus router shortcut
---@field move_right string Boundary navigation focus router shortcut

---@class TerminalConfig Specification matrix for module configurations
---@field panel_height number Sizing percentage for terminal window splits (0.0 to 1.0)
---@field winbar_bg string Hex color mapping for the active winbar background tab highlight
---@field winbar_fg string Hex color mapping for the active winbar foreground text label
---@field winbar_hl_group string Custom namespace identifier for Neovim's highlight database
---@field shell table|string Active system shell environment parsed directly from the OS module spec
---@field keymaps TerminalKeymaps Structured key registration indices dictionary

---@type TerminalConfig
M.config = {
  panel_height = 0.2,
  winbar_bg = '#80a3d4',
  winbar_fg = '#000000',
  winbar_hl_group = 'PioWinBar',
  shell = native_shell,
  keymaps = {
    hide_pane = 'q',
    switch_pane = '<Tab>',
    escape_term = '<Esc>',
    move_up = '<C-k>',
    move_down = '<C-j>',
    move_left = '<C-h>',
    move_right = '<C-l>',
  },
}

---@type fun(job_id: integer, data: string[], event: string)|nil Global module-level output capture hook
M.stdout_callback = nil

---@type table<string, Terminal> Global hash registry for tracking active terminal object definitions
M.terminals = {}

---@class TerminalLayout Matrix for managing terminal split window geometry positioning
---@field container_win integer|nil Explicit native Neovim window handle ID containing the active terminal split panel
---@field active_type string|nil String reference token representing the currently focused terminal pane
M.layout = {
  container_win = nil,
  active_type = nil,
}

-- -- Global layout guard: Physically destroys 3-way vertical parallel columns and forces bottom horizontal layout
-- vim.api.nvim_create_autocmd({ 'BufWinEnter', 'WinEnter', 'WinResized' }, {
--   group = vim.api.nvim_create_augroup('PioGridBreaker', { clear = true }),
--   callback = function()
--     vim.schedule(function()
--       local term_win = M.layout.container_win
--       if not term_win or not vim.api.nvim_win_is_valid(term_win) then
--         return
--       end
--
--       -- Check if the terminal window has been trapped in a vertical column layout
--       local term_width = vim.api.nvim_win_get_width(term_win)
--       local total_width = vim.o.columns
--
--       -- If the terminal width is significantly less than total columns, it's trapped in a vertical 3-way split!
--       if term_width < (total_width - 5) then
--         pcall(function()
--           vim.api.nvim_win_call(term_win, function()
--             -- Force Neovim to rotate/move the terminal window to an absolute bottom row split
--             vim.cmd('wincmd J')
--             -- Fix height to match configured ratio
--             local target_height = math.ceil(vim.o.lines * (M.config.panel_height or 0.2))
--             vim.cmd('resize ' .. target_height)
--           end)
--         end)
--       end
--     end)
--   end,
-- })

--- Pure C-API Highlight winbar renderer (Preserves explicit layout creation order)
---@return nil
function M.UpdateWinbarTitles()
  local maps = M.config.keymaps

  vim.api.nvim_set_hl(0, M.config.winbar_hl_group, { bg = M.config.winbar_bg, fg = M.config.winbar_fg, bold = true })
  vim.api.nvim_set_hl(0, M.config.winbar_hl_group .. 'Dim', { bg = M.config.winbar_bg, fg = '#4e5a6b', italic = true })

  if not M.layout.container_win or not vim.api.nvim_win_is_valid(M.layout.container_win) then
    return
  end

  ---@type Terminal[]
  local ordered_terminals = {}
  for _, term in pairs(M.terminals) do
    if term.buf and vim.api.nvim_buf_is_valid(term.buf) then
      table.insert(ordered_terminals, term)
    end
  end

  table.sort(ordered_terminals, function(a, b)
    return (a._creation_index or 0) < (b._creation_index or 0)
  end)

  local tab_string = string.format('%%#%sDim# ', M.config.winbar_hl_group)
  local total_terminals = 0

  for _, term in ipairs(ordered_terminals) do
    total_terminals = total_terminals + 1
    local name = term.term_type
    if M.layout.active_type == name then
      tab_string = tab_string .. string.format('%%#%s# [%s] %%*', M.config.winbar_hl_group, term.title:gsub('%s+', ''))
    else
      tab_string = tab_string .. string.format('%%#%sDim#  %s  %%*', M.config.winbar_hl_group, term.title:gsub('%s+', ''))
    end
  end

  local hint = (total_terminals > 1) and string.format(' [ %s  Switch;  %s  Hide; :q! Quit ] ', maps.switch_pane, maps.hide_pane)
    or string.format(' [ %s  Hide; :q! Quit ] ', maps.hide_pane)

  vim.api.nvim_set_option_value(
    'winbar',
    string.format('%s%%#%sDim#%%=%s', tab_string, M.config.winbar_hl_group, hint),
    { scope = 'local', win = M.layout.container_win }
  )
end

--- Dynamic Workspace Tree Focus Router Matrix
---@return nil
function M.RestoreWorkspaceFocus()
  local target_win = nil
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.api.nvim_win_is_valid(win) then
      local buf = vim.api.nvim_win_get_buf(win)
      local ft = vim.api.nvim_get_option_value('filetype', { buf = buf })
      local win_type = vim.fn.win_gettype(win)

      if
        ft ~= 'pio_terminal'
        and win_type == ''
        and ft ~= 'neo-tree'
        and ft ~= 'oil'
        and ft ~= 'aerial'
        and ft ~= 'pio_workspace'
        and not ft:match('^terminal_')
      then target_win = win break
      end
    end
  end

  if target_win then vim.api.nvim_set_current_win(target_win) end
end

----------------------------------------------------------------------------------------
-- HIGH-PERFORMANCE OBJECT-ORIENTED TERMINAL SPECIFICATION
----------------------------------------------------------------------------------------
---@class Terminal Object representation mapping for an unlisted isolated terminal channel frame context
---@field term_type string Structured string token name representing the block target layout namespace type (e.g. 'cli', 'mon')
---@field title string Text sequence heading visible inside the C-API winbar layout interface panel
---@field buf integer|nil Unique native identification pointer integer mapping to the active Neovim buffer
---@field job integer|nil Asynchronous backend system process pipe channel identifier integer mapping to termopen
---@field newline string End of line execution delimiter character parsed directly from the system environment
---@field filetype string Explicit workspace identifier tracking signature mapping to Neovim's filetype engine
---@field _custom_stdout fun(job_id: integer, data: string[], event: string)|nil Instance localized text listener output hook callback
---@field _on_next_exit fun()|nil Thread-isolated execution callback hook parsed by send_and_restore macros
---@field _is_scrolling boolean Atomic latch variable used to block high-frequency output dumps from stalling layout streams
---@field _creation_index integer|nil Absolute integer index sequence offset locking winbar alignment orders permanently
local Terminal = {
  term_type = '',
  title = '',
  buf = nil,
  job = nil,
  newline = native_eol,
  filetype = 'pio_terminal',
  _custom_stdout = nil,
  _on_next_exit = nil,
  _is_scrolling = false,
  _creation_index = nil,
}
Terminal.__index = Terminal

--- Factory method instantiating a raw, untainted Terminal object tracking instance node structure
---@param term_type string String identification token mapping (e.g. 'cli', 'mon')
---@param panel_title string UI heading display name text sequence
---@param filetype string|nil Custom structural workspace option signature overrides
---@param custom_stdout fun(job_id: integer, data: string[], event: string)|nil Dedicated buffer channel data listener hook callback
---@return Terminal A finalized object instance adhering completely to the Terminal class template specifications
function Terminal.new(term_type, panel_title, filetype, custom_stdout)
  local self = setmetatable({}, Terminal)
  self.term_type = term_type
  self.title = panel_title
  self.filetype = filetype or ('terminal_' .. term_type)
  self._custom_stdout = custom_stdout
  return self
end

--- Instantiates a pure, untainted native Neovim scratch buffer and encapsulates its termopen execution logic securely
---@return nil
function Terminal:on_create()
  self.buf = vim.api.nvim_create_buf(false, true)

  local target_shell = M.config.shell or native_shell

  if type(target_shell) == 'table' and target_shell.program then
    target_shell = target_shell.program
  end

  vim.api.nvim_buf_call(self.buf, function()
    local channel_id = vim.fn.termopen(target_shell, {
      on_stdout = function(j, d, e) self:on_stdout(j, d, e) end,
      on_stderr = function(j, d, e) self:on_stderr(j, d, e) end,
      on_exit = function() self:on_exit() end,
    })

    self.job = (channel_id and channel_id > 0) and channel_id or nil
  end)

  vim.api.nvim_set_option_value('filetype', self.filetype, { buf = self.buf })
  vim.api.nvim_set_option_value('bufhidden', 'hide', { buf = self.buf })

  pcall(function() vim.b[self.buf].bufferline_deny = true end)

  vim.b[self.buf].pio_term_type = self.term_type

  self:_register_viewport_mappings()
  self:_register_viewport_bindings()
end

--- Pipes an explicit text statement down the asynchronous backend system process pipeline securely
---@param command string|integer Text command statement sequence dispatched downstream into the terminal container pipe
---@return nil
function Terminal:send(command)
  local cmd_str = tostring(command or '')
  local original_work_win = vim.api.nvim_get_current_win()

  if not self.buf or not vim.api.nvim_buf_is_valid(self.buf) then self:on_create() end

  if not M.layout.container_win or not vim.api.nvim_win_is_valid(M.layout.container_win) or M.layout.active_type ~= self.term_type then
    M.show(self.term_type)
  end

  if not self.job or self.job <= 0 then return end
  if cmd_str ~= '' and not cmd_str:match('^%s') then cmd_str = ' ' .. cmd_str end

  vim.fn.chansend(self.job, cmd_str .. self.newline)

  if M.layout.container_win and vim.api.nvim_win_is_valid(M.layout.container_win) and not self._is_scrolling then
    self._is_scrolling = true
    vim.schedule(function()
      if self.buf and vim.api.nvim_buf_is_valid(self.buf) and M.layout.container_win and vim.api.nvim_win_is_valid(M.layout.container_win) then
        local line_count = vim.api.nvim_buf_line_count(self.buf)
        if line_count > 0 then
          pcall(vim.api.nvim_win_set_cursor, M.layout.container_win, { line_count, 0 })
        end
      end
      self._is_scrolling = false
    end)
  end

  if original_work_win and vim.api.nvim_win_is_valid(original_work_win) then
    pcall(vim.api.nvim_set_current_win, original_work_win)
  end
end

--- Internal redirect listener capturing downstream asynchronous standard output arrays from the system process channel
---@param j integer Asynchronous process tracking handler channel ID
---@param d string[] Sequential raw array list data sequence strings representing line entries
---@param e string String descriptor tracking stream execution types (e.g. 'stdout')
---@return nil
function Terminal:on_stdout(j, d, e)
  if self._custom_stdout then
    self._custom_stdout(j, d, e)
  elseif self.term_type == 'cli' and type(M.stdout_callback) == 'function' then
    M.stdout_callback(j, d, e)
  end
end

--- Internal redirect listener capturing downstream asynchronous standard error arrays from the system process channel
---@param j integer Asynchronous process tracking handler channel ID
---@param d string[] Sequential raw array list data sequence strings representing line entries
---@param e string String descriptor tracking stream execution types (e.g. 'stderr')
---@return nil
function Terminal:on_stderr(j, d, e) self:on_stdout(j, d, e) end

--- System framework listener hook executed instantly when the underlying platform process channel closes or terminates
---@return nil
function Terminal:on_exit()
  local cb = self._on_next_exit
  self._on_next_exit = nil

  if cb ~= nil and type(cb) == 'function' then cb() end
  M.UpdateWinbarTitles()
end

--- Turns down the active system process stream channel and wipes the tracking buffer cache cleanly from memory
---@return nil
function Terminal:on_close()
  local tracking_buf = self.buf
  self.job = nil
  self.buf = nil
  self._on_next_exit = nil

  if tracking_buf and vim.api.nvim_buf_is_valid(tracking_buf) then
    pcall(vim.api.nvim_buf_delete, tracking_buf, { force = true })
  end
end

--- Wrapper orchestration function handling channel termination and layout visibility structures concurrently
---@return nil
function Terminal:close()
  self:on_close()
  M.hide()
end


--- Opens a clean split pane layout below your code buffer and attaches this instance context to your canvas view
---@return nil
function Terminal:on_open()
  local target_height = math.ceil(vim.o.lines * (M.config.panel_height or 0.2))
  vim.go.splitkeep = 'screen'

  -- 1. Completely generic sidebar detection using Neovim's window layout engine API 
  -- instead of hardcoding plugin names. We find the window with the smallest width 
  -- that stretches the full height, or simply fallback to the primary active window.
  local best_win = vim.api.nvim_get_current_win()
  local wins = vim.api.nvim_tabpage_list_wins(0)
  
  -- Find a standard editable window (non-floating, normal buftype)
  for _, win in ipairs(wins) do
    if vim.api.nvim_win_is_valid(win) then
      local buf = vim.api.nvim_win_get_buf(win)
      local buftype = vim.api.nvim_get_option_value('buftype', { buf = buf })
      local win_type = vim.fn.win_gettype(win)
      
      if win_type == '' and buftype == '' and buf ~= self.buf then
        best_win = win
        break
      end
    end
  end

  vim.api.nvim_set_current_win(best_win)

  -- 2. Create the split bottom-most globally using standard API primitives
  vim.cmd('botright ' .. target_height .. 'split')
  
  M.layout.container_win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(M.layout.container_win, self.buf)

  M.layout.active_type = self.term_type

  vim.w[M.layout.container_win].pio_managed = true
  vim.api.nvim_set_option_value('winfixheight', true, { scope = 'local', win = M.layout.container_win })
  vim.api.nvim_set_option_value('number', false, { scope = 'local', win = M.layout.container_win })
  vim.api.nvim_set_option_value('relativenumber', false, { scope = 'local', win = M.layout.container_win })
  vim.api.nvim_set_option_value('signcolumn', 'no', { scope = 'local', win = M.layout.container_win })

  self:_register_viewport_mappings()
end


-- -- flicker
-- --- Opens a clean split pane layout below your code buffer and attaches this instance context to your canvas view
-- ---@return nil
-- function Terminal:on_open()
--   local target_height = math.ceil(vim.o.lines * (M.config.panel_height or 0.2))
--   vim.go.splitkeep = 'screen'
--
--   -- Find a valid non-sidebar window to split from, if available
--   local target_win = nil
--   for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
--     if vim.api.nvim_win_is_valid(win) then
--       local buf = vim.api.nvim_win_get_buf(win)
--       local ft = vim.api.nvim_get_option_value('filetype', { buf = buf })
--       local win_type = vim.fn.win_gettype(win)
--       if win_type == '' and ft ~= 'pio_terminal' and not ft:match('^terminal_') then
--         target_win = win
--         break
--       end
--     end
--   end
--
--   -- If we found a proper content window, focus it so the split anchors nicely below code
--   if target_win and vim.api.nvim_win_is_valid(target_win) then
--     vim.api.nvim_set_current_win(target_win)
--   else
--     -- Fallback: if only sidebars exist, jump out of them to avoid vertical column trapping
--     -- pcall(vim.cmd, 'wincmd w')
--     pcall(function () vim.cmd('wincmd w') end)
--   end
--
--   -- Force the split to evaluate as a full-width row at the very bottom of the editor layout
--   vim.cmd('botright ' .. target_height .. 'split')
--
--   M.layout.container_win = vim.api.nvim_get_current_win()
--   vim.api.nvim_win_set_buf(M.layout.container_win, self.buf)
--
--   M.layout.active_type = self.term_type
--
--   vim.w[M.layout.container_win].pio_managed = true
--   vim.api.nvim_set_option_value('winfixheight', true, { scope = 'local', win = M.layout.container_win })
--   vim.api.nvim_set_option_value('number', false, { scope = 'local', win = M.layout.container_win })
--   vim.api.nvim_set_option_value('relativenumber', false, { scope = 'local', win = M.layout.container_win })
--   vim.api.nvim_set_option_value('signcolumn', 'no', { scope = 'local', win = M.layout.container_win })
--
--   self:_register_viewport_mappings()
-- end

--- Maps local interactive hotkeys inside the buffer instance scope boundary context cleanly
---@return nil
function Terminal:_register_viewport_mappings()
  local maps = M.config.keymaps
  vim.keymap.set('t', maps.escape_term, [[<C-\><C-n>]], { buffer = self.buf, silent = true })

  vim.keymap.set('t', maps.switch_pane, function()
    M.SwitchTerminalPane()
  end, { buffer = self.buf, silent = true })
  vim.keymap.set('n', maps.switch_pane, function()
    M.SwitchTerminalPane()
  end, { buffer = self.buf, silent = true })
  vim.keymap.set('n', maps.hide_pane, function()
    M.toggle()
  end, { buffer = self.buf })

  vim.keymap.set('t', maps.move_up, [[<C-\><C-n><C-w>k]], { buffer = self.buf, silent = true })
  vim.keymap.set('n', maps.move_up, '<C-w>k', { buffer = self.buf, silent = true })
  vim.keymap.set('n', maps.move_left, '<C-w>h', { buffer = self.buf })
  vim.keymap.set('n', maps.move_right, '<C-w>l', { buffer = self.buf })
end

--- Binds isolated lifecycle tracking auto-commands to prevent layout leaks or geometry alignment crashes
---@return nil
function Terminal:_register_viewport_bindings()
  local group_id = vim.api.nvim_create_augroup('PioLocalEvents_' .. self.buf, { clear = true })

  vim.api.nvim_create_autocmd({ 'BufWinEnter', 'BufEnter' }, {
    group = group_id,
    buffer = self.buf,
    callback = function()
      if M.layout.container_win and vim.api.nvim_win_is_valid(M.layout.container_win) then
        vim.api.nvim_set_option_value('number', false, { scope = 'local', win = M.layout.container_win })
        vim.api.nvim_set_option_value('relativenumber', false, { scope = 'local', win = M.layout.container_win })
        vim.api.nvim_set_option_value('signcolumn', 'no', { scope = 'local', win = M.layout.container_win })
      end
    end,
  })

  vim.api.nvim_create_autocmd('BufWipeout', {
    group = group_id,
    buffer = self.buf,
    callback = function()
      if self.job and self.job > 0 then
        pcall(vim.fn.jobstop, self.job)
      end
      self.job = nil
      self.buf = nil
      self._on_next_exit = nil

      if M.layout.active_type == self.term_type then
        M.layout.active_type = nil
        M.hide()
      end
    end,
  })

  vim.api.nvim_create_autocmd('WinLeave', {
    group = group_id,
    buffer = self.buf,
    callback = function()
      vim.schedule(function()
        M.UpdateWinbarTitles()
      end)
    end,
  })

  vim.api.nvim_create_autocmd('WinClosed', {
    group = group_id,
    callback = function(args)
      local closed_win = tonumber(args.match)
      if closed_win == M.layout.container_win then
        M.layout.container_win = nil
        M.layout.active_type = nil
      end
    end,
  })
end

----------------------------------------------------------------------------------------
-- CORE API ORCHESTRATION INTERFACE LAYER
----------------------------------------------------------------------------------------
--- Orchestration factory registering a fresh terminal instance context table shell matrix
---@param name string Explicit namespace token code tracking name (e.g. 'cli', 'mon')
---@param title string Visual interface tab name assigned to the C-API winbar rendering split
---@param filetype_or_cb string|fun(j: integer, d: string[], e: string)|nil Workspace signature filetype override string or direct output stream callback hook
---@param custom_stdout fun(j: integer, d: string[], e: string)|nil Dedicated context callback function tracking async pipeline outputs
---@return Terminal Finalized instance table mapped securely inside the tracking registries
function M.create_terminal(name, title, filetype_or_cb, custom_stdout)
  local final_filetype = nil
  local final_cb = nil

  if type(filetype_or_cb) == 'function' then
    final_cb = filetype_or_cb
    final_filetype = 'terminal_' .. name
  else
    final_filetype = filetype_or_cb or ('terminal_' .. name)
    final_cb = custom_stdout
  end

  if M.terminals[name] then
    M.terminals[name].title = title
    M.terminals[name].filetype = final_filetype
    M.terminals[name]._custom_stdout = final_cb
    if not M.terminals[name].buf or not vim.api.nvim_buf_is_valid(M.terminals[name].buf) then
      M.terminals[name]:on_create()
    end
    return M.terminals[name]
  end

  local current_count = 0
  for _ in pairs(M.terminals) do current_count = current_count + 1 end

  M.terminals[name] = Terminal.new(name, title, final_filetype, final_cb)
  M.terminals[name]._creation_index = current_count + 1

  M[name] = M.terminals[name]

  M.terminals[name]:on_create()
  return M.terminals[name]
end

--- Projects a targeted terminal buffer onto the screen view layout space
---@param term_type string|nil Target key name token representing the pane selection matrix context
---@return nil
function M.show(term_type)
  if not term_type then
    term_type = next(M.terminals)
  end
  local target_instance = M.terminals[term_type]
  if not target_instance then return end

  if not target_instance.buf or not vim.api.nvim_buf_is_valid(target_instance.buf) then
    target_instance:on_create()
  end

  -- FAIL-SAFE: If the container window already exists and is valid, 
  -- ALWAYS just swap the buffer instead of creating a new split. 
  -- This completely eliminates 3-way parallel split loops.
  if M.layout.container_win and vim.api.nvim_win_is_valid(M.layout.container_win) then
    vim.api.nvim_win_set_buf(M.layout.container_win, target_instance.buf)
    M.layout.active_type = term_type
    target_instance:_register_viewport_mappings()
    M.UpdateWinbarTitles()
    return
  end

  -- Only execute a fresh split if no container window exists on screen at all
  target_instance:on_open()
  M.UpdateWinbarTitles()
  -- vim.cmd('startinsert')
end

--- Hides the active panel split view window layout frame cleanly from the viewport screen
---@return nil
function M.hide()
  if M.layout.container_win and vim.api.nvim_win_is_valid(M.layout.container_win) then
    if vim.w[M.layout.container_win].pio_managed then
      pcall(vim.api.nvim_win_close, M.layout.container_win, true)
    end
  end
  M.layout.container_win = nil
  M.layout.active_type = nil
  M.RestoreWorkspaceFocus()
end

--- Public automation macro toggling layout panel split view visibilities dynamically
---@return nil
function M.toggle()
  if M.layout.container_win and vim.api.nvim_win_is_valid(M.layout.container_win) then
    M.hide()
  else
    M.show(M.layout.active_type or 'cli')
  end
end

--- Class context shortcut routing instance show triggers back through the main module engine
---@return nil
function Terminal:show()
  M.show(self.term_type)
end

--- Class instance method routing hide requests safely to the master layout manager
---@return nil
function Terminal:hide()
  M.hide()
end

--- Rotates horizontally across the ordered set array list of available tab targets
---@return nil
function M.SwitchTerminalPane()
  local ordered_keys = {}
  for k, _ in pairs(M.terminals) do
    table.insert(ordered_keys, k)
  end

  table.sort(ordered_keys, function(a, b)
    local term_a = M.terminals[a]
    local term_b = M.terminals[b]
    return (term_a._creation_index or 0) < (term_b._creation_index or 0)
  end)

  if #ordered_keys <= 1 then
    return
  end

  local current_index = 1
  for i, k in ipairs(ordered_keys) do
    if k == M.layout.active_type then
      current_index = i
      break
    end
  end

  local next_index = (current_index % #ordered_keys) + 1
  M.show(ordered_keys[next_index])
end

--- Evaluates whether the layout container split window framework is actively open on screen
---@return boolean Validation property flag output
function M.IsTerminalOpen()
  return M.layout.container_win ~= nil and vim.api.nvim_win_is_valid(M.layout.container_win)
end

--- Dispatches a command sequence task and binds a token callback to collapse visibility frames automatically on completion
---@param cmd string Macro command sequence sent downstream (e.g. 'pio run')
---@return nil
function M.send_and_restore(cmd)
  local target_instance = M.terminals.cli
  if not target_instance then
    return
  end

  local original_work_win = vim.api.nvim_get_current_win()

  target_instance._on_next_exit = function()
    vim.schedule(function()
      M.hide()
      if original_work_win and vim.api.nvim_win_is_valid(original_work_win) then
        pcall(vim.api.nvim_set_current_win, original_work_win)
      else
        M.RestoreWorkspaceFocus()
      end
    end)
  end

  if not target_instance.buf or not vim.api.nvim_buf_is_valid(target_instance.buf) then
    target_instance:on_create()
  end

  target_instance:send(cmd)
end

-- UNIVERSAL INTERACTIVE DIRECTIONAL DOWN NAVIGATOR (Generic Explorer Protection)
vim.keymap.set({ 'n', 'i', 'v' }, '<C-j>', function()
  local current_win = vim.api.nvim_get_current_win()
  local win_type = vim.fn.win_gettype(current_win)
  local current_buf = vim.api.nvim_get_current_buf()
  local buftype = vim.api.nvim_get_option_value('buftype', { buf = current_buf })

  if win_type ~= '' or buftype == 'nofile' or buftype == 'acwrite' or buftype == 'prompt' then
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<C-w>j', true, true, true), 'n', false)
    return
  end

  if M.layout.container_win and vim.api.nvim_win_is_valid(M.layout.container_win) then
    vim.api.nvim_set_current_win(M.layout.container_win)
  else
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<C-w>j', true, true, true), 'n', false)
  end
end, { silent = true })

--- Initializes configurations by executing a deep dictionary merge block over existing options
---@param opts TerminalConfig|nil Table configuration overrides dictionary mapping structure parameters
---@return nil
function M.setup(opts)
  M.config = vim.tbl_deep_extend('force', M.config, opts or {})
end

----------------------------------------------------------------------------------------
-- SYSTEM FACTORY CHANNELS INITIALIZATION
--- Wipes existing channel configurations and triggers pristine subsystem object instantiations
---@return nil
function M.reopen()
  if M.terminals['logs'] then M.terminals['logs']:close() end
  if M.terminals['mon'] then M.terminals['mon']:close() end
  if M.terminals['cli'] then M.terminals['cli']:close() end

  M.create_terminal('cli', ' CLI ', function(j, d, e)
    if type(M.stdout_callback) == 'function' then M.stdout_callback(j, d, e) end
  end)
  M.create_terminal('mon', ' Monitor ', nil)
  M.create_terminal('logs', ' OS ', nil)
end
M.reopen()
----------------------------------------------------------------------------------------

setmetatable(M, {
  __index = function(table, key)
    return rawget(table, 'terminals')[key]
  end,
})

return M
-- stylua: ignore end
