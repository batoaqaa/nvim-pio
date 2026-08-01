local K = {}

function K.lspKeymaps(client, bufnr)
  local bufkeymap = function(mode, lhs, rhs, desc)
    vim.keymap.set(mode, lhs, rhs, { buffer = bufnr, silent = true, desc = desc })
  end

  -- Disable Neovim 0.10 default LSP keymaps to avoid conflicts
  for _, key in ipairs({ 'gra', 'gri', 'grn', 'grr', 'gO', 'K' }) do
    pcall(vim.keymap.del, 'n', key, { buffer = bufnr })
  end

  -- Quickfix navigation
  bufkeymap('n', '[q', vim.cmd.cprev, 'Previous quickfix item')
  bufkeymap('n', ']q', vim.cmd.cnext, 'Next quickfix item')

  -- Diagnostic keymaps
  bufkeymap('n', '[d', function()
    vim.diagnostic.jump({ count = -1, float = true })
  end, 'Go to previous diagnostic')
  bufkeymap('n', ']d', function()
    vim.diagnostic.jump({ count = 1, float = true })
  end, 'Go to next diagnostic')

  bufkeymap('n', 'gle', vim.diagnostic.open_float, 'Show diagnostic error messages')
  bufkeymap('n', 'glq', vim.diagnostic.setloclist, 'Open diagnostic quickfix list')

  -- LSP Capabilities
  if client.server_capabilities.hoverProvider then
    bufkeymap('n', 'glk', vim.lsp.buf.hover, 'Hover Documentation')
  end
  if client.server_capabilities.signatureHelpProvider then
    bufkeymap({ 'i', 'n' }, 'gls', vim.lsp.buf.signature_help, 'Show signature')
  end
  if client.server_capabilities.declarationProvider then
    bufkeymap('n', 'glD', vim.lsp.buf.declaration, 'Goto Declaration')
  end
  if client.server_capabilities.definitionProvider then
    bufkeymap('n', 'gld', vim.lsp.buf.definition, 'Go to definition')
  end
  if client.server_capabilities.typeDefinitionProvider then
    bufkeymap('n', 'glt', vim.lsp.buf.type_definition, 'Goto type definition')
  end
  if client.server_capabilities.implementationProvider then
    bufkeymap('n', 'gli', vim.lsp.buf.implementation, 'Goto implementation')
  end
  if client.server_capabilities.referencesProvider then
    bufkeymap('n', 'glr', '<cmd>Telescope lsp_references<CR>', 'Goto references')
  end
  if client.server_capabilities.renameProvider then
    bufkeymap('n', 'glR', vim.lsp.buf.rename, 'Rename symbol')
  end
  if client.server_capabilities.codeActionProvider then
    bufkeymap('n', 'gla', vim.lsp.buf.code_action, 'Code action')
  end

  -- Telescope Base Theme Config
  local get_symbol_theme = function(custom_opts)
    return require('telescope.themes').get_dropdown(vim.tbl_extend('force', {
      symbols = { 'function', 'method' },
      initial_mode = 'normal',
      prompt_prefix = '🔍  ',
      selection_caret = '❯ ',
      layout_config = { height = 25 },
    }, custom_opts or {}))
  end

  if client.server_capabilities.documentSymbolProvider then
    bufkeymap('n', 'glwd', function()
      require('telescope.builtin').lsp_document_symbols(get_symbol_theme())
    end, 'Find Document Symbols')
  end

  if client.server_capabilities.workspaceSymbolProvider or client:supports_method('workspace/symbol') then
    bufkeymap('n', 'glww', function()
      -- Query = ' ' forces clangd workspace symbol lookup immediately
      require('telescope.builtin').lsp_dynamic_workspace_symbols(get_symbol_theme({ query = ' ' }))
    end, 'Find Workspace Symbols')
  end

  -- Workspace management
  if client.server_capabilities.workspace then
    bufkeymap('n', 'glwa', vim.lsp.buf.add_workspace_folder, 'Workspace add folder')
    bufkeymap('n', 'glwr', vim.lsp.buf.remove_workspace_folder, 'Workspace remove folder')
    bufkeymap('n', 'glwl', function()
      print(vim.inspect(vim.lsp.buf.list_workspace_folders()))
    end, 'Workspace list folders')
  end

  -- Clangd specific
  if client:supports_method('textDocument/switchSourceHeader') then
    -- bufkeymap('n', 'glws', '<cmd>ClangdSwitchSourceHeader<cr>', 'Switch Source/Header (C/C++)')
    bufkeymap('n', 'glws', function()
      client:request('textDocument/switchSourceHeader', { uri = vim.uri_from_bufnr(bufnr) }, function(err, result)
        if err or not result then
          vim.notify('Corresponding source/header file not found', vim.log.levels.WARN)
          return
        end
        vim.api.nvim_command('edit ' .. vim.uri_to_fname(result))
      end, bufnr)
    end, 'Switch Source/Header (C/C++)')
  end

  -- Formatting
  if client:supports_method('textDocument/formatting') then
    bufkeymap({ 'n', 'x' }, 'glf', function()
      vim.lsp.buf.format({ bufnr = bufnr, async = true })
    end, 'Format buffer')

    -- Buffer-isolated auto-format on save
    local fmt_group = vim.api.nvim_create_augroup('autoformat_' .. bufnr, { clear = true })
    vim.api.nvim_create_autocmd('BufWritePre', {
      buffer = bufnr,
      group = fmt_group,
      desc = 'Format current buffer on save',
      callback = function(args)
        vim.lsp.buf.format({
          bufnr = args.buf,
          async = false,
          timeout_ms = 3000,
          id = client.id,
        })
      end,
    })
  end

  -- Inlay Hints
  if client.server_capabilities.inlayHintProvider and vim.lsp.inlay_hint then
    bufkeymap('n', 'glh', function()
      local enable = not vim.lsp.inlay_hint.is_enabled({ bufnr = bufnr })
      vim.lsp.inlay_hint.enable(enable, { bufnr = bufnr })
    end, 'Toggle Inlay Hints')
  end
end

return K
