-- Create a dedicated Neovim event group for our diagnostic popup helper
local diag_helper_group = vim.api.nvim_create_augroup('DiagnosticCodePopup', { clear = true })

vim.api.nvim_create_autocmd('CursorHold', {
  group = diag_helper_group,
  pattern = { '*.cpp', '*.h', '*.c' }, -- Only listen to C/C++ project files
  callback = function()
    -- Get all diagnostics currently active under the user's cursor position
    local line, col = unpack(vim.api.nvim_win_get_cursor(0))
    local diagnostics = vim.diagnostic.get(0, { lnum = line - 1 })

    -- Loop through the diagnostics on this line to see if one is under the cursor column
    for _, diag in ipairs(diagnostics) do
      if col >= diag.col and col <= diag.end_col then
        local code_name = diag.code

        -- If the error has a valid internal code name, construct the popup window
        if code_name and code_name ~= '' then
          local lines = {
            ' 🔍 FOUND LSP DIAGNOSTIC CODE ',
            '──────────────────────────────',
            ' Name: ' .. tostring(code_name),
            '──────────────────────────────',
            ' Add this string to your blocklist! ',
          }

          -- Define floating layout properties
          local buf = vim.api.nvim_create_buf(false, true)
          vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

          -- Render the popup floating right next to your cursor
          vim.api.nvim_open_win(buf, false, {
            relative = 'cursor',
            row = 1,
            col = 0,
            width = #lines[1] + 2,
            height = #lines,
            style = 'minimal',
            border = 'rounded',
          })
          break -- Exit the loop as soon as the active error code is found
        end
      end
    end
  end,
})

-- Configure how fast Neovim checks for the cursor hold event (in milliseconds)
vim.o.updatetime = 400 -- Pops up 400ms after you stop moving your cursor
