# 🚀 nvim-pio

A high-performance, asynchronous embedded development framework for Neovim. It bridges **PlatformIO** project structures with **`clangd`** language servers, managing include file mappings and cross-compiler parameter translations on Windows, Linux, and macOS.

---

## ✨ Features

- **Automated Code Insights Mapping:** Discovers and binds toolchain include vectors, firmware library locations, and environment frameworks to your language server.
- **Compiler Flags Neutralization:** Intercepts and strips non-standard bare-metal toolchain argument options (such as `-mlongcalls`) that destabilize desktop language servers.
- **Dynamic Argument Deflating:** Pushes complex macro search paths into localized response files (`clangdFlags.txt`), optimizing your editor layout context.
- **Diagnostic Filtration Interface:** Provides a dynamic selecting utility via `:ClangdFilter` to instantly toggle specific syntax warnings or static alerts.
- **Self-Healing Persistent Configuration:** Workspace options are bound to local context directories, ensuring layout rules persist across cold reboots.

---

## 🛠️ Installation & Setup

### Prerequisites

- **Neovim** $\ge$ 0.11.0
- **PlatformIO Core CLI** (`pio`) installed and available in system PATH variables.

### 📦 Package Integration (`lazy.nvim`)

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
      'williamboman/mason-lspconfig.nvim',
      dependencies = {
        { 'williamboman/mason.nvim' },
        { 'folke/trouble.nvim' },
        { 'j-hui/fidget.nvim' },
      },
    },
  },
  config = function()
    require('nvimpio').setup({
      pio = {
        pio_runtime_dir = '~/.platformio',
        pio_storage_dir = '~/.platformio',
      },
      clangd = {
        support = true,
        install = false,
      },
      menu_key = '<leader>\\',  -- Local workspace menu activation mapping
      menu_name = 'PlatformIO', -- Interactive dashboard selection label
    })
  end,
}
```

---

## ⌨️ Workspace Menu Configuration Specification

The interactive PlatformIO dashboard mapping parameters can be fully configured using the structured `menu_bindings` node array layer inside your setup invocation block:

<details>
  <summary>🔍 Click to view complete declaration snippet specifications</summary>

```lua
require('nvimpio').setup({
  menu_key = '<leader>\\',
  menu_name = 'PlatformIO',
  menu_bindings = {
    { node = 'item', desc = '[B]lock diagnostic', shortcut = 'b', command = 'ClangdFilter' },
    { node = 'item', desc = '[C]li terminal',     shortcut = 'c', command = 'Piocli' },
    { node = 'item', desc = 'Switch [E]nv',       shortcut = 'e', command = 'PioPickEnv' },
    { node = 'item', desc = '[I]nitiate project',  shortcut = 'i', command = 'Pioinit' },
    { node = 'item', desc = '[M]onitor terminal',  shortcut = 'm', command = 'Piomon' },
    { node = 'item', desc = 're[S]tart clangd',   shortcut = 's', command = 'Clangdrestart' },
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
            { node = 'item', desc = 'Verbose [B]uild',   shortcut = 'b', command = 'Piocli run -v' },
            { node = 'item', desc = 'Verbose [U]pload',  shortcut = 'u', command = 'Piocli run -v -t upload' },
            { node = 'item', desc = 'Verbose [T]est',    shortcut = 't', command = 'Piocli test -v' },
            { node = 'item', desc = 'Verbose [C]heck',   shortcut = 'c', command = 'Piocli check -v' },
            { node = 'item', desc = 'Verbose [D]ebug',   shortcut = 'd', command = 'Piocli debug -v' },
          },
        },
      },
    },
    {
      node = 'menu',
      desc = '[D]ependencies',
      shortcut = 'd',
      items = {
        { node = 'item', desc = '[L]ist packages',     shortcut = 'l', command = 'Piocli pkg list' },
        { node = 'item', desc = '[O]utdated packages', shortcut = 'o', command = 'Piocli pkg outdated' },
        { node = 'item', desc = '[U]pdate packages',    shortcut = 'u', command = 'Piocli pkg update' },
      },
    },
    {
      node = 'menu',
      desc = '[F]lash',
      shortcut = 'f',
      items = {
        { node = 'item', desc = '[B]uild file system',  shortcut = 'b', command = 'Piocli run -t buildfs' },
        { node = 'item', desc = 'Program [S]ize',       shortcut = 's', command = 'Piocli run -t size' },
        { node = 'item', desc = '[U]pload file system', shortcut = 'u', command = 'Piocli run -t uploadfs' },
        { node = 'item', desc = '[E]rase Flash',        shortcut = 'e', command = 'Piocli run -t erase' },
      },
    },
    {
      node = 'menu',
      desc = '[G]eneral',
      shortcut = 'g',
      items = {
        { node = 'item', desc = '[B]uild',                     shortcut = 'b', command = 'Piocli run' },
        { node = 'item', desc = '[C]lean',                     shortcut = 'c', command = 'Piocli run -t clean' },
        { node = 'item', desc = '[D]evice list',               shortcut = 'd', command = 'Piocli device list' },
        { node = 'item', desc = '[F]ull clean',                shortcut = 'f', command = 'Piocli run -t fullclean' },
        { node = 'item', desc = '[P]arameters hardware setup', shortcut = 'p', command = 'PioSelectPort' },
        { node = 'item', desc = '[U]pload',                    shortcut = 'u', command = 'Piocli run -t upload' },
      },
    },
    {
      node = 'menu',
      desc = '[P]latformIO',
      shortcut = 'p',
      items = {
        { node = 'item', desc = 're[F]resh PlatformIO project data', shortcut = 'f', command = 'PioRefreshData' },
        { node = 'item', desc = '[G]it ignore',                      shortcut = 'g', command = 'PioGitIgnore' },
        { node = 'item', desc = '[I]nstall PlatformIO Core',         shortcut = 'i', command = 'PioInstall' },
        { node = 'item', desc = '[R]epair PlatformIO Core',          shortcut = 'r', command = 'PioRepair' },
        { node = 'item', desc = '[U]pgrade PlatformIO Core',         shortcut = 'u', command = 'Piocli upgrade' },
      },
    },
    {
      node = 'menu',
      desc = '[R]emote',
      shortcut = 'r',
      items = {
        { node = 'item', desc = 'Remote [U]pload',  shortcut = 'u', command = 'Piocli remote run -t upload' },
        { node = 'item', desc = 'Remote [T]est',    shortcut = 't', command = 'Piocli remote test' },
        { node = 'item', desc = 'Remote [M]onitor', shortcut = 'm', command = 'Piomon remote run -t monitor' },
        { node = 'item', desc = 'Remote [D]evices', shortcut = 'd', command = 'Piocli remote device list' },
      },
    },
  },
})
```

</details>

---

## ⚡ Isolated Evaluation Environment (Zero-Risk Sandbox)

Test the complete capabilities of this extension inside an insulated runtime sandbox without modifying your production editor configurations. Execute this sequence from a standard terminal prompt:

```sh
# Fetch the automated sandbox bootstrapper script
wget https://githubusercontent.com

# Execute the isolated evaluation environment
nvim -u minimal.lua
```

---

> [!TIP]
> You can `:checkhealth nvimpio` to ensure you have all the required
> dependencies. It can also check that your config table looks correct. This is
> still in its early stages, so please file issues if you'd like to see more
> checks added or a check isn't working properly.
>
> `:h nvimpio` for help

<details>
  <summary>
## 📊 Statusline Integrations
  </summary>

### lualine.nvim Integration

Utilizes a safe `pcall` structural check to ensure your statusline never crashes if the plugin hasn't finished loading yet during the `lazy.nvim` startup cycle:

```lua
require('lualine').setup({
  sections = {
    lualine_x = {
      function()
        local ok, statusline = pcall(require, 'nvimpio.statusline')
        if ok and type(statusline.get_status_string) == 'function' then
          return statusline.get_status_string()
        end
        return ""
      end,
      'filetype'
    }
  }
})
```

### Native Statusline Integration

If you don't have lualine, use this native nvim statusline.

```lua
vim.opt.statusline:append("%{v:lua.require('nvimpio.statusline').get_status_string()}")
```
