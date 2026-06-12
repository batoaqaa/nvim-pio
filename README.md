# 🚀 nvim-pio

A high-performance, lightweight Neovim plugin that seamlessly bridges **PlatformIO toolchains** with **`clangd`** for embedded development. It automatically discovers your build includes, synchronizes board macro definitions, and eliminates cross-compiler argument errors asynchronously on both Windows and Linux.

---

## ✨ Features

- **Zero-Configuration Includes:** Automatically maps all core toolchain, build framework, and local project library paths to your language server.
- **Dynamic Argument Bridging:** Moves massive compiler search path pools out of sight into a hidden response file (`clangdFlags.txt`) to maximize editing viewport space.
- **Automatic Flag Stripping:** Real-time interceptor gateway catches and neutralizes non-standard microcontroller compiler options (like `-mlongcalls`) that crash standard desktop `clangd`.
- **Interactive Warning Filtering:** Provides an on-demand dropdown menu selection panel (`:ClangdFilter`) to easily toggle specific code diagnostics and alerts.
- **Self-Healing Persistence:** State settings are anchored entirely to your local workspace, ensuring your choices never vanish across cold editor reboots.

---

## 🛠️ Installation & Setup

### Requirements

- **Neovim** ≥ 0.11.0
- **PlatformIO Core CLI** (`pio`) verified in your system environment paths

```
### Minimal nvim full features

Try the plugin with minimal standalone neovim config without modifying your existing
nvim setup. With this minmal cofiguration you can ful featured nvimpio.
**This is especially useful if you're encountering errors during installation or usage**.

```

sh
wget https://raw.githubusercontent.com/batoaqaa/nvim-pio/refs/heads/main/mini_nvimpio.lua
nvim -u nvimpio.lua .

# Now run :Pioinit

````



### 📦 Packaged Configuration (`lazy.nvim`)

```lua
return {
  'batoaqaa/nvim-pio',
  lazy = false,
  dependencies = {
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
  config = function()
    -- Initialize the core plugin setup layer
    local nvimpio = require('nvimpio')
    nvimpio.setup({
      pio = {
        pio_runtime_dir = '~/.platformio',
        pio_storage_dir = '~/.platformio',
      },
      clangd = {
        support = true,
        install = false,
      },
      menu_key = '<leader>\\', -- replace this menu key  to your convenience
      menu_name = 'PlatformIO', -- replace this menu name to your convenience
    })
  end,
}
```

#### Keybinds

These are the default keybindings, which you can override in your configuration.

```lua
    local pok, nvimpio = pcall(require, 'nvimpio')
    if pok then
      nvimpio.setup({
        pio = {
          pio_runtime_dir = vim.fs.joinpath(OS.defaultHome, '.platformio'),
          pio_storage_dir = vim.fs.joinpath(OS.defaultHome, '.platformio'),
        },
        clangd = {
          support = true,
          install = false,
        },
        menu_key = '<leader>\\', -- replace this menu key  to your convenience
        menu_name = 'PlatformIO', -- replace this menu name to your convenience

        menu_bindings = {
          { node = 'item', desc = '[B]lock diagnostic', shortcut = 'b', command = 'ClangdFilter' },
          { node = 'item', desc = '[C]li terminal', shortcut = 'c', command = 'Piocli' },
          { node = 'item', desc = 'Switch [E]nv', shortcut = 'e', command = 'PioPickEnv' },
          { node = 'item', desc = '[I]nitiate project', shortcut = 'i', command = 'Pioinit' },
          { node = 'item', desc = '[L]ist terminals', shortcut = 'l', command = 'PioTermList' },
          { node = 'item', desc = '[M]onitor terminal', shortcut = 'm', command = 'Piomon run -t monitor' },
          { node = 'item', desc = 're[S]art clangd', shortcut = 's', command = 'Clangdrestart' },
          {
            node = 'menu',
            desc = '[A]dvanced',
            shortcut = 'a',
            items = {
              { node = 'item', desc = '[T]est', shortcut = 't', command = 'Piocli test' },
              { node = 'item', desc = '[C]heck', shortcut = 'c', command = 'Piocli check' },
              { node = 'item', desc = '[D]ebug', shortcut = 'd', command = 'Piocli debug' },
              { node = 'item', desc = 'Compilation Data[b]ase', shortcut = 'b', command = 'PioCompileDB' },
              {
                node = 'menu',
                desc = '[V]erbose',
                shortcut = 'v',
                items = {
                  { node = 'item', desc = 'Verbose [B]uild', shortcut = 'b', command = 'Piocli run -v' },
                  { node = 'item', desc = 'Verbose [U]pload', shortcut = 'u', command = 'Piocli run -v -t upload' },
                  { node = 'item', desc = 'Verbose [T]est', shortcut = 't', command = 'Piocli test -v' },
                  { node = 'item', desc = 'Verbose [C]heck', shortcut = 'c', command = 'Piocli check -v' },
                  { node = 'item', desc = 'Verbose [D]ebug', shortcut = 'd', command = 'Piocli debug -v' },
                },
              },
            },
          },
          {
            node = 'menu',
            desc = '[D]ependencies',
            shortcut = 'd',
            items = {
              { node = 'item', desc = '[L]ist packages', shortcut = 'l', command = 'Piocli pkg list' },
              { node = 'item', desc = '[O]utdated packages', shortcut = 'o', command = 'Piocli pkg outdated' },
              { node = 'item', desc = '[U]pdate packages', shortcut = 'u', command = 'Piocli pkg update' },
            },
          },
          {
            node = 'menu',
            desc = '[F]lash',
            shortcut = 'f',
            items = {
              { node = 'item', desc = '[B]uild file system', shortcut = 'b', command = 'Piocli run -t buildfs' },
              { node = 'item', desc = 'Program [S]ize', shortcut = 's', command = 'Piocli run -t size' },
              { node = 'item', desc = '[U]pload file system', shortcut = 'u', command = 'Piocli run -t uploadfs' },
              { node = 'item', desc = '[E]rase Flash', shortcut = 'e', command = 'Piocli run -t erase' },
            },
          },
          {
            node = 'menu',
            desc = '[G]eneral',
            shortcut = 'g',
            items = {
              { node = 'item', desc = '[B]uild', shortcut = 'b', command = 'Piocli run' },
              { node = 'item', desc = '[C]lean', shortcut = 'c', command = 'Piocli run -t clean' },
              { node = 'item', desc = '[D]evice list', shortcut = 'd', command = 'Piocli device list' },
              { node = 'item', desc = '[F]ull clean', shortcut = 'f', command = 'Piocli run -t fullclean' },
              { node = 'item', desc = '[P]arameters hardware setup', shortcut = 'p', command = 'PioSelectPort' },
              { node = 'item', desc = '[U]pload', shortcut = 'u', command = 'Piocli run -t upload' },
            },
          },
          {
            node = 'menu',
            desc = '[P]latformIO',
            shortcut = 'p',
            items = {
              { node = 'item', desc = '[U]pgrade PlatformIO Core', shortcut = 'u', command = 'Piocli upgrade' },
              { node = 'item', desc = '[I]nstall PlatformIO Core', shortcut = 'i', command = 'PioInstall' },
              { node = 'item', desc = '[G]it ignore', shortcut = 'g', command = 'PioGitIgnore' },
            },
          },
          {
            node = 'menu',
            desc = '[R]emote',
            shortcut = 'r',
            items = {
              { node = 'item', desc = 'Remote [U]pload', shortcut = 'u', command = 'Piocli remote run -t upload' },
              { node = 'item', desc = 'Remote [T]est', shortcut = 't', command = 'Piocli remote test' },
              { node = 'item', desc = 'Remote [M]onitor', shortcut = 'm', command = 'Piomon remote run -t monitor' },
              { node = 'item', desc = 'Remote [D]evices', shortcut = 'd', command = 'Piocli remote device list' },
            },
          },
        },
      })
    end
```

<br>

Try the plugin with this minimal standalone config without modifying your existing nvim setup. **This is especially useful if you're encountering errors during installation or usage**.

```sh
wget https://raw.githubusercontent.com/batoaqaa/nvim-pio/refs/heads/main/nvimpio.lua
nvim -u nvimpio.lua .

# Now run :Pioinit
```

---

## 📊 Statusline Integrations

### lualine.nvim Integration

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

### Native Statusline Integration

```lua
vim.opt.statusline:append("%{v:lua.require('nvimpio.statusline').get_status_string()}")
```

---

## 🎮 Usage & Interface

Run **`:ClangdFilter`** (or press your custom user `<leader>\b` shortcut shortcut key mapping) inside any active C++ source file buffer to launch your filter options dropdown picker window panel.

```text
 📁 .clangdFilter.json | Blocked: 2
 ──────────────────────────────────────────────────────────
 💥 Reset All Filters
 [ ] Suppress Code: [unused-includes]
 [*] Restore Code:  [no_member]
 [ ] Suppress Code: [misc-definitions-in-headers]
```

- **Toggle Filters:** Select any warning row entry item to toggle its state. `[*]` items represent lints that are permanently blocked from cluttering your viewport screen display layout view.
- **Commit Actions:** Press **`Escape`** to close out the menu layout view panel. The compiler state machine will instantly merge your selections in RAM, flush your settings to disk, and issue an atomic background buffer re-lint pass instantly.

---

## 📋 File Layout Specifications

### `.clangdFilter.json`

Your single-source-of-truth database record file. It sits securely inside your active microcontroller project root directory folder path so your workspace settings travel with your repository code.

```json
{
  "codes": {
    "no_member": true
  },
  "flags": {
    "-fno-tree-switch-conversion": true,
    "-fstrict-volatile-bitfields": true,
    "-mlongcalls": true
  }
}
```
````
