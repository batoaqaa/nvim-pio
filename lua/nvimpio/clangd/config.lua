-----------------------------------------------------------------------------------------
-- Fidget is an unintrusive window in the corner of your editor
--- stylua: ignore start
local fidget_config = {
  version = '*',
  notification = {
    override_vim_notify = true, -- This redirect vim.notify to fidget
    -- filter = vim.log.levels.DEBUG,
    -- How to configure notification groups when instantiated
    configs = { default = require('fidget.notification').default_config },
  },
  progress = {
    -- Clear notification group when LSP server detaches
    clear_on_detach = function(client_id)
      local client = vim.lsp.get_client_by_id(client_id)
      return client and client.name or nil
    end,
    -- How to get a progress message's notification group key
    notification_group = function(msg)
      return msg.lsp_client.name
    end,
    -- Options related to Neovim's built-in LSP client
    lsp = {
      progress_ringbuf_size = 0, -- Configure the nvim's LSP progress ring buffer size
      log_handler = false, -- Log `$/progress` handler invocations (for debugging)
    },
  },
}
local is_fidget_loaded = package.loaded['fidget'] ~= nil
local fidgetok, fidget = pcall(require, 'fidget')
if fidgetok then
  if not is_fidget_loaded then
    fidget.setup({ fidget_config })
  else
    if fidget.options then
      fidget.options = vim.tbl_deep_extend('force', fidget.options or {}, fidget_config)
    else
      -- Fallback safe re-setup block if your user's specific fidget version locks down option fields
      pcall(fidget.setup, fidget_config)
    end
  end
end
vim.notify = require('fidget').notify

-----------------------------------------------------------------------------------------
local is_trouble_loaded = package.loaded['trouble'] ~= nil
local tok, trouble = pcall(require, 'trouble')
if tok then
  if not is_trouble_loaded then
    trouble.setup({})
  end
end

----------------------------------------------------------------------------------------
-- INFO: setup and install mason packages
-----------------------------------------------------------------------------------------
-- 1. Snapshot the memory footprint BEFORE forcing any file reloads
local is_mason_loaded = package.loaded['mason'] ~= nil

-- 2. Safely capture the module references
local mason_ok, mason = pcall(require, 'mason')

-- by default Mason binaries are prepended to the path
if mason_ok then
  if not is_mason_loaded then
    mason.setup({})
  end
end

-- List of packages you want Mason to ensure are installed
-- local ensure_installed = {
--   'clang-format', -- embedded in clangd
--   'stylua',
-- }
-- -- call mason-registry function to install or ensure formatters/linters are installed
-- local mr = require('mason-registry')
-- mr.refresh(function()
--   for _, tool in ipairs(ensure_installed) do
--     local ok, result = pcall(mr.get_package, tool)
--     if ok and result then
--       if not result:is_installed() then
--         -- if not result:is_installing() then
--         result:install({}, function(success, _)
--           if not success then
--             vim.defer_fn(function()
--               OS.notify('LSP: ' .. tool .. ' failed to install', 'error')
--             end, 0)
--           end
--         end)
--         -- end
--       else
--         vim.defer_fn(function()
--           OS.notify('LSP: ' .. tool .. ' already installed', 'warn')
--         end, 0)
--       end
--     else
--       vim.defer_fn(function()
--         OS.notify('LSP: Failed to get package: ' .. tool, 'warn')
--       end, 0)
--     end
--   end
-- end)

----------------------------------------------------------------------------------------
-- INFO: install clangd using mason-lspconfig
-----------------------------------------------------------------------------------------
local mason_lsp_ok, mason_lspconfig = pcall(require, 'mason-lspconfig')
local lspconfig_config = {
  -- Add any servers you want to guarantee exist in your environment
  ensure_installed = { 'clangd', 'lua_ls', 'pyrefly', 'yamlls', 'jsonls' },
  automatic_installation = true,
}

local is_mason_lsp_loaded = package.loaded['mason-lspconfig'] ~= nil
if mason_lsp_ok then
  if not is_mason_lsp_loaded then
    -- CASE 1: True first-time load. Trigger core bridging system and automatic installs.
    mason_lspconfig.setup(lspconfig_config)
  else
    -- -- CASE 2: Already active in runtime memory.
    -- -- Mutate the active configuration table to dynamically register new settings/servers.
    -- local lsp_settings = require('mason-lspconfig.settings')
    --
    -- -- Deep extend the live global configuration table directly
    -- lsp_settings.current = vim.tbl_deep_extend('force', lsp_settings.current or {}, lspconfig_config)
    --
    -- -- 💡 Bonus: If your PlatformIO pipeline just updated `ensure_installed`,
    -- -- you can tell Mason-LSPConfig to immediately process and check for missing servers right now!
    -- require('mason-lspconfig.ensure_installed')()
    pcall(mason_lspconfig.setup, lspconfig_config)
  end
else
  OS.notify('mason-lspconfig is not installed on this system!', 'warn')
end

local capabilities = vim.lsp.protocol.make_client_capabilities()

capabilities.textDocument.foldingRange = {
  textDocument = {
    -- Folding capabilities for nvim-ufo
    foldingRange = {
      dynamicRegistration = false,
      lineFoldingOnly = true,
    },
    diagnostic = {
      dynamicRegistration = true,
    },
  },
}
local bok, blink = pcall(require, 'blink.cmp')
if bok then
  capabilities = blink.get_lsp_capabilities(capabilities)
end

-- INFO: 1
vim.lsp.config('*', {
  capabilities = capabilities,
  root_markers = { '.git' },
  workspace_required = false,
})

-- Apply and Enable
-- local getClangdConfig = require('nvimpio.clangd.control').getClangdConfig
-- if getClangdConfig then
--   vim.lsp.config('clangd', getClangdConfig())
--   vim.lsp.enable('clangd')
-- end

----------------------------------------------------------------------------------------
-- INFO: configure jsonls lsp server
-----------------------------------------------------------------------------------------
local jsonls = {
  -- lazy-load schemastore when needed
  cmd = { 'vscode-json-language-server', '--stdio' },
  filetypes = { 'json', 'jsonc' },
  init_options = { provideFormatter = true },
  root_makers = { '.git' },
}
-- Apply and Enable
vim.lsp.config('jsonls', jsonls)

----------------------------------------------------------------------------------------
-- INFO: configure clangd lsp server
-----------------------------------------------------------------------------------------
local lua_ls = {
  cmd = { 'lua-language-server' },
  filetypes = { 'lua' },
  root_markers = {
    '.luarc.json',
    '.luarc.jsonc',
    '.luacheckrc',
    '.stylua.toml',
    'selene.toml',
    'selene.yml',
    '.git',
  },
  settings = {
    Lua = {
      hint = {
        enable = true,
        arrayIndex = 'Enable',
        await = true,
        paramName = 'All',
        paramType = true,
        semicolon = 'Disable',
        setType = true,
      },
      telemetry = { enable = false },
      diagnostics = { globals = { 'vim' } },
      runtime = {
        -- Specify LuaJIT for Neovim
        version = 'LuaJIT',
        -- Include Neovim runtime files
        path = vim.split(package.path, ';'),
      },
      workspace = {
        checkThirdParty = false,
        library = {
          vim.env.VIMRUNTIME,
          '${3rd}/luv/library',
          './lua',
          vim.api.nvim_get_runtime_file('', true),
          -- Depending on the usage, you might want to add additional paths here.
          -- "${3rd}/busted/library",
        },
      },
    },
  },
}
vim.lsp.config('lua_ls', lua_ls)

local yamlls = {
  -- on_attach = opts.on_attach,
  cmd = { 'yaml-language-server', '--stdio' },
  filetypes = { 'yaml', 'yaml.docker-compose', 'yaml.gitlab' },
  settings = {
    yaml = {
      hover = true,
      validate = false,
      completion = true,
      keyOrdering = false,
      format = { enabled = false },
      redhat = {
        telemetry = { enabled = false },
      },
      schemaStore = {
        enable = true,
        url = 'https://www.schemastore.org/api/json/catalog.json',
      },
      schemas = {
        kubernetes = '*.yaml',
        ['http://json.schemastore.org/github-workflow'] = '.github/workflows/*',
        ['http://json.schemastore.org/github-action'] = '.github/action.{yml,yaml}',
        ['https://raw.githubusercontent.com/microsoft/azure-pipelines-vscode/master/service-schema.json'] = 'azure-pipelines.yml',
        ['http://json.schemastore.org/ansible-stable-2.9'] = 'roles/tasks/*.{yml,yaml}',
        ['http://json.schemastore.org/prettierrc'] = '.prettierrc.{yml,yaml}',
        ['http://json.schemastore.org/kustomization'] = 'kustomization.{yml,yaml}',
        ['http://json.schemastore.org/ansible-playbook'] = '*play*.{yml,yaml}',
        ['http://json.schemastore.org/chart'] = 'Chart.{yml,yaml}',
        ['https://json.schemastore.org/dependabot-v2'] = '.github/dependabot.{yml,yaml}',
        ['https://gitlab.com/gitlab-org/gitlab/-/raw/master/app/assets/javascripts/editor/schema/ci.json'] = '*gitlab-ci*.{yml,yaml}',
        ['https://raw.githubusercontent.com/OAI/OpenAPI-Specification/main/schemas/v3.1/schema.json'] = '*api*.{yml,yaml}',
        ['https://raw.githubusercontent.com/compose-spec/compose-spec/master/schema/compose-spec.json'] = '*docker-compose*.{yml,yaml}',
        ['https://raw.githubusercontent.com/argoproj/argo-workflows/master/api/jsonschema/schema.json'] = '*flow*.{yml,yaml}',
        ['https://raw.githubusercontent.com/yannh/kubernetes-json-schema/refs/heads/master/v1.32.1-standalone-strict/all.json'] = '/*.k8s.yaml',
      },
    },
  },
}
vim.lsp.config('yamlls', yamlls)

local pyrefly = {
  name = 'pyrefly',
  cmd = { 'pyrefly', 'lsp' },
  filetypes = { 'python' },
  root_markers = { 'pyrefly.toml', 'pyproject.toml', 'setup.py', 'setup.cfg', 'requirements.txt', 'Pipfile', '.git' },
  settings = {
    python = {
      pyrefly = {
        displayTypeErrors = 'force-on',
      },
      -- pythonPath = vim.env.VIRTUAL_ENV,
      venvPath = vim.env.VIRTUAL_ENV,
    },
  },
}
vim.lsp.config('pyrefly', pyrefly)

----------------------------------------------------------------------------------
