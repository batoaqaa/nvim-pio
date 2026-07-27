---@diagnostic disable: undefined-global, undefined-field
-- Save this file as: spec/validator_spec.lua

-- Initialize global environment natively by importing OS module layout
-- require('nvimpio.osInfo')
-- local OS = _G.OS ---@cast OS +OS

-- Require modules under test (Adjust paths if files are in subfolders)
local M = require('nvimpio')
local defConfig = require('nvimpio.defConfig')
local validator = require('nvimpio.validator')
local menu = require('nvimpio.menu')

describe('PlatformIO Configuration & Validation System', function()
  before_each(function()
    -- Reset pristine factory default options before every single test run
    M.defaults = vim.deepcopy(defConfig)

    -- Mock M.setup logic using your real validator and menu merger
    M.options = nil
    M.setup = function(user_opts)
      user_opts = user_opts or {}

      -- 1. Perform structural deep merge on menu trees and scalar options
      local merged_opts = vim.tbl_deep_extend('force', M.defaults, user_opts)
      if user_opts.menu_bindings then
        merged_opts.menu_bindings = menu.merge_menu_tree(M.defaults.menu_bindings, user_opts.menu_bindings, 'menu_bindings')
      end

      -- 2. Run validator against synthesized runtime configuration
      local ok, err = validator.validate_all_options(merged_opts)
      if not ok then
        error(err, 0)
      end

      M.options = merged_opts
      return M.options
    end
  end)

  it('should successfully pass validation using empty tables or factory defaults', function()
    M.setup({})
    assert.is_table(M.options)
    assert.is_true(M.options.clangd.support)
    assert.is_equal('attach+', M.options.clangd.attach)
    assert.is_equal('<leader>\\', M.options.menu_key)
    assert.is_equal('item', M.options.menu_bindings[1].node)
  end)

  it('should merge scalar properties correctly without breaking bindings arrays', function()
    M.setup({
      clangd = { install = true },
    })

    assert.is_true(M.options.clangd.install)
    assert.is_true(M.options.clangd.support)
    assert.is_equal('item', M.options.menu_bindings[1].node)
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
                shortcut = 'LONG_SHORTCUT', -- Triggers is_char (#vim.trim(v) == 1) failure
                command = 'ValidCommand',
              },
            },
          },
        },
      })
    end)
  end)

  -- =========================================================================
  -- INI STRING INTERPOLATION TEST SECTION
  -- =========================================================================
  describe('INI String Interpolation Engine', function()
    it('should correctly resolve nested platformio variables even if core_dir is missing from the ini', function()
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

      -- Mock internal file system reader module temporarily
      local misc = require('nvimpio.utils.misc')
      local original_readFile = misc.readFile
      local original_filereadable = vim.fn.filereadable

      rawset(misc, 'readFile', function(_)
        return true, mock_ini_content
      end)

      rawset(vim.fn, 'filereadable', function(_)
        return 1
      end)

      -- Execute parsing pipeline
      local core_mod = require('nvimpio.pio.metadata')
      local active_env, metadata = core_mod.get_active_env('TEST_CONTEXT: ')

      -- Restore mocks
      rawset(misc, 'readFile', original_readFile)
      rawset(vim.fn, 'filereadable', original_filereadable)

      -- Verify assertions
      assert.is_equal('uno', active_env)
      assert.is_table(metadata)

      local expected_base = require('nvimpio').config.pio_storage_dir or '~/.platformio'
      assert.is_equal(expected_base, metadata.core_dir)
      assert.is_equal(expected_base .. '/packages', metadata.packages_dir)
      assert.is_equal(expected_base .. '/platforms', metadata.platforms_dir)
    end)
  end)
end)
