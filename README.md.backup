<h1 align="center">
    <img src="https://github.com/user-attachments/assets/fa3f7663-802e-4845-b4f7-0992e34899f2" style="height: 1em; vertical-align: bottom;">
    nvim-pio
</h1>

<p align="center"> PlatformIO wrapper for Neovim written in Lua.</p>

<br>

Try the plugin with this minimal standalone config without modifying your existing nvim setup. **This is especially useful if you're encountering errors during installation or usage**.

```sh
wget https://raw.githubusercontent.com/batoaqaa/nvim-pio/refs/heads/main/mini_nvimpio.lua
nvim -u mini_nvimpio.lua

# Now run :Pioinit
```

## Features

- 🚀 **PlatformIO Install**: Run `:PioInstall` to set up PIO in the background.
-  **Project initialize**: Run `:Pioinit` to set up PIO in the background.
- 🛠️ **PIO Autoupdate Path**: Automatically adds PIO binaries to your Neovim `$PATH`.
- 🩺 **Health Check**: Run `:checkhealth pio` to verify your setup.
- 🔔 **Smart Alerts**: Notifies you if PIO is missing

## Installation

#### Plugin

Install the plugin using lazy

```lua
return {
    'batoaqaa/nvim-pio',
    -- cmd = { 'Pioinit', 'Piorun', 'Piocmdh', 'Piocmdf', 'Piolib', 'Piomon', 'Piodebug', 'Piodb' },

    lazy = true,
    init = function(self)
      if require('lazy.core.config').plugins[self.name]._.loaded then
        return
      end
      if vim.fn.filereadable('platformio.ini') == 1 then
        require('lazy').load({ plugins = { self.name } })
      else
        vim.api.nvim_create_user_command('Pioinit', function()
          require('lazy').load({ plugins = { self.name } })
          require('nvimpio.pioInit').pioInit()
        end, { nargs = '*' })
      end
    end,
    dependencies = {
        { 'akinsho/toggleterm.nvim' },
        { 'nvim-telescope/telescope.nvim' },
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
}

```

#### Usage `:h PlatformIO`

### Configuration

```lua
    vim.g.pioConfig ={
      pio = {
        auto_update_path = true,
        notify_on_missing = true,
      },
      clangd = {
        support = true,
        install = true,
      },
      menu_key = '<leader>\\', -- replace this menu key  to your convenience
      menu_name = 'PlatformIO', -- replace this menu name to your convenience
    }
    local pok, nvimpio = pcall(require, 'nvimpio')
    if pok then nvimpio.setup(vim.g.pioConfig) end
```

### Keybinds

These are the default keybindings, which you can override in your configuration.

```lua
    local pok, nvimpio = pcall(require, 'nvimpio')
    if pok then
      nvimpio.setup({
        pio = {
          pio_runtime_dir = '~/.platformio',
          pio_storage_dir = '~/.platformio',
        },
        clangd = {
          support = false,
          install = false
        },
        menu_key = '<leader>\\', -- replace this menu key  to your convenience
        menu_name = 'PlatformIO', -- replace this menu name to your convenience
        debug = false,

        menu_bindings = {
          { node = 'item', desc = 'Switch [E]nv', shortcut = 'e', command = 'PioPickEnv' },
          { node = 'item', desc = '[I]nitiate project', shortcut = 'i', command = 'Pioinit' },
          { node = 'item', desc = '[L]ist terminals', shortcut = 'l', command = 'PioTermList' },
          { node = 'item', desc = 're[S]art clangd', shortcut = 's', command = 'Pioclangdrestart' },
          { node = 'item', desc = '[T]erminal Core CLI', shortcut = 't', command = 'Piocmdf' },
          {
            node = 'menu',
            desc = '[A]dvanced',
            shortcut = 'a',
            items = {
              { node = 'item', desc = '[T]est', shortcut = 't', command = 'Piocmdf test' },
              { node = 'item', desc = '[C]heck', shortcut = 'c', command = 'Piocmdf check' },
              { node = 'item', desc = '[D]ebug', shortcut = 'd', command = 'Piocmdf debug' },
              { node = 'item', desc = 'Compilation Data[b]ase', shortcut = 'b', command = 'PioCompileDB' },
              {
                node = 'menu',
                desc = '[V]erbose',
                shortcut = 'v',
                items = {
                  { node = 'item', desc = 'Verbose [B]uild', shortcut = 'b', command = 'Piocmdf run -v' },
                  { node = 'item', desc = 'Verbose [U]pload', shortcut = 'u', command = 'Piocmdf run -v -t upload' },
                  { node = 'item', desc = 'Verbose [T]est', shortcut = 't', command = 'Piocmdf test -v' },
                  { node = 'item', desc = 'Verbose [C]heck', shortcut = 'c', command = 'Piocmdf check -v' },
                  { node = 'item', desc = 'Verbose [D]ebug', shortcut = 'd', command = 'Piocmdf debug -v' },
                },
              },
            },
          },
          {
            node = 'menu',
            desc = '[D]ependencies',
            shortcut = 'd',
            items = {
              { node = 'item', desc = '[L]ist packages', shortcut = 'l', command = 'Piocmdf pkg list' },
              { node = 'item', desc = '[O]utdated packages', shortcut = 'o', command = 'Piocmdf pkg outdated' },
              { node = 'item', desc = '[U]pdate packages', shortcut = 'u', command = 'Piocmdf pkg update' },
            },
          },
          {
            node = 'menu',
            desc = '[F]lash',
            shortcut = 'f',
            items = {
              { node = 'item', desc = '[B]uild file system', shortcut = 'b', command = 'Piocmdf run -t buildfs' },
              { node = 'item', desc = 'Program [S]ize', shortcut = 's', command = 'Piocmdf run -t size' },
              { node = 'item', desc = '[U]pload file system', shortcut = 'u', command = 'Piocmdf run -t uploadfs' },
              { node = 'item', desc = '[E]rase Flash', shortcut = 'e', command = 'Piocmdf run -t erase' },
            },
          },
          {
            node = 'menu',
            desc = '[G]eneral',
            shortcut = 'g',
            items = {
              { node = 'item', desc = '[B]uild', shortcut = 'b', command = 'Piocmdf run' },
              { node = 'item', desc = '[C]lean', shortcut = 'c', command = 'Piocmdf run -t clean' },
              { node = 'item', desc = '[D]evice list', shortcut = 'd', command = 'Piocmdf device list' },
              { node = 'item', desc = '[F]ull clean', shortcut = 'f', command = 'Piocmdf run -t fullclean' },
              { node = 'item', desc = '[M]onitor', shortcut = 'm', command = 'Piocmdh run -t monitor' },
              { node = 'item', desc = '[U]pload', shortcut = 'u', command = 'Piocmdf run -t upload' },
            },
          },
          {
            node = 'menu',
            desc = '[P]latformIO',
            shortcut = 'p',
            items = {
              { node = 'item', desc = '[U]pgrade PlatformIO Core', shortcut = 'u', command = 'Piocmdf upgrade' },
              { node = 'item', desc = '[I]nstall PlatformIO Core', shortcut = 'i', command = 'PioInstall' },
              { node = 'item', desc = '[G]it ignore', shortcut = 'g', command = 'PioGitIgnore' },
            },
          },
          {
            node = 'menu',
            desc = '[R]emote',
            shortcut = 'r',
            items = {
              { node = 'item', desc = 'Remote [U]pload', shortcut = 'u', command = 'Piocmdf remote run -t upload' },
              { node = 'item', desc = 'Remote [T]est', shortcut = 't', command = 'Piocmdf remote test' },
              { node = 'item', desc = 'Remote [M]onitor', shortcut = 'm', command = 'Piocmdh remote run -t monitor' },
              { node = 'item', desc = 'Remote [D]evices', shortcut = 'd', command = 'Piocmdf remote device list' },
            },
          },
        },

      })
    end
```

### lualine.nvim statusline

```lua
require('lualine').setup({
  sections = {
    lualine_x = {
      function() return require("nvimpio.statusline").get_status_string() end,
      'filetype'
    }
  }
})
```

### native statusline

```lua
vim.opt.statusline:append("%{v:lua.require('nvimpio.statusline').get_status_string()}")
```

### Lazy loading

It's possible to lazy load the plugin using Lazy.nvim, this will load the plugins only when it is needed, to enable lazy loading, add this plugin spec to your config.

```lua
cmd = { 'Pioinit', 'Piorun', 'Piocmdh', 'Piocmdf', 'Piolib', 'Piomon', 'Piodebug', 'Piodb' },
```
