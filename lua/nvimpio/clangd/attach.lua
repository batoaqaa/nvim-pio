-- stylua: ignore start
local M = {}

function M.init(clangd)
  -- INFO: Primary LspAttach execution group
  local pio_group = vim.api.nvim_create_augroup('platformio-lsp-attach', { clear = true })

  vim.api.nvim_create_autocmd('LspAttach', {
    group = pio_group,
    callback = function(args)
      local client = vim.lsp.get_client_by_id(args.data.client_id)
      local bufnr = args.buf

      -- Fast exit: If this attached server isn't clangd, do absolutely nothing
      if not client or client.name ~= 'clangd' then return end

      -- Stop here for non-file buffers (like git://, nvim://, oil://, etc.)
      local uri = vim.uri_from_bufnr(bufnr)
      if not uri:match('^file://') then return end

      ------------------------------------------------------------------
      -- 1. Switch Source / Header Command Definition
      vim.api.nvim_buf_create_user_command(bufnr, 'LspClangdSwitchSourceHeader', function()
        local params = vim.lsp.util.make_text_document_params(bufnr)
        client:request('textDocument/switchSourceHeader', params, function(err, result)
          if err then
            if OS and OS.notify then
              OS.notify('LSP Attach: Clangd Error ' .. tostring(err), 'error')
            else
              vim.notify('LSP Attach: Clangd Error ' .. tostring(err), vim.log.levels.ERROR)
            end
            return
          end
          if not result or result == '' then
            if OS and OS.notify then
              OS.notify('LSP Attach: Corresponding file cannot be determined', 'warn')
            else
              vim.notify('LSP Attach: Corresponding file cannot be determined', vim.log.levels.WARN)
            end
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
      -- 2. Built-in Omnifunc Fallback Completion (If blink.cmp isn't used)
      local ok, _ = pcall(require, 'blink.cmp')
      if not ok then
        if client:supports_method('textDocument/completion') then
          vim.opt.completeopt = { 'menu', 'menuone', 'noselect', 'noinsert', 'fuzzy', 'popup' }

          -- Enable native completion for this specific client and buffer
          vim.lsp.completion.enable(true, client.id, bufnr, { autotrigger = true })
          vim.keymap.set('i', '<C-Space>', function()
            vim.lsp.completion.get()
          end, { buffer = bufnr, desc = 'Trigger native LSP completion' })
        end
      end

      ------------------------------------------------------------------
      -- 3. Modern Inlay Hints Verification Hook
      if client:supports_method('textDocument/inlayHints') then
        vim.lsp.inlay_hint.enable(true, { bufnr = bufnr })
      end

      ------------------------------------------------------------------
      -- 4. Document Colors using Neovim 0.11 syntax
      if vim.lsp.document_color and client:supports_method('textDocument/documentColor') then
        vim.lsp.document_color.enable(true, { bufnr = bufnr, style = 'inline' })
      end

      ------------------------------------------------------------------
      -- 5. Document Word/Symbol Highlighting Lifecycle Hook
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

        -- FIXED: Using a targeted BufDelete listener prevents clearing out 
        -- global LspDetach hooks mid-flight.
        vim.api.nvim_create_autocmd('BufDelete', {
          group = pio_group,
          buffer = bufnr,
          callback = function()
            pcall(vim.lsp.buf.clear_references)
            pcall(vim.api.nvim_clear_autocmds, { group = highlight_augroup, buffer = bufnr })
          end,
        })
      end

      ------------------------------------------------------------------
      -- 6. Execute custom keyboard maps only if "attach+" string profile is active
      if clangd.attach == 'attach+' then
        local lspkeymaps = require('nvimpio.clangd.keymaps')
        lspkeymaps.lspKeymaps(client, bufnr)
      end

      ------------------------------------------------------------------
      -- 7. Stop comment characters from auto-extending down on newline hits
      vim.bo[bufnr].formatoptions = vim.bo[bufnr].formatoptions:gsub('[ro]', '')
    end,
  })

  ----------------------------------------------------------------------
  -- FIXED: Isolated Cleanup Monitoring Group
  -- Keeping this completely separate from 'pio_group' ensures its callbacks
  -- can never be hijacked or bypassed when buffers drop out of runtime memory.
  local cleanup_group = vim.api.nvim_create_augroup('platformio-lsp-cleanup', { clear = true })

  vim.api.nvim_create_autocmd('LspDetach', {
    group = cleanup_group,
    callback = function(arg)
      local bufnr = arg.buf
      local client_id = arg.data.client_id
      local client = vim.lsp.get_client_by_id(client_id)

      print('here')
      -- Fallback parsing block to safely catch client metrics if Neovim 0.11+
      -- has already purged it from the master index tracker pool.
      local client_name = nil
      if client then
        client_name = client.name
      else
        for _, c in ipairs(vim.lsp.get_clients()) do
          if c.id == client_id then
            client_name = c.name
            client = c
            break
          end
        end
      end

      -- If we definitively know a client name and it isn't clangd, ignore it.
      if client_name and client_name ~= 'clangd' then return end
      client_name = client_name or "clangd"

      -- Render notification safely inside a scheduled window layer
      vim.schedule(function()
        if OS and OS.notify then
          OS.notify('Detaching ' .. client_name .. ' from buffer ' .. bufnr, 'info')
        else
          vim.notify('Detaching ' .. client_name .. ' from buffer ' .. bufnr, vim.log.levels.INFO, {
            title = "PlatformIO IDE"
          })
        end
      end)

      -- Process server garbage collection if this was the last active editor tab
      if client and client.attached_buffers then
        local active_buffers = vim.tbl_count(client.attached_buffers)
        if active_buffers <= 1 then
          client:stop(true)
        end
      end
    end,
  })
end

return M
