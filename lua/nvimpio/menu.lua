local M = {}

function M.merge_menu_tree(defaults, overrides, path)
  if type(overrides) ~= 'table' then
    return defaults
  end
  local res = vim.deepcopy(defaults)

  local shortcuts = {}
  for _, item in ipairs(res) do
    shortcuts[item.shortcut] = item
  end

  for _, u_node in ipairs(overrides) do
    if type(u_node) == 'table' and u_node.shortcut then
      local d_node = shortcuts[u_node.shortcut]
      if d_node then
        if u_node.desc then
          d_node.desc = u_node.desc
        end
        if u_node.command then
          d_node.command = u_node.command
        end
        if d_node.node == 'menu' and u_node.items then
          d_node.items = M.merge_menu_tree(d_node.items, u_node.items, path .. '.items')
        end
      else
        u_node.node = u_node.node or 'item'
        if u_node.node == 'menu' and u_node.items then
          u_node.items = M.merge_menu_tree({}, u_node.items, path .. '.items')
        end
        table.insert(res, u_node)
      end
    end
  end
  return res
end

return M
