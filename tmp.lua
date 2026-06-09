local M = {}
M.config = {
  panel_height = 0.28,
  winbar_bg = '#80a3d4',
  winbar_fg = '#000000',
  shell = vim.fn.has('win32') == 1 and {
    'pwsh.exe',
    '-NoLogo',
    '-NoProfile',
    '-ExecutionPolicy Bypass',
    '-Command [Console]::InputEncoding=[Console]::OutputEncoding=[System.Text.Encoding]::UTF8;',
  } or { vim.o.shell },
}
return M
