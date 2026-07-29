# 🚀 nvim-pio

[![Dotfyle Shield](https://dotfyle.com/plugins/batoaqaa/nvim-pio/shield)](https://dotfyle.com/plugins/batoaqaa/nvim-pio)
[![Neovim](https://img.shields.io/badge/Neovim-0.11.0%2B-57A143?style=flat&logo=neovim&logoColor=white)](https://neovim.io)
[![License: Apache 2.0](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](https://opensource.org/licenses/LICENSE-2.0)

A high-performance, asynchronous embedded development framework for Neovim. It bridges **PlatformIO** project structures with **`clangd`** language servers, managing include file mappings and cross-compiler parameter translations on Windows, Linux, and macOS.

---

## ✨ Features

- **Automated Code Insights Mapping:** Discovers and binds toolchain include vectors, firmware library locations, and environment frameworks to your language server.
- **Compiler Flags Neutralization:** Intercepts and strips non-standard bare-metal toolchain argument options (such as `-mlongcalls`) that destabilize desktop language servers.
- **Diagnostic Filtration Interface:** Provides a dynamic selecting utility via `:ClangdFilter` to instantly toggle specific syntax warnings or static alerts.
- **Self-Healing Persistent Configuration:** Workspace options are bound to local context directories, ensuring layout rules persist across cold reboots.

---

## 🛠️ Installation & Setup

### Prerequisites

- **Neovim** $\ge$ 0.11.0
- **Python** $\ge$ 3.9
- **PlatformIO Core CLI** (`pio`) installed and available in system PATH variable.

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
        support = true, -- Master switch for PlatformIO LSP logic
        -- Configures attach integration behavior.
        -- Options:
        --   "attach+" -> Attach the LSP client AND inject default hotkeys.
        --   "attach"  -> Attach the LSP client only (no custom hotkeys).
        --   "none"    -> Do not attach to files at all.
        attach = 'attach+',
        install = false, -- Flags whether to auto-install missing clangd
      },
      menu_key = '<leader>\\',  -- Local workspace menu activation mapping
      menu_name = 'PlatformIO', -- Interactive dashboard selection label
    })
  end,
}
```
