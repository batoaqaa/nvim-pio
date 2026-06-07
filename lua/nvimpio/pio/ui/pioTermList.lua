local function pioTermList()
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

  -- local prev = {
  --   orig_window = orig_window,
  --   term = nil,
  --   cli = nil,
  --   mon = nil,
  --   float = false,
  -- }
  local prev = require('nvimpio.utils.term').getPreviousWindow(vim.api.nvim_get_current_win())
  if prev.cli then
    table.insert(toggleterm_list, {
      term = prev.cli,
      termtype = 'piocli', -- Store the terminal type [piomon or piocli]
      hide = prev.mon,
    })
  end
  if prev.mon then
    table.insert(toggleterm_list, {
      term = prev.mon,
      termtype = 'piomon', -- Store the terminal type [piomon or piocli]
      hide = prev.cli,
    })
  end
  -- local terms = require('toggleterm.terminal').get_all(true)
  -- if #terms ~= 0 then
  --   for i = 1, #terms do
  --     if terms[i].display_name and terms[i].display_name ~= '' and terms[i].display_name:find('pio', 1) then
  --       local misc = require('nvimpio.utils.misc')
  --       local termtype = misc.strsplit(terms[i].display_name, ':')[1]
  --       table.insert(toggleterm_list, {
  --         term = terms[i],
  --         termtype = termtype, -- Store the terminal type [piomon or piocli]
  --       })
  --     end
  --   end
  -- end

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
      else
        if chosen.hide then
          chosen.hide:close()
        end
        chosen.term:open()
      end
      vim.api.nvim_echo({ { 'Switched to PIO terminal: ' .. chosen.termtype, 'Normal' } }, true, {})
    else
      vim.api.nvim_echo({ { 'No PIO terminal window selected.', 'Normal' } }, true, {})
    end
  end)
end

return {
  pioTermList = pioTermList,
}
