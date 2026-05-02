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
                vim.notify('LSP: clangd; ' .. tool .. ' failed to install', vim.log.levels.ERROR)
              end, 0)
            end
          end)
        else
          vim.defer_fn(function()
            vim.notify('LSP: clangd; ' .. tool .. ' already installed', vim.log.levels.WARN)
          end, 0)
        end
      end
    else
      vim.defer_fn(function()
        vim.notify('LSP: clangd; Failed to get package: ' .. tool, vim.log.levels.WARN)
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

----------------------------------------------------------------------------------------
-- INFO: configure clangd lsp server
-----------------------------------------------------------------------------------------
--stylua: ignore
function _G.get_clangd_config()
  local new_root_dir = vim.uv.cwd() or '.'
  if not new_root_dir then return end

  -- 1. Safe defaults (Standard clangd behavior)
  local f_flags, q_driver = [["-std=c++17", "-xc++"]], '--query-driver=**'

  -- 2. Run your toolchain detection
  if _G.metadata and _G.metadata.cc_compiler and  _G.metadata.cc_compiler ~= '' then
    if _G.metadata.triplet and _G.metadata.triplet ~= '' then
      -- local include_flags = table.concat(vim.tbl_map(function(item)
      --   return '"' .. item .. '"'
      -- end, _G.metadata.fallbackFlags), ", ")
      --
      -- local includes_toolchain = table.concat(vim.tbl_map(function(item)
      --   return '"' .. item .. '"'
      -- end, _G.metadata.includes_toolchain), ", ")

      f_flags = ''
      -- f_flags = string.format([["-std=gnu++17", "-xc++", "-D__cplusplus=201703L", "--target=%s", "--sysroot=%s", %s, %s]], _G.metadata.triplet, _G.metadata.sysroot, includes_toolchain, include_flags)
      -- f_flags = string.format('"--sysroot=%s"', _G.metadata.sysroot)
      -- f_flags = string.format([["--sysroot=%s", %s]], _G.metadata.sysroot, include_flags)

      -- q_driver =  '**' --_G.metadata.query_driver .. ',C:/PROGRA~1/LLVM/bin/*'  -- use with "--query-driver=%s"
      q_driver =  _G.metadata.query_driver --.. ',C:/PROGRA~1/LLVM/bin/*'          -- use with "--query-driver=%s"
    end
  end

  -- 3. Format your template string
  local table_config = boilerplate_gen([[.clangd_config]], vim.g.platformioRootDir)
  local formatted_str = string.format(table_config or '', q_driver, f_flags, vim.misc.normalizePath(new_root_dir))
  -- local formatted_str = string.format(table_config or '', q_driver, '', vim.misc.normalizePath(new_root_dir))
  -- local formatted_str = string.format(table_config or '', q_driver, '', vim.g.platformioRootDir)

  -- 4. Load the config table
  local cok, clangd_config = pcall(function() return load('return ' .. formatted_str)() end)

  local formated = vim.misc.jsonFormat(clangd_config)
  local file = vim.misc.joinPath(vim.uv.cwd(), 'clangd_config.json')
  vim.misc.writeFile(file, formated, {})

  if cok and clangd_config then
    -- print(vim.inspect(clangd_config))
    return clangd_config
  end
end

-- Apply and Enable
vim.lsp.config('clangd', _G.get_clangd_config())
vim.lsp.enable('clangd')

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

-- restart lsp
-- require('nvimpio.lspConfig.tools').lsp_restart('clangd')
----------------------------------------------------------------------------------
