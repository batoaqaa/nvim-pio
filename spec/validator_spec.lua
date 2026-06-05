---@diagnostic disable: undefined-global, undefined-field
-- Save this file as: spec/validator_spec.lua

-- Automatically find the current project's /lua directory and append it to Neovim's runtime path
local current_file = debug.getinfo(1, 'S').source:sub(2) -- Gets the absolute path of this test file
local project_root = vim.fs.dirname(vim.fs.dirname(current_file))
vim.opt.rtp:append(vim.fs.joinpath(project_root, 'lua'))

-- 1. Initialize the global environment natively by importing your OS module layout
-- Adjust the path context below to point directly to your system info setup file
require('nvimpio.os')

-- 2. Safely capture the global type casting schema to satisfy the Lls_lua diagnostic engine
local OS = _G.OS ---@cast OS +OS

-- 3. Require the modules under test
local M = require('nvimpio')
require('nvimpio.validator')

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

    -- Mock the dependencies tree merging system for isolation testing
    package.loaded['nvimpio.menu'] = {
      merge_menu_tree = function(_, user_tree, _)
        return user_tree
      end,
    }

    -- Reset active runtime choices state
    M.options = nil
  end)

  it('should successfully pass validation using empty tables or factory defaults', function()
    M.setup({})
    assert.is_table(M.options)
    assert.is_true(M.options.clangd.support)
    assert.is_equal('<leader>\\', M.options.menu_key)
  end)

  it('should merge scalar properties correctly without breaking bindings arrays', function()
    M.setup({
      debug = true,
      clangd = { install = true },
    })

    assert.is_true(M.options.debug)
    assert.is_true(M.options.clangd.install)
    assert.is_true(M.options.clangd.support)
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
                shortcut = 'LONG_SHORTCUT',
                command = 'ValidCommand',
              },
            },
          },
        },
      })
    end)
  end)
end)
