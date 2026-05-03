local M = {}

-- -- INFO:

--- stylua: ignore
function M.pioClangdRestart()
  local name = 'clangd'
  -- vim.schedule_wrap(function()
  vim.notify('LSP: Clangd restart.', vim.log.levels.WARN)

  local clangConfig = _G.get_clangd_config()
  -- print(vim.inspect(clangConfig))
  vim.lsp.config(name, clangConfig)
  vim.lsp.enable(name, false)
  vim.lsp.enable(name, true)
  vim.cmd('checktime')
  _G.metadata.isBusy = false
  -- end)
end

return M
