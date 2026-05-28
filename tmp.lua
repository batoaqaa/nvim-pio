-- Create a persistent automation module tracking group
local pio_group = vim.api.nvim_create_augroup('platformio-lsp-pipeline', { clear = true })

vim.api.nvim_create_autocmd('LspAttach', {
  group = pio_group,
  callback = function(args)
    local client = vim.lsp.get_client_by_id(args.data.client_id)
    local bufnr = args.buf

    -- Fast exit: If this attached server isn't clangd, do absolutely nothing
    if not client or client.name ~= 'clangd' then
      return
    end

    vim.api.nvim_echo({ { 'Attaching ' .. client.name .. ' to buffer ' .. bufnr, 'Info' } }, true, {})

    -- 🚀 THE FIX: Intercept using a buffer-local Autocommand Event loop
    -- This intercepts every diagnostic refresh lifecycle event on this buffer *only*
    vim.api.nvim_create_autocmd('DiagnosticChanged', {
      buffer = bufnr,
      group = pio_group,
      callback = function()
        -- Safely load your customized microcontroller filtering table rules
        local success, pio_diag = pcall(require, 'nvimpio.clangd.diagnostic')
        if not (success and pio_diag and pio_diag.clean_diagnostics_pipeline) then
          return
        end

        -- 1. Grab the active internal LSP diagnostic namespace matching this clangd engine
        local ns = vim.lsp.diagnostic.get_namespace(client.id)
        if not ns then
          return
        end

        -- 2. Pull down the diagnostics array currently stored in the namespace cache
        -- We temporarily disable our own event callback tracking to avoid an infinite execution loop
        vim.api.nvim_clear_autocmds({ group = pio_group, buffer = bufnr, event = 'DiagnosticChanged' })

        local raw_diagnostics = vim.diagnostic.get(bufnr, { namespace = ns })
        if #raw_diagnostics > 0 then
          local cleaned = pio_diag.clean_diagnostics_pipeline(raw_diagnostics)

          -- 3. Hard-overwrite Neovim's display table registry with your clean items list
          vim.diagnostic.set(ns, bufnr, cleaned)
        end

        -- 4. Re-enable the buffer execution tracking hook for the next change event
        vim.api.nvim_create_autocmd('DiagnosticChanged', {
          buffer = bufnr,
          group = pio_group,
          callback = vim.api.nvim_get_autocmds({ group = pio_group, buffer = bufnr, event = 'DiagnosticChanged' })[1].callback,
        })
      end,
    })

    -- Execute a micro-evaluation right now to clean the canvas context upon initial open
    vim.cmd('doautocmd DiagnosticChanged')
  end,
})
