local M = {}

-- Private Helper: Recursively validates deeply nested menu bindings
local function validate_menu_node(node, path_string)
  -- 1. Custom validation check for non-empty string properties
  local is_non_empty_string = function(v)
    return type(v) == 'string' and vim.trim(v) ~= ''
  end

  -- 2. Validate properties common to BOTH item nodes and menu nodes
  vim.validate({
    [path_string .. '.node'] = { node.node, is_non_empty_string, '\'either "item" or "menu"\'' },
    [path_string .. '.desc'] = { node.desc, is_non_empty_string, "'a non-empty string description'" },
    [path_string .. '.shortcut'] = { node.shortcut, is_non_empty_string, "'a single-character string shortcut'" },
  })

  -- Enforce shortcut maximum string length constraint
  if #vim.trim(node.shortcut) ~= 1 then
    error(string.format("%s.shortcut: expected a single character, got '%s'", path_string, node.shortcut), 0)
  end

  -- 3. BRANCH VALIDATION: Isolate behavior based on node type
  if node.node == 'item' then
    -- Execution items MUST have an absolute command bound to them
    vim.validate({
      [path_string .. '.command'] = { node.command, is_non_empty_string, "'a non-empty executable string command'" },
    })

    -- Safety: Catch mistakes if a user accidentally types 'items = {}' on an 'item' node
    if node.items ~= nil then
      error(string.format("%s: 'item' nodes cannot contain child 'items' tables. Change node type to 'menu'", path_string), 0)
    end
  elseif node.node == 'menu' then
    -- Nested menus MUST contain a sub-table array of child nodes
    vim.validate({
      [path_string .. '.items'] = { node.items, 'table' },
    })

    if #node.items == 0 then
      error(string.format('%s.items: child item tracking table array cannot be empty.', path_string), 0)
    end

    -- RECURSIVE TRIGGER: Step down into child items array to trace inner configurations
    for index, child_node in ipairs(node.items) do
      local sub_path = string.format('%s.items[%d]', path_string, index)

      if type(child_node) ~= 'table' then
        error(string.format('%s: expected sub-table map config tree element, got %s', sub_path, type(child_node)), 0)
      end

      validate_menu_node(child_node, sub_path)
    end
  else
    -- Catch typos like node = 'itme' or node = 'menuu'
    error(string.format("%s.node: expected 'item' or 'menu', got '%s'", path_string, tostring(node.node)), 0)
  end
end

-- Top-Level Tree Orchestrator
function M.validate_config_tree(options)
  local is_non_empty_string = function(v)
    return type(v) == 'string' and vim.trim(v) ~= ''
  end

  local status, err = pcall(function()
    -- Validate top-level primitive values first
    vim.validate({
      pio = { options.pio, 'table' },
      clangd = { options.clangd, 'table' },
      menu_key = { options.menu_key, is_non_empty_string, "'a non-empty string shortcut'" },
      menu_name = { options.menu_name, is_non_empty_string, "'a non-empty string label'" },
      debug = { options.debug, 'boolean' },
      menu_bindings = { options.menu_bindings, 'table' }, -- Our new target key
    })

    -- Trace through user's dynamic menu layout items recursively
    for index, root_node in ipairs(options.menu_bindings) do
      local current_path = string.format('menu_bindings[%d]', index)

      if type(root_node) ~= 'table' then
        error(string.format('%s: expected table configuration layout element, got %s', current_path, type(root_node)), 0)
      end

      validate_menu_node(root_node, current_path)
    end
  end)

  if not status then
    vim.schedule(function()
      vim.notify('PlatformIO Wizard Configuration Layout Error:\n' .. err, vim.log.levels.ERROR)
    end)
    return false
  end

  return true
end

return M
