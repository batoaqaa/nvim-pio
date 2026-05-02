-- Vim nargs options
-- 0: No arguments.
-- 1: Exactly one argument.
-- ?: Zero or one argument.
-- *: Any number of arguments (including none).
-- +: At least one argument.
-- -1: Zero or one argument (like ?, explicitly).

----------------------------------------------------------------
-- lazy-loading technique using a Lua metatable.
-- It essentially "teaches" Neovim how to find a custom module only when you actually try to use it
-- setmetatable(vim, {
--   __index = function(t, k)
--     -- Lazy load the misc module if requested
--     if k == 'misc' then
--       t.misc = require('nvimpio.utils.misc')
--       return t.misc
--     end
--
--     -- Alias vim.pio to the pio module for convenience
--     if k == 'pio' then
--       t.pio = require('nvimpio.utils.pio')
--       return t.pio
--     end
--   end,
-- })

--@class vim
--@field pio platformio.utils.pio
--@field misc platformio.utils.misc

-- setmetatable(vim, {
--   __index = function(t, k)
--     if k == 'misc' then
--       local m = require('nvimpio.utils.misc')
--       rawset(t, k, m) -- Physically add 'misc' to 'vim'
--       return m
--     end
--     if k == 'pio' then
--       local p = require('nvimpio.utils.pio')
--       rawset(t, k, p) -- Physically add 'pio' to 'vim'
--       return p
--     end
--   end,
-- })
vim.misc = require('nvimpio.utils.misc')
vim.pio = require('nvimpio.pio.upkeep')

-- INFO: fix paths in compile_commands.json
vim.api.nvim_create_user_command('PioFixPaths', function()
  vim.pio.compile_commandsFix()
end, {})

-- -- Pioinit2
-- local pio_wiz = require('nvimpio.pioinit2')
--
-- -- Create a keybinding to trigger the wizard
-- vim.keymap.set('n', '<leader>pi', function()
--   pio_wiz.launch()
-- end, { desc = 'Run PIO Project Wizard' })
--
-- -- Alternatively, create a user command
-- vim.api.nvim_create_user_command('PioWizard', function()
--   pio_wiz.launch()
-- end, {})
--
------------------------------------------------------
local piolsserial = require('nvimpio.piolsserial')

-- Pioinit
vim.api.nvim_create_user_command('Pioinit', function()
  require('nvimpio.pioinit').pioinit()
end, { force = true })

-- Piolsp
vim.api.nvim_create_user_command('PioLSP', function()
  vim.schedule(function()
    require('nvimpio.pioCommands').piolsp()
  end)
end, {})

-- Piorun
vim.api.nvim_create_user_command('Piorun', function(opts)
  local args = opts.args
  require('nvimpio.piocommands').piorun({ args })
end, {
  nargs = '?',
  complete = function(_, _, _)
    return { 'upload', 'uploadfs', 'build', 'clean' } -- Autocompletion options
  end,
})

-- Piomon
-- piolsserial.sync_ttylist()
vim.api.nvim_create_user_command('Piomon', function(opts)
  local args = opts.fargs
  require('nvimpio.pioCommands').piomon(args)
end, {
  nargs = '*',

  complete = function(_, cmd_line)
    local parts = vim.split(cmd_line, '%s+')
    local BAUD = { '4800', '9600', '57600', '115200' }
    local ports = {}
    for _, item in ipairs(piolsserial.tty_list) do
      table.insert(ports, item.port)
    end
    if #parts == 2 then
      return BAUD
    end
    if #parts == 3 then
      return ports
    end
    return {}
  end,
})

-- Piolsserial
vim.api.nvim_create_user_command('Piolsserial', function()
  require('nvimpio.piolsserial').print_tty_list()
end, {})

-- Piolib
vim.api.nvim_create_user_command('Piolib', function(opts)
  local args = vim.split(opts.args, ' ')
  require('nvimpio.piolib').piolib(args)
end, {
  nargs = '+',
})

-- Piocmdh    Piocmd horizontal terminal
vim.api.nvim_create_user_command('Piocmdh', function(opts)
  local cmd_table = vim.split(opts.args, ' ')
  require('nvimpio.pioCommands').piocmd(cmd_table, 'horizontal')
end, {
  nargs = '*',
})

-- Piocmdf    Piocmd float terminal
vim.api.nvim_create_user_command('Piocmdf', function(opts)
  local cmd_table = vim.split(opts.args, ' ')
  require('nvimpio.pioCommands').piocmd(cmd_table, 'float')
end, {
  nargs = '*',
})

-- Piodebug
vim.api.nvim_create_user_command('Piodebug', function()
  require('nvimpio.pioCommands').piodebug()
end, {})

------------------------------------------------------

-- require('telescope').load_extension('ui-select')
-- stylua: ignore
-- INFO: List ToggleTerminals
vim.api.nvim_create_user_command('PioTermList', function()
  local telescope = require('telescope')
  telescope.setup({
    extensions = {
      ['ui-select'] = {
        require('telescope.themes').get_dropdown({
          borderchars = {
            prompt = { ' ', ' ', ' ', ' ', ' ', ' ', ' ', ' ' },
            results = { ' ', ' ', ' ', ' ', ' ', ' ', ' ', ' ' },
            preview = { '─', '│', '─', '│', '╭', '╮', '╯', '╰' },
          },
          prompt_position = 'top', -- "top" or "bottom"
          prompt_prefix = '🔍 ', -- Prompt prefix
          selection_caret = '❯ ', -- Selection indicator
          entry_prefix = '  ', -- Entry prefix
          initial_mode = 'insert', -- "insert" or "normal"
          scroll_strategy = 'cycle', -- "cycle" or "limit"
          sorting_strategy = 'ascending', -- "ascending" or "descending"
          color_devicons = true, -- Color file icons
          use_less = true, -- Use less for preview
          -- prompt_prefix = " ",
          -- selection_caret = " ",
          -- color_devicons = true,
        }),
      },
    },
  })
  telescope.load_extension('ui-select')
  local toggleterm_list = {}

  local terms = require('toggleterm.terminal').get_all(true)
  if #terms ~= 0 then
    for i = 1, #terms do
      if terms[i].display_name and terms[i].display_name ~= '' and terms[i].display_name:find('pio', 1) then
        local termtype = vim.misc.strsplit(terms[i].display_name, ':')[1]
        table.insert(toggleterm_list, {
          term = terms[i],
          termtype = termtype, -- Store the terminal type [piomon or piocli]
        })
      end
    end
  end

  if #toggleterm_list == 0 then
    vim.api.nvim_echo({ { 'No PIO terminal windows found.', 'Normal' } }, true, {})
    return
  end

  vim.ui.select(toggleterm_list, {
    prompt = 'Select a PIO terminal window:',
    format_item = function(item)
      return string.format(
        '%d:%s (hidden: %s)',
        item.term.id,
        item.termtype,
        vim.api.nvim_buf_is_loaded(item.term.bufnr) and (vim.fn.bufwinid(item.term.bufnr) == -1)
      )
    end,
    kind = 'PioTerminals',
  }, function(chosen, _)
    if chosen then
      chosen.term.display_name = chosen.termtype .. ':' .. vim.api.nvim_get_current_win()
      local win_type = vim.fn.win_gettype(chosen.term.window)
      local win_open = win_type == '' or win_type == 'popup'
      if chosen.term.window and (win_open and vim.api.nvim_win_get_buf(chosen.term.window) == chosen.term.bufnr) then
        vim.api.nvim_set_current_win(chosen.term.window)
      else chosen.term:open() end
      vim.api.nvim_echo({ { 'Switched to PIO terminal: ' .. chosen.termtype, 'Normal' } }, true, {})
    else vim.api.nvim_echo({ { 'No PIO terminal window selected.', 'Normal' } }, true, {}) end
  end)
end, {})
