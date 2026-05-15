local M = {}

function M.clean(raw_path)
  if not raw_path or raw_path == '' then
    return nil
  end
  local normalized = vim.fs.normalize(vim.fn.expand(raw_path))
  return M.is_win and normalized:gsub('/', '\\') or normalized
end

return M
