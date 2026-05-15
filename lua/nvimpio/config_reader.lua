local M = {}
-- stylua: ignore
function M.check_ini_override()
  local ini_file = vim.fn.getcwd() .. OS.folder_sep .. 'platformio.ini'
  if vim.fn.filereadable(ini_file) == 0 then return nil end

  local in_platformio_section = false

  for _, line in ipairs(vim.fn.readfile(ini_file)) do
    local clean = line:lower():gsub('%s+', '') -- Strip whitespace & normalize casing

    if clean:match('^%[platformio%]$') then in_platformio_section = true
    elseif clean:match('^%[.*%]$') then in_platformio_section = false
    elseif in_platformio_section and clean:match('^core_dir=') then return line:match('=%s*(.-)%s*$') end
  end
  return nil
end

return M
