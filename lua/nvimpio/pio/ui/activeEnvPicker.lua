local M = {}

function M.select_env_picker()
  if not _G.metadata or not _G.metadata.envs then
    return
  end
  local current_active = _G.metadata.active_env

  local envs = vim.tbl_keys(_G.metadata.envs)
  table.sort(envs)

  -- Set native floating window borders color to make sure it looks great
  vim.api.nvim_set_hl(0, 'FloatBorder', { fg = '#4ec9b0', bg = 'NONE' })

  vim.ui.select(envs, {
    prompt = 'Select Active Target Environment:',
    kind = 'nvimpio_env_selector',
    format_item = function(name)
      local idx = vim.fn.index(envs, name) + 1
      local line = string.format(' %d. %s %s', idx, (name == current_active) and '[x]' or '[ ]', name)

      -- FORCE WIDTH: Pad the string with spaces so it matches a minimum width (e.g., 45 characters)
      local target_width = 25
      local padding_needed = target_width - #line
      if padding_needed > 0 then
        line = line .. string.rep(' ', padding_needed)
      end

      return line
    end,
  }, function(choice)
    if choice then
      _G.metadata.active_env = choice
      vim.cmd('redrawstatus')
      OS.notify(string.format('PlatformIO target swapped -> %s', choice), 'info')
    end
  end)
end

return M
