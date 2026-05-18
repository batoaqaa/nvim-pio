-- Define a global function so Neovim's C-engine can access it from anywhere
function _G.my_native_statusline()
  -- 1. Left side items (Mode, File path, modifications markers)
  local mode = '%#StatusLineNC# %{mode()} ' -- Displays active mode (NORMAL, INSERT, etc.)
  local file_path = '%#Normal# %f ' -- Relative path to the active buffer file
  local modified = '%m%r%h%w ' -- Displays [+] if modified, [RO] if read-only

  -- 2. The Alignment Splitter (Pushes everything after it to the far right side)
  local alignment = '%='

  -- 3. The PlatformIO Integration Layer
  local pio_section = ''
  -- Safe lookups ensure it never crashes if your plugin isn't active in the folder
  if _G.metadata and _G.metadata.active_env and _G.metadata.active_env ~= '' then
    -- Format with a clean text block identifier: " [   esp32c3] "
    pio_section = '%#DiagnosticOk#    ' .. _G.metadata.active_env .. ' '
  end

  -- 4. Right side items (Filetype, Cursor position percentage)
  local filetype = '%#StatusLineNC# %Y '
  local position = '%#Normal# %l:%c %p%% ' -- Line:Column number followed by percentage down file

  -- 5. Synthesize all segments into one clean, seamless output row string
  return table.concat({
    mode,
    file_path,
    modified,
    alignment, -- Dynamic separator gap split point
    pio_section, -- Your custom PlatformIO board injection target
    filetype,
    position,
  })
end

-- 6. Activate the statusline by assigning our global function string wrapper
vim.opt.statusline = '%!v:lua.my_native_statusline()'
