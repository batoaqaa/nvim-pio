vim.api.nvim_create_autocmd('LspAttach', {
  group = vim.api.nvim_create_augroup('platformio-lsp-attach', { clear = true }),
  callback = function(args)
    local client = assert(vim.lsp.get_client_by_id(args.data.client_id))
    local bufnr = args.buf

    -- Fast exit: If this attached server isn't clangd, do absolutely nothing
    if not client or client.name ~= 'clangd' then
      return
    end

    vim.api.nvim_echo({ { 'Attaching ' .. client.name .. ' to buffer ' .. bufnr, 'Info' } }, true, {})

    -- Hook up an isolated pipeline overlay dedicated strictly to this active buffer
    client.handlers['textDocument/publishDiagnostics'] = function(err, result, ctx, config)
      -- Exit early on heartbeat noise or completely clear diagnostics packets
      if err or not result or not result.diagnostics or #result.diagnostics == 0 then
        return vim.lsp.handlers['textDocument/publishDiagnostics'](err, result, ctx, config)
      end

      -- Lazy load your customized microcontroller filtering table rules
      local success, pio_diag = pcall(require, 'nvimpio.clangd.diagnostic')
      if success and pio_diag and pio_diag.clean_diagnostics_pipeline then
        result.diagnostics = pio_diag.clean_diagnostics_pipeline(result.diagnostics)
      end

      -- Call the default handler signature using the stripped down diagnostics list
      vim.lsp.handlers['textDocument/publishDiagnostics'](err, result, ctx, config)
    end
  end, ------------------------------------------------------------------
})
