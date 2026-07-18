function M.reload_clangd_from_scratch()
  local name = 'clangd'
  local uv = vim.uv or vim.loop

  -- 1. Locate the active runtime client via native 0.11+ query APIs
  local old_client = nil
  for _, client in ipairs(vim.lsp.get_clients({ name = name })) do
    old_client = client
    break
  end

  -- IF NO EXISTING RUNTIME CLIENT: Declaratively update config and boot instantly
  if not old_client then
    vim.lsp.config(name, M.getClangdConfig())
    vim.lsp.enable(name, true)
    print('[LSP Architecture] Fresh pristine clangd instance initialized.')
    return
  end

  -- ============================================================================
  -- NESTED 0.11+: Navigate the modern internal RPC sub-table map safely
  -- ============================================================================
  local rpc_handle = old_client._rpc_client
  if not rpc_handle or not rpc_handle.pid then
    vim.notify('[LSP Architecture] Fatal: Operating system process ID handle missing.', vim.log.levels.ERROR)
    return
  end

  ---@diagnostic disable-next-line: undefined-field
  local old_pid = rpc_handle.pid
  local old_id = old_client.id

  print('[LSP Architecture] Evicting active instance handles for PID: ' .. old_pid)

  -- 2. PHASE A: Native Kernel Signal Injection (Zero Shell Process Overhead)
  local signal_target = (vim.fn.has('win32') == 1) and 9 or 'sigkill'
  local kill_success, _ = pcall(uv.process_kill, { pid = old_pid, signal = signal_target })
  if not kill_success then
    pcall(uv.process_kill, { pid = old_pid, signal = 9 })
  end

  -- 3. PHASE B: EVENT-DRIVEN LIFECYCLE REGISTRATION (No timers, No race conditions)
  local reload_group = vim.api.nvim_create_augroup('Clangd_Cold_Reset_Engine', { clear = true })

  vim.api.nvim_create_autocmd('LspDetach', {
    group = reload_group,
    desc = 'Block execution until Neovim confirms absolute client unregistration',
    callback = function(args)
      if args.data.client_id == old_id then
        vim.api.nvim_del_augroup_by_id(reload_group)

        vim.schedule(function()
          -- Declaratively clear stale attachment metadata spaces
          vim.lsp.enable(name, false)

          -- Apply fresh configuration profiles cleanly
          vim.lsp.config(name, M.getClangdConfig())

          -- Boot the perfectly clean, non-colliding background process daemon
          vim.lsp.enable(name, true)
          print('[LSP Architecture] clangd cold-boot complete via native LspDetach hooks.')
        end)
      end
    end,
  })

  -- 4. PHASE C: Structural Client Broker Disconnection
  vim.lsp.stop_client(old_id, true)
end
