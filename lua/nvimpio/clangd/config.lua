local boilerplate_gen = require('nvimpio.boilerplate').boilerplate_gen
local ok, result
ok, result = pcall(require, 'fidget')
if ok then
  result.setup({})
end

-----------------------------------------------------------------------------------------
ok, result = pcall(require, 'trouble')
if ok then
  result.setup({})
end

----------------------------------------------------------------------------------------
-- INFO: setup and install mason packages
-----------------------------------------------------------------------------------------
ok, result = pcall(require, 'mason')
if ok then
  result.setup({
    PATH = 'append',
    ui = {
      border = 'single',
      icons = {
        package_installed = '✓',
        package_pending = '➜',
        package_uninstalled = '✗',
      },
    },
  })
end

-- List of packages you want Mason to ensure are installed
local ensure_installed = {
  -- 'clang-format', embeded in clangd
  -- 'stylua',
}
-- call mason-registry function to install or ensure formatters/linters are installed
local mr = require('mason-registry')
mr.refresh(function()
  for _, tool in ipairs(ensure_installed) do
    ok, result = pcall(mr.get_package, tool)
    if ok and result then
      if not result:is_installed() then
        if not result:is_installing() then
          result:install({}, function(success, _)
            if not success then
              vim.defer_fn(function()
                vim.misc.notify('LSP: clangd; ' .. tool .. ' failed to install', 'error')
              end, 0)
            end
          end)
        else
          vim.defer_fn(function()
            vim.misc.notify('LSP: clangd; ' .. tool .. ' already installed', 'warn')
          end, 0)
        end
      end
    else
      vim.defer_fn(function()
        vim.misc.notify('LSP: clangd; Failed to get package: ' .. tool, 'warn')
      end, 0)
    end
  end
end)

----------------------------------------------------------------------------------------
-- INFO: install clangd using mason-lspconfig
-----------------------------------------------------------------------------------------
local mok, mason_lspconfig = pcall(require, 'mason-lspconfig')
if mok then
  mason_lspconfig.setup({
    ensure_installed = { 'clangd', 'lua_ls', 'pyrefly', 'yamlls', 'jsonls' },
    automatic_enable = true, -- this will automatically enable LSP servers after lsp.config
  })
end

local capabilities = vim.lsp.protocol.make_client_capabilities()

capabilities.textDocument.foldingRange = {
  textDocument = {
    -- Folding capabilities for nvim-ufo
    foldingRange = {
      dynamicRegistration = false,
      lineFoldingOnly = true,
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
local getClangdConfig = require('nvimpio.clangd.control').getClangdConfig()
if getClangdConfig then
  vim.lsp.config('clangd', getClangdConfig())
  vim.lsp.enable('clangd')
end

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

require('nvimpio.clangd.attach')
----------------------------------------------------------------------------------
