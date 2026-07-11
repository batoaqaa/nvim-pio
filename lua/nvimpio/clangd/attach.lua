-- stylua: ignore start
local M = {}

function M.init(clangd)
  -- INFO: LspAttach autocommand start
  local pio_group = vim.api.nvim_create_augroup('platformio-lsp-attach', { clear = true })
  vim.api.nvim_create_autocmd('LspAttach', {
    group = pio_group,
    callback = function(args)
      local client = vim.lsp.get_client_by_id(args.data.client_id)
      local bufnr = args.buf

      -- Fast exit: If this attached server isn't clangd, do absolutely nothing
      if not client or client.name ~= 'clangd' then return end

      -- Stop here for non-file buffers (like git:// or nvim://)
      local uri = vim.uri_from_bufnr(bufnr)
      if not uri:match('^file://') then
        return
      end

      print('Attaching to: ' .. client.name .. ' attached to buffer ' .. bufnr)
      ------------------------------------------------------------------
      vim.api.nvim_buf_create_user_command(bufnr, 'LspClangdSwitchSourceHeader', function()
        local params = vim.lsp.util.make_text_document_params(bufnr)
        client:request('textDocument/switchSourceHeader', params, function(err, result)
          if err then
            OS.notify('LSP Attach: Clangd Error ' .. tostring(err), 'error')
            return
          end
          if not result or result == '' then
            OS.notify('LSP Attach: Corresponding file cannot be determined', 'warn')
            return
          end
          -- Use vim.schedule to ensure we aren't editing while the LSP is in a callback
          vim.schedule(function()
            local target = type(result) == 'string' and result or result.uri
            local fname = vim.uri_to_fname(target)
            vim.cmd.edit(fname)
          end)
        end, bufnr)
      end, { desc = 'Switch between source/header' })

      -- Use lsp completion if blink.cmp is not loaded
      local ok, _ = pcall(require, 'blink.cmp')
      if not ok then
        if client:supports_method('textDocument/completion') then
          vim.opt.completeopt = { 'menu', 'menuone', 'noselect', 'noinsert', 'fuzzy', 'popup' }

          -- Enable native completion for this specific client and buffer
          vim.lsp.completion.enable(true, client.id, args.buf, { autotrigger = true })
          vim.keymap.set('i', '<C-Space>', function()
            vim.lsp.completion.get()
          end, { buffer = bufnr, desc = 'Trigger native LSP completion' })
        end
      end

      -- Inlay hints
      if client:supports_method('textDocument/inlayHints') then
        vim.lsp.inlay_hint.enable(true, { bufnr = bufnr })
      end

      -- Document Colors using Neovim 0.11 syntax
      if vim.lsp.document_color and client:supports_method('textDocument/documentColor') then
        vim.lsp.document_color.enable(true, {
          bufnr = args.buf,
          style = 'inline',
        })
      end

      ------------------------------------------------------------------
      if client:supports_method('textDocument/documentHighlight') then
        local highlight_augroup = vim.api.nvim_create_augroup('platformio-lsp-highlight-' .. bufnr, { clear = true })

        vim.api.nvim_create_autocmd({ 'CursorHold', 'CursorHoldI' }, {
          group = highlight_augroup,
          buffer = bufnr,
          callback = vim.lsp.buf.document_highlight,
        })

        vim.api.nvim_create_autocmd({ 'CursorMoved' }, {
          group = highlight_augroup,
          buffer = bufnr,
          callback = vim.lsp.buf.clear_references,
        })

        vim.api.nvim_create_autocmd('LspDetach', {
          group = highlight_augroup,
          buffer = bufnr,
          callback = function(event)
            vim.lsp.buf.clear_references()
            pcall(vim.api.nvim_clear_autocmds, { group = highlight_augroup, buffer = event.buf })
          end,
        })
      end

      ------------------------------------------------------------------
      if clangd.attach == 'attach+' then
        local lspkeymaps = require('nvimpio.clangd.keymaps')
        lspkeymaps.lspKeymaps(client, bufnr)
      end

      ------------------------------------------------------------------
      -- Stop comments from auto-extending onto new lines
      vim.bo[bufnr].formatoptions = vim.bo[bufnr].formatoptions:gsub('[ro]', '')
    end,
  })

  vim.api.nvim_create_autocmd('LspDetach', {
    group = vim.api.nvim_create_augroup('LspCleanup', { clear = true }),
    callback = function(arg)
      local bufnr = arg.buf
      local client_id = arg.data.client_id
      local client = vim.lsp.get_client_by_id(client_id)
      if not client or client.name ~= 'clangd' then return end
      print('Detaching ' .. client.name .. ' from buffer ' .. bufnr)
    end,
  })
end

return M
