local M = {}

local is_win = vim.fn.has('win32') == 1
local home = os.getenv('HOME') or os.getenv('USERPROFILE')

local core_dir = os.getenv('PLATFORMIO_CORE_DIR')
-- stylua: ignore
if not core_dir then core_dir = vim.fs.joinpath(home, '.platformio') end


--INFO: get PIO binary folder
-- stylua: ignore
------------------------------------------------------
function M.get_pio_bin_dir()
  -- 3. Use 'Scripts' for Windows and 'bin' for Unix-like systems
  local bin_subfolder = is_win and 'penv/Scripts' or 'penv/bin'

  -- Normalize the path to handle mix of '/' and '\' on Windows
  local full_path = vim.fs.joinpath(core_dir, bin_subfolder)
  return full_path
end

--INFO: Verify PIO version
-- stylua: ignore
------------------------------------------------------
function M.verify_version()
  vim.system({ 'pio', '--version' }, { text = true }, function(obj)
    vim.schedule(function()
      if obj.code == 0 then print('PlatformIO Version: ' .. vim.trim(obj.stdout))
      else print('❌ PlatformIO execution error: ' .. (obj.stderr or 'Unknown error')) end
    end)
  end)
end

return M
