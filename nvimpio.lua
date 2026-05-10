local isWindows = vim.fn.has('win32') == 1 --jit.os == 'Windows'
local isMac = vim.fn.has('mac') == 1

----------------------------------------------------------------------------------------
-- INFO: Set options
-- disable netrw at the very start of your init.lua
vim.g.loaded_netrw = 1
vim.g.loaded_netrwPlugin = 1

-- optionally enable 24-bit colour
vim.opt.termguicolors = true

vim.opt['number'] = true
vim.opt.autowrite = true -- Enable auto write

-- only set clipboard if not in ssh, to make sure the OSC 52
-- integration works automatically. Requires Neovim >= 0.10.0
vim.opt.clipboard = vim.env.SSH_TTY and '' or 'unnamedplus' -- Sync with system clipboard

vim.opt.tabstop = 2 -- Number of spaces tabs count for
vim.opt.softtabstop = 2
vim.opt.shiftround = true -- Round indent
vim.opt.shiftwidth = 2 -- Size of an indent
vim.opt.smartindent = true -- Insert indents automatically
vim.opt.expandtab = true -- Use spaces instead of tabs

vim.opt.smoothscroll = true
vim.opt.foldmethod = 'expr'
vim.opt.foldtext = ''
vim.opt.fillchars = ''
vim.opt.foldcolumn = '0'
vim.opt.foldenable = true
vim.opt.foldexpr = 'v:lua.vim.treesitter.foldexpr()'
vim.opt.foldlevel = 99
vim.opt.foldlevelstart = 99
vim.opt.foldnestmax = 3

vim.g.have_nerd_font = true
vim.g.mapleader = ' '
vim.g.maplocalleader = ' '

if isWindows then
  local pwsh = vim.fn.executable('pwsh') == 1 and 'pwsh' or 'powershell'
  vim.opt.shell = pwsh
  vim.opt.shellcmdflag =
    '-NoLogo -NoProfile -ExecutionPolicy RemoteSigned -Command [Console]::InputEncoding=[Console]::OutputEncoding=[System.Text.UTF8Encoding]::new();'
  vim.opt.shellredir = '2>&1 | Out-File -Encoding UTF8 %s; exit $LastExitCode'
  vim.opt.shellpipe = '2>&1 | Out-File -Encoding UTF8 %s; exit $LastExitCode'
  vim.opt.shellquote = ''
  vim.opt.shellxquote = ''

--elseif vim.fn.has("mac") == 1 then
else
  vim.g.shell = '/bin/bash' -- or '/bin/zsh', '/usr/bin/fish', etc.
  vim.g.shellcmdflag = '-c' -- Executes the command passed as a string
  vim.g.shellpipe = '|' -- Pipes output of external commands
  vim.g.shellredir = '> ' -- Redirects output of external commands
end

vim.hl = vim.highlight
vim.api.nvim_set_hl(0, 'PioStatus', {
  fg = '#e0af68', -- Dark text
  bg = '#11111b',
  bold = true,
})
----------------------------------------------------------------------------------------
-- INFO: Set diagnostic config
vim.diagnostic.config({
  virtual_lines = true,
  update_in_insert = true,
  underline = true,
  severity_sort = true,
  float = {
    focusable = true,
    style = 'minimal',
    border = 'rounded',
    source = true,
    header = '',
    prefix = '',
  },
  signs = {
    text = {
      [vim.diagnostic.severity.ERROR] = ' ',
      [vim.diagnostic.severity.WARN] = ' ',
      [vim.diagnostic.severity.HINT] = ' ',
      [vim.diagnostic.severity.INFO] = ' ',
    },
  },
})

----------------------------------------------------------------------------------------
-- INFO: Set nvim keymaps
local keymap = function(mode, lhs, rhs, opts)
  local options = { silent = true } --noremap = true by default in vim.keymap.set
  if opts then
    options = vim.tbl_extend('force', options, opts or {})
  end
  vim.keymap.set(mode, lhs, rhs, options)
end

--To toggle line wrapping in Neovim
keymap('n', '<leader>w', ':set wrap!<CR>', { desc = 'Toggle wrap' })

keymap('n', 'gll', function()
  vim.cmd.edit(vim.lsp.log.get_filename())
end, { desc = 'open LSP [l]og' })
-- Keybinds to make split navigation easier.
--  Use CTRL+<hjkl> to switch between windows
--  See `:help wincmd` for a list of all window commands
keymap('n', '<C-h>', '<C-w><C-h>', { desc = 'Move focus to the left window' })
keymap('n', '<C-l>', '<C-w><C-l>', { desc = 'Move focus to the right window' })
keymap('n', '<C-j>', '<C-w><C-j>', { desc = 'Move focus to the lower window' })
keymap('n', '<C-k>', '<C-w><C-k>', { desc = 'Move focus to the upper window' })

-- Resize with arrows
keymap('n', '<C-Up>', ':resize -2<CR>')
keymap('n', '<C-Down>', ':resize +2<CR>')
keymap('n', '<C-Left>', ':vertical resize -2<CR>')
keymap('n', '<C-Right>', ':vertical resize +2<CR>')

keymap('n', '<leader>bb', ':bprevious<CR>', { desc = '[B]efore Buffer' })
keymap('n', '<leader>ba', ':bnext<CR>', { desc = '[A]fter Buffer' })
keymap('n', '<leader>bs', ':ball<CR>', { desc = '[S]how AllOpened Buffers' })

-- keymap('n', '<leader>bd', '<Cmd>bdelete<CR>', { desc = '[D]elete Buffer' })
keymap('n', '<leader>bd', function()
  local bufnr = vim.api.nvim_get_current_buf()
  local bufs = vim.fn.getbufinfo({ buflisted = 1 })

  if #bufs <= 1 then
    -- Create a new empty buffer
    vim.cmd('enew')
  else
    -- Switch to the previous buffer
    vim.cmd('bp')
  end

  -- Delete the buffer we started with (using pcall to ignore "No buffers deleted" errors)
  pcall(vim.api.nvim_buf_delete, bufnr, { force = false })
end, { desc = '[D]elete Buffer' })

keymap('n', '<leader>e', '<cmd>Neotree document_symbols<CR>', { desc = 'NeoTreeToggle' })
keymap('n', '\\', '<cmd>Neotree toggle<CR>', { desc = 'NeoTreeToggle' })
-- keymap('n', '<leader>e', '<cmd>NvimTreeToggle<CR>', { desc = 'NvimTreeToggle' })
-- keymap('n', '\\', '<cmd>NvimTreeToggle<CR>', { desc = 'NvimTreeToggle' })

-- Keybinds to make split navigation easier.
--  Use CTRL+<hjkl> to switch between windows
keymap('n', '<C-h>', '<C-w><C-h>', { desc = 'Move focus to the left window' })
keymap('n', '<C-l>', '<C-w><C-l>', { desc = 'Move focus to the right window' })
keymap('n', '<C-j>', '<C-w><C-j>', { desc = 'Move focus to the lower window' })
keymap('n', '<C-k>', '<C-w><C-k>', { desc = 'Move focus to the upper window' })

----------------------------------------------------------------------------------------
----------------------------------------------------------------------------------------
-- INFO: Set mini lazy config
----------------------------------------------------------------------------------------
-- stylua: ignore
---[[
local function setup_xdg_paths()
  -- local isWindows = vim.fn.has('win32') == 1
  -- local isMac = vim.fn.has('mac') == 1
  local home = vim.env.HOME or vim.env.USERPROFILE or ''
  local app_name = 'nvim-pio' -- pick a temp root

  -- 1. XDG_CONFIG_HOME (Settings/Configs)
  if not vim.env.XDG_CONFIG_HOME then
    local path = isWindows and (vim.env.LOCALAPPDATA or (home .. '/AppData/Local'))
              or isMac and (home .. '/Library/Preferences')
              or (home .. '/.config')
    vim.env.XDG_CONFIG_HOME = vim.fs.joinpath(path, app_name)
  end

  -- 2. XDG_DATA_HOME (Large data/Databases)
  if not vim.env.XDG_DATA_HOME then
    local path = isWindows and (vim.env.LOCALAPPDATA or (home .. '/AppData/Local'))
              or isMac and (home .. '/Library/Application Support')
              or (home .. '/.local/share')
    vim.env.XDG_DATA_HOME = vim.fs.joinpath(path, app_name)
  end

  -- 3. XDG_STATE_HOME (Logs/History/Persistent State)
  if not vim.env.XDG_STATE_HOME then
    local path = isWindows and (vim.env.LOCALAPPDATA or (home .. '/AppData/Local'))
              or isMac and (home .. '/Library/Application Support')
              or (home .. '/.local/state')
    vim.env.XDG_STATE_HOME = vim.fs.joinpath(path, app_name)
  end

  -- 4. XDG_CACHE_HOME (Temporary/Disposable data)
  if not vim.env.XDG_CACHE_HOME then
    local path = isWindows and (vim.env.TEMP or (home .. '/AppData/Local/Temp'))
              or isMac and (home .. '/Library/Caches')
              or (home .. '/.cache')
    vim.env.XDG_CACHE_HOME = vim.fs.joinpath(path, app_name)
  end
end

setup_xdg_paths()
---]]
--[[
local app_name = 'nvim-pio' -- pick a temp root
local home = isWindows and vim.env.LOCALAPPDATA:gsub('\\', '/') or vim.env.HOME
-- local home = vim.env.HOME or vim.env.USERPROFILE or ""
home = home .. '/' .. app_name
-- local home = vim.loop.os_tmpdir():gsub('\\', '/') .. '/' .. app_name

-- vim.env.NVIM_APPNAME = app_name --isolated nvim
vim.env.XDG_CONFIG_HOME = home .. (isWindows and '/config/' or '/.config')
vim.env.XDG_DATA_HOME = home .. (isWindows and '/data/' or '/.local/share/')
vim.env.XDG_STATE_HOME = home .. (isWindows and '/state/' or '/.local/state/')
vim.env.XDG_CACHE_HOME = home .. (isWindows and '/cache/' or '/.cache/')
--]]

-- BOOTSTRAP (Use stdpath so it ALWAYS matches Neovim's internal logic)
local lazypath = vim.fn.stdpath('data') .. '/lazy/lazy.nvim'

if not (vim.uv or vim.loop).fs_stat(lazypath) then
  print('Installing lazy.nvim to: ' .. lazypath)
  vim.fn.system({
    'git',
    'clone',
    '--filter=blob:none',
    'https://github.com/folke/lazy.nvim.git',
    '--branch=stable',
    lazypath,
  })
end

-- ADD TO RUNTIME PATH (Crucial: makes 'require("lazy")' work)
vim.opt.rtp:prepend(lazypath)

----------------------------------------------------------------------------------------
-- INFO: define plugins table
local plugins = {

  {
    'rebelot/kanagawa.nvim',
    config = function()
      -- require('kanagawa').load('wave')
      require('kanagawa').load('dragon')
      -- require('kanagawa').load('lotus')
    end,
  },

  { 'windwp/nvim-autopairs', event = 'InsertEnter', config = true },

  {
    'Saghen/blink.cmp',
    dependencies = { 'rafamadriz/friendly-snippets' },
    version = '1.*', -- Download pre-built binaries
    opts = {
      keymap = { preset = 'default' }, -- 'default', 'super-tab', or 'enter'
      sources = {
        default = { 'lsp', 'path', 'snippets', 'buffer' },
      },
    },
  },

  -- Recommended: Minimal statusline/tabline
  {
    'nvim-lualine/lualine.nvim',
    dependencies = {
      'nvim-tree/nvim-web-devicons',
      config = function()
        require('lualine').setup({
          options = {
            globalstatus = true, -- Single statusline for all windows
            extensios = { 'neo-treee' },
          },
          -- This replaces the visual part of bufferline
          tabline = {
            lualine_a = {
              {
                'buffers',
                show_filename_only = true,
                hide_filename_extension = false,
                show_modified_status = true,
                mode = 0, -- 0: Shows buffer name
                max_length = vim.o.columns,
                filetype_names = {
                  NvimTree = 'Explorer',
                  TelescopePrompt = 'Telescope',
                },
              },
            },
          },
        })
      end,
    },
  },

  {
    'nvim-neo-tree/neo-tree.nvim',
    branch = 'v3.x',
    dependencies = {
      'nvim-lua/plenary.nvim',
      'nvim-tree/nvim-web-devicons',
      'MunifTanjim/nui.nvim',
    },
    opts = {
      filesystem = {
        -- use_libuv_file_watcher = true,
        filtered_items = {
          hide_dotfiles = false,
          hide_gitignored = true,
          hide_by_name = {
            '.pio',
            '.cache',
          },
          never_show = { -- Add any massive folders here
            -- '.cache',
            -- '.git',
            'node_modules',
            -- 'build',
            -- 'target',
          },
        },
      },
    },
  },

  {
    'batoaqaa/nvim-pio',
    -- cmd = { 'Pioinit' },
    lazy = true,
    init = function(self)
      -- if require('lazy.core.config').plugins[self.name]._.loaded then
      --   return
      -- end
      if vim.fn.filereadable('platformio.ini') == 1 then
        require('lazy').load({ plugins = { self.name } })
      else
        vim.api.nvim_create_user_command('Pioinit', function()
          require('lazy').load({ plugins = { self.name } })
          -- require('nvimpio.pioInit').pioInit()
        end, { nargs = '*' })
      end
    end,

    dependencies = {
      { 'akinsho/toggleterm.nvim' },
      { 'nvim-telescope/telescope.nvim' },
      -- {
      --   'nvim-telescope/telescope.nvim',
      --   tag = '0.1.8',
      --   dependencies = { 'nvim-lua/plenary.nvim' },
      -- },
      { 'nvim-telescope/telescope-ui-select.nvim' },
      { 'nvim-lua/plenary.nvim' },
      { 'folke/which-key.nvim' },
      {
        'mason-org/mason-lspconfig.nvim',
        dependencies = {
          { 'mason-org/mason.nvim' },
          { 'folke/trouble.nvim' },
          { 'j-hui/fidget.nvim' }, -- status bottom right
        },
      },
    },
  },
}
----------------------------------------------------------------------------------------

----------------------------------------------------------------------------------------
-- INFO: Install/config plugins
require('lazy').setup(plugins, {
  root = vim.fn.stdpath('data') .. '/lazy',
  install = { missing = true },
  ui = { border = 'rounded' },
})

----------------------------------------------------------------------------------------
-- stylua: ignore
if vim.fn.has('nvim-0.11') == 1 then
  local json_format_group = vim.api.nvim_create_augroup('JsonFormat', { clear = true })
  vim.api.nvim_create_autocmd('BufWritePre', {
    group = json_format_group,
    pattern = '*.json',
    -- This runs 'python -m json.tool' on the current buffer content
    -- It updates the buffer in-place before the file is written to disk
    callback = function() vim.cmd('%!python -m json.tool') end,
  })
elseif vim.fn.has('nvim-0.12') == 1 then
end

----------------------------------------------------------------------------------------
-- INFO: autocommand to Update lazy.nvim plugins in the background
vim.api.nvim_create_autocmd('User', {
  pattern = 'LazyVimStarted', -- Triggers after the UI enters and startup time is calculated
  desc = 'Update lazy.nvim plugins in the background',
  callback = function()
    require('lazy').sync({
      wait = false, -- Makes the operation asynchronous
      show = false, -- Prevents the Lazy UI from automatically opening
    })
    -- You can add a notification here if you like
    -- vim.misc.notify("Lazy plugins sync started in background", "info")
  end,
})

-- AUTO-CLEANUP ON EXIT
-- SELECTIVE CLEANUP ON EXIT (Keeps plugins, deletes temp files)
-- stylua: ignore
-- SELECTIVE CLEANUP FOR WINDOWS
vim.api.nvim_create_autocmd("VimLeavePre", { -- Use VimLeavePre to act before the write attempt
  callback = function()
    -- 1. Tell Neovim NOT to write the history file on exit to avoid E138
    vim.opt.shadafile = "NONE"

    -- 2. Define target paths
    local state_path = vim.fn.stdpath("state")
    local cache_path = vim.fn.stdpath("cache")

    local targets = {
      state_path .. "/shada",
      cache_path,
    }

    -- 3. Delete the directories cross-platform
    for _, path in ipairs(targets) do
      -- Native Neovim function (0.9+) that handles Windows/macOS/Linux paths automatically
      if vim.fn.isdirectory(path) == 1 then vim.fs.rm(path, { recursive = true, force = true }) end
    end
  end,
})
----------------------------------------------------------------------------------------
-- INFO: configure nvim-pio and load
-----------------------------------------------------------------------------------------
local tok, telescope = pcall(require, 'telescope')
if tok then
  -- 1. Import the actions module (This is the missing part!)
  local actions = require('telescope.actions')
  -- local telescope = require('telescope')
  -- print("here" .. vim.inspect(pioConfig))
  telescope.setup({
    extensions = {
      ['ui-select'] = {
        require('telescope.themes').get_dropdown({
          -- Customizing the dialog appearance
          width = 0.6,
          previewer = false,
        }),
      },
    },
    defaults = {
      mappings = {
        i = {
          ['<C-d>'] = actions.delete_buffer, -- Delete buffer in insert mode
        },
        n = {
          ['dd'] = actions.delete_buffer, -- Delete buffer in normal mode
        },
      },
    },
    pickers = {
      buffers = {
        show_all_buffers = true,
        sort_lastused = true,
        theme = 'dropdown', -- Compact look
        previewer = false, -- Disable preview for a faster feel
      },
    },
  })

  -- Enable Telescope extensions if they are installed
  pcall(require('telescope').load_extension, 'fzf')
  pcall(require('telescope').load_extension, 'ui-select')

  local function run_project_wizard()
    local project_config = {}

    -- Step 1: Select IDE
    vim.ui.select({ 'Neovim', 'VS Code', 'IntelliJ' }, { prompt = 'Select IDE' }, function(ide)
      if not ide then
        return
      end
      project_config.ide = ide

      -- Step 2: Select Board
      vim.ui.select({ 'ESP32', 'Arduino Uno', 'Raspberry Pi' }, { prompt = 'Select Board' }, function(board)
        if not board then
          return
        end
        project_config.board = board

        -- Step 3: Select Framework
        vim.ui.select({ 'ESP-IDF', 'Arduino Core', 'MicroPython' }, { prompt = 'Select Framework' }, function(fw)
          if not fw then
            return
          end
          project_config.framework = fw

          -- Step 4: Final Selection
          vim.ui.select({ 'true', 'false' }, { prompt = 'Include Sample Code?' }, function(sample)
            project_config.sample = sample == 'true'

            -- Final Output/Action
            print(
              string.format('Setup: %s on %s using %s (Sample: %s)', project_config.ide, project_config.board, project_config.framework, project_config.sample)
            )
          end)
        end)
      end)
    end)
  end

  vim.keymap.set('n', '<leader>pw', run_project_wizard, { desc = 'Run Project Wizard' })

  -- See `:help telescope.builtin`
  local builtin = require('telescope.builtin')
  vim.keymap.set('n', '<leader>sh', builtin.help_tags, { desc = 'Search [H]elp' })
  vim.keymap.set('n', '<leader>sk', builtin.keymaps, { desc = 'Search [K]eymaps' })
  vim.keymap.set('n', '<leader>sf', builtin.find_files, { desc = 'Search [F]iles' })
  vim.keymap.set('n', '<leader>ss', builtin.builtin, { desc = 'Search [S]elect Telescope' })
  vim.keymap.set('n', '<leader>sw', builtin.grep_string, { desc = 'Search current [W]ord' })
  vim.keymap.set('n', '<leader>sg', builtin.live_grep, { desc = 'Search by [G]rep' })
  vim.keymap.set('n', '<leader>sd', builtin.diagnostics, { desc = 'Search [D]iagnostics' })
  vim.keymap.set('n', '<leader>sr', builtin.resume, { desc = 'Search [R]esume' })
  vim.keymap.set('n', '<leader>s.', builtin.oldfiles, { desc = 'Search Recent Files ("." for repeat)' })
  vim.keymap.set('n', '<leader><leader>', builtin.buffers, { desc = '[ ] Find existing buffers' })

  -- Slightly advanced example of overriding default behavior and theme
  vim.keymap.set('n', '<leader>/', function()
    -- You can pass additional configuration to Telescope to change the theme, layout, etc.
    builtin.current_buffer_fuzzy_find(require('telescope.themes').get_dropdown({
      winblend = 10,
      previewer = false,
    }))
  end, { desc = '[/] Fuzzily search in current buffer' })
  -- Keymap to open the buffer list
  vim.keymap.set('n', '<leader>fb', '<cmd>Telescope buffers<cr>', { desc = 'Find Buffers' })
end

-- local pioConfig = {
--   pio = {
--     auto_update_path = true,
--     notify_on_missing = true,
--   },
--   lspClangd = {
--     -- enabled = false,
--     enabled = true,
--     attach = {
--       enabled = true,
--       keymaps = true,
--     },
--   },
--   -- menu_key = "<leader>\\", -- replace this menu key  to your convenience
--   -- menu_name = "PlatformIO", -- replace this menu name to your convenience
--   -- debug = false,
-- }
local pioConfig = {
  pio = {
    auto_update_path = true,
    notify_on_missing = true,
  },
  clangd = {
    support = true,
    install = true,
  },
  -- menu_key = "<leader>\\", -- replace this menu key  to your convenience
  -- menu_name = "PlatformIO", -- replace this menu name to your convenience
  -- debug = false,
}
local pok, nvimpio = pcall(require, 'nvimpio')
if pok then
  -- print("here" .. vim.inspect(pioConfig))
  nvimpio.setup(pioConfig)
end
