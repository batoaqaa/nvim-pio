---@diagnostic disable: undefined-global, undefined-field
-- Save this file as: spec/validator_spec.lua

require('nvimpio.os')
local OS = _G.OS ---@cast OS +OS

local M = require('nvimpio')

describe('PlatformIO Configuration & Validation System', function()
  before_each(function()
    -- Reset baseline M.defaults to pristine factory state before every single test run
    M.defaults = {
      pio = {
        pio_runtime_dir = vim.fs.joinpath(OS.defaultHome, '.platformio'),
        pio_storage_dir = vim.fs.joinpath(OS.defaultHome, '.platformio'),
      },
      clangd = { support = true, install = false },
      debug = false,
      menu_key = '<leader>\\',
      menu_name = 'PlatformIO',
      menu_bindings = {
        { node = 'item', desc = '[B]lock diagnostic', shortcut = 'b', command = 'ClangdFilter' },
        {
          node = 'menu',
          desc = '[A]dvanced',
          shortcut = 'a',
          items = {
            { node = 'item', desc = '[T]est', shortcut = 't', command = 'Piocmdf test' },
          },
        },
      },
    }

    -- Reset active runtime state
    M.options = nil
  end)

  it('should successfully pass validation using empty tables or factory defaults', function()
    M.setup({})
    assert.is_table(M.options)
    assert.is_true(M.options.clangd.support)
    assert.is_equal('<leader>\\', M.options.menu_key)
    -- FIX: Index the array first before checking the field properties
    assert.is_equal('item', M.options.menu_bindings[1].node)
  end)

  it('should merge scalar properties correctly without breaking bindings arrays', function()
    M.setup({
      debug = true,
      clangd = { install = true },
    })

    assert.is_true(M.options.debug)
    assert.is_true(M.options.clangd.install)
    assert.is_true(M.options.clangd.support)
    -- FIX: Index the array first before checking the field properties
    assert.is_equal('item', M.options.menu_bindings[1].node)
  end)

  it('should raise a breaking error when top-level configurations violate type schemas', function()
    assert.has_error(function()
      M.setup({ debug = 'not_a_boolean_value' })
    end)
  end)

  it('should deep-scan and crash when nested menus items fail layout constraints', function()
    assert.has_error(function()
      M.setup({
        menu_bindings = {
          {
            node = 'menu',
            desc = 'Invalid Nested Submenu',
            shortcut = 'z',
            items = {
              {
                node = 'item',
                desc = 'Bad Shortcut Rule',
                shortcut = 'LONG_SHORTCUT', -- Intentionally broken constraint (> 1 character)
                command = 'ValidCommand',
              },
            },
          },
        },
      })
    end)
  end)
end)
