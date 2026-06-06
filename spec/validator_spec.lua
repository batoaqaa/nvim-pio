---@diagnostic disable: undefined-global, undefined-field
-- Save this file as: spec/validator_spec.lua

-- Initialize the global environment natively by importing your OS module layout
require('nvimpio.osInfo')
local OS = _G.OS ---@cast OS +OS

-- Require the modules under test
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
                shortcut = 'LONG_SHORTCUT',
                command = 'ValidCommand',
              },
            },
          },
        },
      })
    end)
  end)

  -- =========================================================================
  -- NEW TEST SECTION: VERIFY INI STRING INTERPOLATION ACCURACY
  -- =========================================================================
  describe('INI String Interpolation Engine', function()
    it('should correctly resolve nested platformio variables even if core_dir is missing from the ini', function()
      -- Create a mock function to inject a temporary file string
      local mock_ini_content = [[
[platformio]
default_envs = uno
platforms_dir = ${platformio.core_dir}/platforms
packages_dir = ${platformio.core_dir}/packages

[env:uno]
platform = atmelavr
board = uno
framework = arduino
]]

      -- Mock the internal file system reader module temporarily for isolation testing
      local misc = require('nvimpio.utils.misc')
      local original_readFile = misc.readFile
      misc.readFile = function(_)
        return true, mock_ini_content
      end

      -- Mock the file check to always think the file exists during the test
      local original_filereadable = vim.fn.filereadable
      vim.fn.filereadable = function(_)
        return 1
      end

      -- Run your target parsing function pipeline
      local active_env, metadata = M.get_active_env('TEST_CONTEXT: ')

      -- Restore our filesystem wrappers immediately to keep other tests isolated and healthy
      misc.readFile = original_readFile
      vim.fn.filereadable = original_filereadable

      -- Core Assertions: Verify data structure interpolation matches expectations
      assert.is_equal('uno', active_env)
      assert.is_table(metadata)

      -- Verify your core_dir evaluated fallback logic
      local expected_base = require('nvimpio').config.pio_storage_dir or '~/.platformio'
      assert.is_equal(expected_base, metadata.core_dir)

      -- CRITICAL INTERPOLATION VERIFICATIONS: Ensure slashes didn't fail or return raw values
      assert.is_equal(expected_base .. '/packages', metadata.packages_dir)
      assert.is_equal(expected_base .. '/platforms', metadata.platforms_dir)
    end)
  end)
  -- =========================================================================
end)

-- ---@diagnostic disable: undefined-global, undefined-field
-- -- Save this file as: spec/validator_spec.lua
--
-- require('nvimpio.osInfo')
-- local OS = _G.OS ---@cast OS +OS
--
-- local M = require('nvimpio')
--
-- describe('PlatformIO Configuration & Validation System', function()
--   before_each(function()
--     -- Reset baseline M.defaults to pristine factory state before every single test run
--     M.defaults = {
--       pio = {
--         pio_runtime_dir = vim.fs.joinpath(OS.defaultHome, '.platformio'),
--         pio_storage_dir = vim.fs.joinpath(OS.defaultHome, '.platformio'),
--       },
--       clangd = { support = true, install = false },
--       debug = false,
--       menu_key = '<leader>\\',
--       menu_name = 'PlatformIO',
--       menu_bindings = {
--         { node = 'item', desc = '[B]lock diagnostic', shortcut = 'b', command = 'ClangdFilter' },
--         {
--           node = 'menu',
--           desc = '[A]dvanced',
--           shortcut = 'a',
--           items = {
--             { node = 'item', desc = '[T]est', shortcut = 't', command = 'Piocmdf test' },
--           },
--         },
--       },
--     }
--
--     -- Reset active runtime state
--     M.options = nil
--   end)
--
--   it('should successfully pass validation using empty tables or factory defaults', function()
--     M.setup({})
--     assert.is_table(M.options)
--     assert.is_true(M.options.clangd.support)
--     assert.is_equal('<leader>\\', M.options.menu_key)
--     -- FIX: Index the array first before checking the field properties
--     assert.is_equal('item', M.options.menu_bindings[1].node)
--   end)
--
--   it('should merge scalar properties correctly without breaking bindings arrays', function()
--     M.setup({
--       debug = true,
--       clangd = { install = true },
--     })
--
--     assert.is_true(M.options.debug)
--     assert.is_true(M.options.clangd.install)
--     assert.is_true(M.options.clangd.support)
--     -- FIX: Index the array first before checking the field properties
--     assert.is_equal('item', M.options.menu_bindings[1].node)
--   end)
--
--   it('should raise a breaking error when top-level configurations violate type schemas', function()
--     assert.has_error(function()
--       M.setup({ debug = 'not_a_boolean_value' })
--     end)
--   end)
--
--   it('should deep-scan and crash when nested menus items fail layout constraints', function()
--     assert.has_error(function()
--       M.setup({
--         menu_bindings = {
--           {
--             node = 'menu',
--             desc = 'Invalid Nested Submenu',
--             shortcut = 'z',
--             items = {
--               {
--                 node = 'item',
--                 desc = 'Bad Shortcut Rule',
--                 shortcut = 'LONG_SHORTCUT', -- Intentionally broken constraint (> 1 character)
--                 command = 'ValidCommand',
--               },
--             },
--           },
--         },
--       })
--     end)
--   end)
-- end)
