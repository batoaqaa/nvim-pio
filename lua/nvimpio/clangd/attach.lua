-- stylua: ignore start
local M = {}

function M.init(clangd)
  -- INFO: Shared high-performance autocommand groups
  local pio_attach_group = vim.api.nvim_create_augroup('platformio-lsp-attach', { clear = true })
  local pio_cleanup_group = vim.api.nvim_create_augroup('platformio-lsp-cleanup', { clear = true })
  local pio_highlight_group = vim.api.nvim_create_augroup('platformio-lsp-highlight', { clear = false })

  vim.api.nvim_create_autocmd('LspAttach', {
    group = pio_attach_group,
    callback = function(args)
      local client = vim.lsp.get_client_by_id(args.data.client_id)
      local bufnr = args.buf

      -- Fast exit: If this attached server isn't clangd, do absolutely nothing
      if not client or client.name ~= 'clangd' then return end

      -- Stop here for non-file buffers (like git:// or nvim://)
      local uri = vim.uri_from_bufnr(bufnr)
      if not uri:match('^file://') then return end

      -- Get the human-readable filename for clean logs
      local filename = vim.fs.basename(vim.api.nvim_buf_get_name(bufnr)) or "Unknown"
      print('Attaching to: ' .. client.name .. ' attached to buffer ' .. bufnr .. ' ' .. filename)

      ------------------------------------------------------------------
      -- 1. Switch Source/Header Command
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
          vim.schedule(function()
            local target = type(result) == 'string' and result or result.uri
            local fname = vim.uri_to_fname(target)
            vim.cmd.edit(fname)
          end)
        end, bufnr)
      end, { desc = 'Switch between source/header' })

      ------------------------------------------------------------------
      -- 2. Built-in Completion Fallback
      local ok, _ = pcall(require, 'blink.cmp')
      if not ok then
        if client:supports_method('textDocument/completion') then
          vim.opt.completeopt = { 'menu', 'menuone', 'noselect', 'noinsert', 'fuzzy', 'popup' }
          vim.lsp.completion.enable(true, client.id, bufnr, { autotrigger = true })
          vim.keymap.set('i', '<C-Space>', function()
            vim.lsp.completion.get()
          end, { buffer = bufnr, desc = 'Trigger native LSP completion' })
        end
      end

      ------------------------------------------------------------------
      -- 3. Inlay Hints
      if client:supports_method('textDocument/inlayHints') then
        vim.lsp.inlay_hint.enable(true, { bufnr = bufnr })
      end

      ------------------------------------------------------------------
      -- 4. Document Colors (Neovim 0.11 syntax)
      if vim.lsp.document_color and client:supports_method('textDocument/documentColor') then
        vim.lsp.document_color.enable(true, { bufnr = bufnr, style = 'inline' })
      end

      ------------------------------------------------------------------
      -- 5. Document Highlight (Uses global group scoped strictly to buffer)
      if client:supports_method('textDocument/documentHighlight') then
        vim.api.nvim_create_autocmd({ 'CursorHold', 'CursorHoldI' }, {
          group = pio_highlight_group,
          buffer = bufnr,
          callback = vim.lsp.buf.document_highlight,
        })

        vim.api.nvim_create_autocmd({ 'CursorMoved' }, {
          group = pio_highlight_group,
          buffer = bufnr,
          callback = vim.lsp.buf.clear_references,
        })

        -- Clear highlights cleanly when detaching
        vim.api.nvim_create_autocmd('LspDetach', {
          group = pio_highlight_group,
          buffer = bufnr,
          callback = function(event)
            pcall(vim.lsp.buf.clear_references)
            -- Clear autocommands ONLY for this buffer inside the shared group
            pcall(vim.api.nvim_clear_autocmds, { group = pio_highlight_group, buffer = event.buf })
          end,
        })
      end

      ------------------------------------------------------------------
      -- 6. Keyboard Maps Injections
      if clangd.attach == 'attach+' then
        local lspkeymaps = require('nvimpio.clangd.keymaps')
        lspkeymaps.lspKeymaps(client, bufnr)
      end

      ------------------------------------------------------------------
      -- 7. Stop comment characters from auto-extending
      vim.bo[bufnr].formatoptions = vim.bo[bufnr].formatoptions:gsub('[ro]', '')
    end,
  })

  ----------------------------------------------------------------------
  -- INFO: Global Cleanup Monitoring
  vim.api.nvim_create_autocmd('LspDetach', {
    group = pio_cleanup_group,
    callback = function(arg)
      local bufnr = arg.buf
      local client_id = arg.data.client_id
      local client = vim.lsp.get_client_by_id(client_id)

      if not client or client.name ~= 'clangd' then return end

      local filename = vim.fs.basename(vim.api.nvim_buf_get_name(bufnr)) or "Unknown"
      print('Detaching ' .. client.name .. ' from buffer ' .. bufnr .. ' ' .. filename)
    end,
  })
end

return M
