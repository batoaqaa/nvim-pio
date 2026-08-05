-- terminal.lua
local M = {}

-- Configuration with defaults
M.config = {
  panel_height = 0.2, -- Percentage of screen height
  focus_terminal = true, -- Auto-focus terminal on open
  persist_layout = true, -- Remember layout for toggling
  close_on_escape = true, -- Close terminal with ESC
}

-- Layout state
M.layout = {
  container_win = nil,
  active_type = nil,
  prev_win = nil,
  prev_layout = nil, -- Save layout for restoration
}

-- Terminal class
local Terminal = {}
Terminal.__index = Terminal

function Terminal:new(term_type, opts)
  local instance = setmetatable({}, Terminal)
  instance.term_type = term_type or 'terminal'
  instance.buf = nil
  instance.opts = opts or {}
  instance.is_open = false
  return instance
end

function Terminal:create_buffer()
  if self.buf and vim.api.nvim_buf_is_valid(self.buf) then
    return self.buf
  end

  -- Create terminal buffer
  self.buf = vim.api.nvim_create_buf(false, true)

  -- Set buffer options
  vim.api.nvim_set_option_value('buftype', 'terminal', { buf = self.buf })
  vim.api.nvim_set_option_value('bufhidden', 'hide', { buf = self.buf })

  return self.buf
end

function Terminal:is_open()
  return self.is_open and self.buf and vim.api.nvim_buf_is_valid(self.buf)
end

function Terminal:on_open()
  if self:is_open() then
    self:focus()
    return
  end

  -- Create buffer if needed
  self:create_buffer()

  -- Save current state before opening
  M.layout.prev_win = vim.api.nvim_get_current_win()
  M.layout.prev_layout = self:_get_current_layout()

  -- Find appropriate window to split from
  local target_win = self:_find_target_window()
  vim.api.nvim_set_current_win(target_win)

  -- Calculate height
  local target_height = math.ceil(vim.o.lines * (M.config.panel_height or 0.2))
  vim.go.splitkeep = 'screen'

  -- Create the split
  vim.cmd('botright ' .. target_height .. 'split')

  -- Store and setup the terminal window
  M.layout.container_win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(M.layout.container_win, self.buf)
  M.layout.active_type = self.term_type

  -- Configure window options
  self:_setup_window(M.layout.container_win)

  -- Start terminal
  self:_start_terminal()

  -- Register keymaps
  self:_register_mappings()

  -- Focus terminal if configured
  if M.config.focus_terminal then
    vim.api.nvim_set_current_win(M.layout.container_win)
    self:enter_terminal_mode()
  end

  self.is_open = true

  -- Auto-close on Escape in terminal mode
  if M.config.close_on_escape then
    vim.api.nvim_create_autocmd('TermEnter', {
      buffer = self.buf,
      callback = function()
        vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<C-\\><C-n>', true, false, true), 'n', false)
        self:on_close()
      end,
      once = true,
    })
  end
end

function Terminal:on_close()
  if not self:is_open() then
    return
  end

  -- Save terminal window
  local term_win = M.layout.container_win

  -- Close the terminal window
  if term_win and vim.api.nvim_win_is_valid(term_win) then
    vim.api.nvim_win_close(term_win, true)
  end

  -- Hide the buffer
  if self.buf and vim.api.nvim_buf_is_valid(self.buf) then
    vim.api.nvim_set_option_value('bufhidden', 'hide', { buf = self.buf })
  end

  -- Restore previous layout if saved
  if M.config.persist_layout and M.layout.prev_layout then
    self:_restore_layout(M.layout.prev_layout)
  end

  -- Return to previous window
  if M.layout.prev_win and vim.api.nvim_win_is_valid(M.layout.prev_win) then
    vim.api.nvim_set_current_win(M.layout.prev_win)
  end

  -- Clean up
  M.layout.container_win = nil
  M.layout.active_type = nil
  self.is_open = false
end

function Terminal:toggle()
  if self:is_open() then
    self:on_close()
  else
    self:on_open()
  end
end

function Terminal:focus()
  if not self:is_open() then
    self:on_open()
    return
  end

  if M.layout.container_win and vim.api.nvim_win_is_valid(M.layout.container_win) then
    vim.api.nvim_set_current_win(M.layout.container_win)
    self:enter_terminal_mode()
  end
end

function Terminal:enter_terminal_mode()
  if self.buf and vim.api.nvim_buf_is_valid(self.buf) then
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<C-\\><C-n>', true, false, true), 'n', false)
    vim.cmd('startinsert')
  end
end

-- Private methods

function Terminal:_find_target_window()
  local current_win = vim.api.nvim_get_current_win()
  local current_buf = vim.api.nvim_win_get_buf(current_win)

  -- If current window has terminal buffer, find another
  if current_buf == self.buf or vim.api.nvim_get_option_value('buftype', { buf = current_buf }) == 'terminal' then
    local wins = vim.api.nvim_tabpage_list_wins(0)
    for _, win in ipairs(wins) do
      local buf = vim.api.nvim_win_get_buf(win)
      local buftype = vim.api.nvim_get_option_value('buftype', { buf = buf })
      if buftype ~= 'terminal' and vim.fn.win_gettype(win) == '' then
        return win
      end
    end
  end

  -- Try to find a regular window
  local wins = vim.api.nvim_tabpage_list_wins(0)
  for _, win in ipairs(wins) do
    local buf = vim.api.nvim_win_get_buf(win)
    local buftype = vim.api.nvim_get_option_value('buftype', { buf = buf })
    if buftype == '' and vim.fn.win_gettype(win) == '' and buf ~= self.buf then
      return win
    end
  end

  -- Fallback to current window
  return current_win
end

function Terminal:_setup_window(win)
  -- Window options
  vim.w[win].pio_managed = true
  vim.api.nvim_set_option_value('winfixheight', true, { scope = 'local', win = win })
  vim.api.nvim_set_option_value('number', false, { scope = 'local', win = win })
  vim.api.nvim_set_option_value('relativenumber', false, { scope = 'local', win = win })
  vim.api.nvim_set_option_value('signcolumn', 'no', { scope = 'local', win = win })
  vim.api.nvim_set_option_value('list', false, { scope = 'local', win = win })
  vim.api.nvim_set_option_value('spell', false, { scope = 'local', win = win })

  -- Terminal-specific
  vim.api.nvim_set_option_value('number', false, { scope = 'local', win = win })
  vim.api.nvim_set_option_value('relativenumber', false, { scope = 'local', win = win })
end

function Terminal:_start_terminal()
  -- Start with your preferred shell
  local shell = vim.o.shell
  local cmd = self.opts.cmd or shell

  -- If it's a fresh buffer, start the terminal
  if vim.api.nvim_buf_line_count(self.buf) <= 1 then
    vim.fn.termopen(cmd, {
      on_exit = function()
        -- Optional: auto-close on exit
        if self.opts.close_on_exit ~= false then
          vim.schedule(function()
            self:on_close()
          end)
        end
      end,
    })
  end
end

function Terminal:_register_mappings()
  if not M.layout.container_win then
    return
  end

  local opts = { buffer = self.buf }

  -- Escape to normal mode
  vim.keymap.set('t', '<Esc>', '<C-\\><C-n>', opts)

  -- Toggle with double Escape in normal mode
  vim.keymap.set('n', '<Esc><Esc>', function()
    self:toggle()
  end, { buffer = self.buf })

  -- Close with Ctrl+C in normal mode
  vim.keymap.set('n', '<C-c>', function()
    self:on_close()
  end, { buffer = self.buf })

  -- Alt+h/j/k/l to navigate out of terminal
  vim.keymap.set('t', '<A-h>', '<C-\\><C-n><C-w>h', opts)
  vim.keymap.set('t', '<A-j>', '<C-\\><C-n><C-w>j', opts)
  vim.keymap.set('t', '<A-k>', '<C-\\><C-n><C-w>k', opts)
  vim.keymap.set('t', '<A-l>', '<C-\\><C-n><C-w>l', opts)
end

function Terminal:_get_current_layout()
  -- Save current window layout for restoration
  local layout = {}
  local wins = vim.api.nvim_tabpage_list_wins(0)
  for _, win in ipairs(wins) do
    if vim.api.nvim_win_is_valid(win) then
      local width = vim.api.nvim_win_get_width(win)
      local height = vim.api.nvim_win_get_height(win)
      layout[win] = { width = width, height = height }
    end
  end
  return layout
end

function Terminal:_restore_layout(layout)
  -- Restore layout if needed
  -- This is a placeholder for more sophisticated layout restoration
  -- You might want to use winsaveview()/winrestview() or similar
end

-- Global API functions

function M.create_terminal(term_type, opts)
  return Terminal:new(term_type, opts)
end

function M.toggle(term_type, opts)
  if not M._instances then
    M._instances = {}
  end

  if not M._instances[term_type] then
    M._instances[term_type] = M.create_terminal(term_type, opts)
  end

  M._instances[term_type]:toggle()
end

function M.close_all()
  if M._instances then
    for _, instance in pairs(M._instances) do
      instance:on_close()
    end
  end
  M.layout.container_win = nil
end

function M.setup(opts)
  M.config = vim.tbl_deep_extend('force', M.config, opts or {})
end

-- Setup default keymaps
function M.setup_keymaps()
  vim.keymap.set('n', '<C-\\>', function()
    M.toggle('default')
  end, { desc = 'Toggle terminal' })

  vim.keymap.set('n', '<C-|>', function()
    M.toggle('vertical', { cmd = 'bash' })
  end, { desc = 'Toggle vertical terminal' })
end

-- Autocommands for cleanup
vim.api.nvim_create_autocmd('VimLeavePre', {
  callback = function()
    M.close_all()
  end,
})

return M
