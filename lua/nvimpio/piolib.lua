local M = {}

local curl = require('plenary.curl')
local pickers = require('telescope.pickers')
local finders = require('telescope.finders')
local entry_display = require('telescope.pickers.entry_display')
local make_entry = require('telescope.make_entry')
local conf = require('telescope.config').values
local actions = require('telescope.actions')
local action_state = require('telescope.actions.state')
local misc = require('nvimpio.utils.misc')
local previewers = require('telescope.previewers')

local libentry_maker = function(opts)
  local displayer = entry_display.create({
    separator = '▏',
    items = {
      { width = 50 },
      { width = 50 },
      { remaining = true },
    },
  })

  local make_display = function(entry)
    return displayer({
      entry.value.name,
      entry.value.owner,
      entry.value.description,
    })
  end

  return function(entry)
    return make_entry.set_default_entry_mt({
      value = {
        name = entry.name,
        owner = entry.owner.username,
        description = entry.description,
        data = entry,
      },
      ordinal = entry.name .. ' ' .. entry.owner.username .. ' ' .. entry.description,
      display = make_display,
    }, opts)
  end
end

-- stylua: ignore
local function pick_library(json_data)
  local opts = {}
  pickers.new(opts, {
    prompt_title = 'Libraries',
    layout_config = {
      width = 0.9, -- Overall width of the Telescope window (90% of screen)
      preview_width = 0.60, -- 65% of the window goes to "Board Details", leaving 25% for results
    },
    finder = finders.new_table({
      results = json_data['items'],
      entry_maker = opts.entry_maker or libentry_maker(opts),
    }),
    attach_mappings = function(prompt_bufnr, _)
      actions.select_default:replace(function()
        actions.close(prompt_bufnr)
        local selection = action_state.get_selected_entry()
        local pkg_name = selection['value']['owner'] .. '/' .. selection['value']['name']
        -- local command = 'pio pkg install --library "' .. pkg_name .. '"'
        -- command = command .. ' && pio run -t compiledb'

        local pio = require('nvimpio.pio.upkeep')
        pio.run_sequence({
            cmnds = {'pio pkg install --library "' .. pkg_name .. '"'},
            cb = pio.handlePiolib
          --function () vim.notify('Piolib: Done', vim.log.levels.INFO) end
        })
      end)
      return true
    end,

    previewer = previewers.new_buffer_previewer({
      title = 'Package Info',
      define_preview = function(self, entry, _)
        local json = misc.strsplit(vim.inspect(entry['value']['data']), '\n')
        local bufnr = self.state.bufnr
        vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, json)
        vim.api.nvim_set_option_value('filetype', 'lua', { buf = bufnr }) --fix deprecated function
        vim.defer_fn(function()
          local win = self.state.winid
          vim.api.nvim_set_option_value('wrap', true, { scope = 'local', win = win })
          vim.api.nvim_set_option_value('linebreak', true, { scope = 'local', win = win })
          vim.api.nvim_set_option_value('wrapmargin', 2, { buf = bufnr })
        end, 0)
      end,
    }),
    sorter = conf.generic_sorter(opts),
  }):find()
end

-- local function pick_library(json_data)
--   local opts = {}
--
--   -- 1. Create a displayer for exactly 2 columns
--   local displayer = entry_display.create({
--     separator = " │ ",
--     items = {
--       { width = 25 },       -- Column 1: Owner (fixed width)
--       { remaining = true }, -- Column 2: Library Name
--     },
--   })
--
--   -- 2. Define the display logic for each row
--   local make_display = function(entry)
--     return displayer({
--       { entry.value.owner or "unknown", "TelescopeResultsVariable" },
--       entry.value.name or "unnamed",
--     })
--   end
--
--   pickers.new(opts, {
--     prompt_title = 'Libraries',
--     layout_config = {
--       width = 0.9,          -- Overall width (90%)
--       preview_width = 0.60, -- Wider preview (60%)
--     },
--
--
--     finder = finders.new_table({
--       results = json_data['items'],
--       entry_maker = function(entry)
--         return {
--           value = entry,
--           display = make_display,
--           -- Ordinal is used for searching/filtering
--           ordinal = (entry.owner or '') .. ' ' .. (entry.name or ''),
--         }
--       end,
--     }),
--     attach_mappings = function(prompt_bufnr, _)
--       actions.select_default:replace(function()
--         actions.close(prompt_bufnr)
--         local selection = action_state.get_selected_entry()
--         local pkg_name = selection['value']['owner'] .. '/' .. selection['value']['name']
--
--         local pio = require('nvimpio.utils.pio')
--         pio.run_sequence({
--             cmnds = {'pio pkg install --library "' .. pkg_name .. '"'},
--             cb = function () vim.notify('Piolib: Done', vim.log.levels.INFO) end
--         })
--       end)
--       return true
--     end,
--
--     --
--     previewer = previewers.new_buffer_previewer({
--       title = 'Package Info',
--       define_preview = function(self, entry, _)
--         local json = misc.strsplit(vim.inspect(entry['value']['data'] or entry['value']), '\n')
--         local bufnr = self.state.bufnr
--         local win = self.state.winid
--
--         vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, json)
--         vim.api.nvim_set_option_value('filetype', 'lua', { buf = bufnr })
--
--         -- Apply wrapping to make the wide preview readable
--         vim.api.nvim_set_option_value('wrap', true, { win = win })
--         vim.api.nvim_set_option_value('linebreak', true, { win = win })
--       end,
--     }),
--     sorter = conf.generic_sorter(opts),
--   }):find()
-- end

function M.piolib(lib_arg_list)
  if not misc.pio_install_check() then
    return
  end

  local lib_str = ''

  for _, v in pairs(lib_arg_list) do
    lib_str = lib_str .. v .. '+'
  end

  local url = 'https://api.registry.platformio.org/v3/search'
  local res = curl.get(url, {
    insecure = true,
    timeout = 20000,
    headers = { content_type = 'application/json' },
    query = {
      query = lib_str,
      limit = 30,
      sort = 'popularity',
      -- page = 1,
      -- limit = 1,
    },
  })

  if res['status'] == 200 then
    local json_data = vim.json.decode(res['body'])

    pick_library(json_data)
  else
    vim.notify(
      'API Request to platformio return HTTP code: ' .. res['status'] .. '\nplease run `curl -LI ' .. url .. '` for complete information',
      vim.log.levels.ERROR
    )
  end
end

return M
