--- stylua: ignore
-- local piolsp = require('nvimpio.piolsp') --.piolsp
-- INFO: LspAttach autocommand start
local pio_group = vim.api.nvim_create_augroup('platformio-lsp-attach', { clear = true })
vim.api.nvim_create_autocmd('LspAttach', {
  group = pio_group,
  callback = function(args)
    local client = assert(vim.lsp.get_client_by_id(args.data.client_id))
    local bufnr = args.buf

    -- Fast exit: If this attached server isn't clangd, do absolutely nothing
    if not client or client.name ~= 'clangd' then
      return
    end

    vim.api.nvim_echo({ { 'Attaching ' .. client.name .. ' to buffer ' .. bufnr, 'Info' } }, true, {})
    local nvim_pio_diag = require('nvimpio.clangd.diagnostic')

    local buf_path = vim.api.nvim_buf_get_name(bufnr)
    -- Run the root marker scan using a valid string path structure
    if buf_path ~= '' and vim.fs.root(buf_path, { 'platformio.ini' }) then
      -- A. Create a Buffer-Local User Command (:PioMangler)
      vim.api.nvim_buf_create_user_command(bufnr, 'PioMangler', function()
        nvim_pio_diag.manage_file_diagnostics_interactive()
      end, { desc = 'Open LSP Handler Filter Panel' })

      -- B. Create a Buffer-Local Keyboard Shortcut (<leader>pc)
      vim.keymap.set('n', '<leader>pc', function()
        nvim_pio_diag.manage_file_diagnostics_interactive()
      end, {
        buffer = bufnr,
        desc = 'Open LSP Handler Filter Panel',
      })
    end

    -- Hook up an isolated pipeline overlay dedicated strictly to this active buffer

    -- 1. Hook up your isolated pipeline overlay for all future background events

    -- -- 🚀 THE FIX: Intercept using a buffer-local Autocommand Event loop
    -- -- This intercepts every diagnostic refresh lifecycle event on this buffer *only*
    -- vim.api.nvim_create_autocmd('DiagnosticChanged', {
    --   buffer = bufnr,
    --   group = pio_group,
    --   callback = function()
    --     -- Safely load your customized microcontroller filtering table rules
    --     local success, pio_diag = pcall(require, 'nvimpio.clangd.diagnostic')
    --     if not (success and pio_diag and pio_diag.clean_diagnostics_pipeline) then
    --       return
    --     end
    --
    --     -- 1. Grab the active internal LSP diagnostic namespace matching this clangd engine
    --     local ns = vim.lsp.diagnostic.get_namespace(client.id)
    --     if not ns then
    --       return
    --     end
    --
    --     -- 2. Pull down the diagnostics array currently stored in the namespace cache
    --     -- We temporarily disable our own event callback tracking to avoid an infinite execution loop
    --     vim.api.nvim_clear_autocmds({ group = pio_group, buffer = bufnr, event = 'DiagnosticChanged' })
    --
    --     local raw_diagnostics = vim.diagnostic.get(bufnr, { namespace = ns })
    --     if #raw_diagnostics > 0 then
    --       local cleaned = pio_diag.clean_diagnostics_pipeline(raw_diagnostics)
    --
    --       -- 3. Hard-overwrite Neovim's display table registry with your clean items list
    --       vim.diagnostic.set(ns, bufnr, cleaned)
    --     end
    --
    --     -- 4. Re-enable the buffer execution tracking hook for the next change event
    --     vim.api.nvim_create_autocmd('DiagnosticChanged', {
    --       buffer = bufnr,
    --       group = pio_group,
    --       callback = vim.api.nvim_get_autocmds({ group = pio_group, buffer = bufnr, event = 'DiagnosticChanged' })[1].callback,
    --     })
    --   end,
    -- })
    -- -- Execute a micro-evaluation right now to clean the canvas context upon initial open
    -- vim.cmd('doautocmd DiagnosticChanged')

    -- client.handlers['textDocument/publishDiagnostics'] = function(err, result, ctx, config)
    --   -- Exit early on heartbeat noise or completely clear diagnostics packets
    --   if err or not result or not result.diagnostics or #result.diagnostics == 0 then
    --     return vim.lsp.handlers['textDocument/publishDiagnostics'](err, result, ctx, config)
    --   end
    --
    --   -- Lazy load your customized microcontroller filtering table rules
    --   local success, pio_diag = pcall(require, 'nvimpio.clangd.diagnostic')
    --   if success and pio_diag and pio_diag.clean_diagnostics_pipeline then
    --     result.diagnostics = pio_diag.clean_diagnostics_pipeline(result.diagnostics)
    --   end
    --
    --   -- Call the default handler signature using the stripped down diagnostics list
    --   vim.lsp.handlers['textDocument/publishDiagnostics'](err, result, ctx, config)
    -- end
    ------------------------------------------------------------------
    local uri = vim.uri_from_bufnr(bufnr)
    if not uri:match('^file://') then
      return -- Stop here for non-file buffers (like git:// or nvim://)
    end
    vim.api.nvim_buf_create_user_command(bufnr, 'LspClangdSwitchSourceHeader', function()
      local params = vim.lsp.util.make_text_document_params(bufnr)
      client:request('textDocument/switchSourceHeader', params, function(err, result)
        if err then
          vim.misc.notify('LSP Attach: Clangd Error ' .. tostring(err), 'error')
          return
        end
        if not result or result == '' then
          vim.misc.notify('LSP Attach: Corresponding file cannot be determined', 'warn')
          return
        end
        -- Use vim.schedule to ensure we aren't editing while the LSP is in a callback
        vim.schedule(function()
          local target = type(result) == 'string' and result or result.uri
          local fname = vim.uri_to_fname(target)
          vim.cmd.edit(vim.uri_to_fname(fname))
        end)
      end, bufnr)
    end, { desc = 'Switch between source/header' })

    -- use lsp completion if no blink
    local ok, _ = pcall(require, 'blink.cmp')
    if not ok then
      if client:supports_method('textDocument/completion') then
        vim.opt.completeopt = { 'menu', 'menuone', 'noselect', 'noinsert', 'fuzzy', 'popup' }

        -- Enable native completion for this specific client and buffer
        vim.lsp.completion.enable(true, client.id, args.buf, { autotrigger = true })
        vim.keymap.set('i', '<C-Space', function()
          vim.lsp.completion.get()
        end)
      end
    end

    -- Inlay hints
    if client:supports_method('textDocument/inlayHints') then
      vim.lsp.inlay_hint.enable(true, { bufnr = bufnr })
    end

    if vim.lsp.document_color and client:supports_method('textDocument/documentColor') then
      -- vim.lsp.document_color.enable(true, args.buf, { style = 'background', -- 'background', 'foreground', or 'virtual' })
      vim.lsp.document_color.enable(true, {
        bufnr = args.buf,
        style = 'inline', -- This is the modern 0.11 way to show color icons
      })
    end

    ------------------------------------------------------------------
    if client and client:supports_method('textDocument/documentHighlight') then
      local highlight_augroup = vim.api.nvim_create_augroup('platformio-lsp-highlight', { clear = false })

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
      --
      vim.api.nvim_create_autocmd('LspDetach', {
        group = highlight_augroup,
        -- group = vim.api.nvim_create_augroup('platformio-lsp-detach', { clear = true }),
        callback = function(event)
          vim.lsp.buf.clear_references()
          vim.api.nvim_clear_autocmds({ group = 'platformio-lsp-highlight', buffer = event.buf })
        end,
      })
      --
    end

    ------------------------------------------------------------------
    local lspkeymaps = require('nvimpio.clangd.keymaps')
    lspkeymaps.lspKeymaps(client, bufnr)

    ------------------------------------------------------------------
    vim.cmd([[autocmd FileType * set formatoptions-=ro]])
    --
  end,
})

vim.api.nvim_create_autocmd('LspDetach', {
  group = vim.api.nvim_create_augroup('LspCleanup', { clear = true }),
  callback = function(arg)
    local bufnr = arg.buf
    local client = vim.lsp.get_client_by_id(arg.data.client_id)
    if client and client.attached_buffers then
      vim.api.nvim_echo({ { 'Detaching ' .. client.name .. ' from buffer ' .. bufnr, 'Info' } }, true, {})
      -- local count = 0
      -- for _ in pairs(client.attached_buffers) do
      --   count = count + 1
      -- end
      --
      -- if count == 1 then
      --   client:stop(true)
      -- end
    end
  end,
})

-- --> End LspAttach autocommand
