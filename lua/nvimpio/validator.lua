local M = {}

local function is_str(v)
  return type(v) == 'string' and vim.trim(v) ~= ''
end

function M.validate_node(node, path)
  vim.validate({
    [path .. '.node'] = { node.node, is_str, "either 'item' or 'menu'" },
    [path .. '.desc'] = { node.desc, is_str, 'a description string' },
    [path .. '.shortcut'] = {
      node.shortcut,
      function(s)
        return is_str(s) and #vim.trim(s) == 1
      end,
      'a 1-character shortcut',
    },
  })

  if node.node == 'item' then
    vim.validate({ [path .. '.command'] = { node.command, is_str, 'a command execution string' } })
  elseif node.node == 'menu' then
    vim.validate({ [path .. '.items'] = { node.items, 'table' } })
    for i, child in ipairs(node.items) do
      M.validate_node(child, string.format('%s.items[%d]', path, i))
    end
  end
end

function M.validate_all_options(opt)
  return pcall(vim.validate, {
    pio = { opt.pio, 'table' },
    clangd = { opt.clangd, 'table' },
    debug = { opt.debug, 'boolean' },
    menu_key = { opt.menu_key, is_str, 'a non-empty trigger shortcut' },
    menu_name = { opt.menu_name, is_str, 'a menu interface title label' },
    ['pio.pio_runtime_dir'] = { opt.pio.pio_runtime_dir, is_str, 'a runtime directory path string' },
    ['pio.pio_storage_dir'] = { opt.pio.pio_storage_dir, is_str, 'a storage directory path string' },
    ['clangd.support'] = { opt.clangd.support, 'boolean' },
    ['clangd.install'] = { opt.clangd.install, 'boolean' },
  })
end

return M
