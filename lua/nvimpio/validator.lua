local M = {}

-- Safe validation checker helpers
local function is_str(v)
  return type(v) == 'string' and vim.trim(v) ~= ''
end

local function is_char(v)
  return is_str(v) and #vim.trim(v) == 1
end

-- Validates structural item elements recursively
function M.validate_node(node, path)
  -- Enforce basic node structural constraints
  vim.validate({
    [path .. '.node'] = { node.node, is_str },
    [path .. '.desc'] = { node.desc, is_str },
    [path .. '.shortcut'] = { node.shortcut, is_char },
  })

  -- Branch validation based on the explicit node behavior profile
  if node.node == 'item' then
    vim.validate({
      [path .. '.command'] = { node.command, is_str },
    })
  elseif node.node == 'menu' then
    vim.validate({
      [path .. '.items'] = { node.items, 'table' },
    })
    for i, child in ipairs(node.items or {}) do
      M.validate_node(child, string.format('%s.items[%d]', path, i))
    end
  else
    error(string.format("Validation Error: %s.node must be 'item' or 'menu'", path))
  end
end

-- Top-level configuration integrity verification wrapper
function M.validate_all_options(opt)
  if type(opt) ~= 'table' then
    return false, 'Configuration must be a table'
  end

  -- Safe wrapper to safely validate properties even if parent tables are missing
  local status, err = pcall(function()
    -- 1. Structural layer check
    vim.validate({
      pio = { opt.pio, 'table' },
      clangd = { opt.clangd, 'table' },
      debug = { opt.debug, 'boolean' },
      menu_key = { opt.menu_key, is_str },
      menu_name = { opt.menu_name, is_str },
      menu_bindings = { opt.menu_bindings, 'table' },
    })

    -- 2. Nested property checks (Safely guarded using fallback empty tables)
    local pio = opt.pio or {}
    local clangd = opt.clangd or {}

    vim.validate({
      ['pio.pio_runtime_dir'] = { pio.pio_runtime_dir, is_str },
      ['pio.pio_storage_dir'] = { pio.pio_storage_dir, is_str },
      ['clangd.support'] = { clangd.support, 'boolean' },
      ['clangd.install'] = { clangd.install, 'boolean' },
    })

    -- 3. Execute nested menu loops
    for i, binding in ipairs(opt.menu_bindings or {}) do
      M.validate_node(binding, string.format('menu_bindings[%d]', i))
    end
  end)

  return status, err
end

return M
