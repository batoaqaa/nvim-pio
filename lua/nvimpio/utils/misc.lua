---@class platformio.utils.misc

local M = {}

M.is_windows = jit.os == 'Windows'
local uv = vim.uv or vim.loop

M.devNul = M.is_windows and ' 2>./nul' or ' 2>/dev/null'
-- M.extra = 'printf \'\\\\n\\\\033[0;33mPlease Press ENTER to continue \\\\033[0m\'; read'
-- M.extra = ' && echo . && echo . && echo Please Press ENTER to continue'

local pluginName = 'nvim-pio'

--INFO:
-- stylua: ignore
------------------------------------------------------
---@param msg string The message to display
---@param level string|integer|nil
function M.notify(msg, level)
  local icons = {
    [vim.log.levels.INFO] = '',
    [vim.log.levels.WARN] = '',
    [vim.log.levels.ERROR] = '',
    [vim.log.levels.DEBUG] = '',
  }

  -- Mapping string inputs to official levels
  local level_map = {
    info  = vim.log.levels.INFO,  -- 2
    warn  = vim.log.levels.WARN,  -- 3
    error = vim.log.levels.ERROR, -- 4
    debug = vim.log.levels.DEBUG, -- 1
  }

  -- 1. If 'level' is a string, convert it using our map
  -- 2. If it's already a number, use it
  -- 3. Default to INFO if nothing is provided
  if type(level) == 'string' then
    level = level_map[level:lower()] -- :lower() makes it case-insensitive
  end

  -- Log level (defaults to INFO)
  level = level or vim.log.levels.INFO
  local icon = icons[level] or '  '

  local full_message = string.format(" %s [%s] %s", pluginName, icon, msg)
  -- local message = '  '.. pluginName .. ' [' .. icon .. ']: ' .. msg
  vim.notify(full_message, level, {
    title = pluginName,
    icon = icon,
  })
end

--INFO:
------------------------------------------------------
function M.isReadable(path)
  local stat = vim.uv.fs_stat(path)

  -- Check if it exists and is a regular file
  local is_file = stat ~= nil and stat.type == 'file'

  -- Return both: the boolean check and the full metadata table
  return is_file, stat
end

--INFO:
------------------------------------------------------
function M.isDir(path)
  local stat = vim.uv.fs_stat(path)

  -- Returns true ONLY if the path exists AND is a directory
  local is_dir = stat ~= nil and stat.type == 'directory'

  return is_dir, stat
end

--INFO:
------------------------------------------------------
-- stylua: ignore
function M.showMessage(msg)
  local bufnr = vim.api.nvim_create_buf(false, true)
  local text = '  ' .. msg .. '  '
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { '', text, '' })

  local width, height = #text + 2, 3
  local row = math.floor((vim.o.lines - height) / 2)
  local col = math.floor((vim.o.columns - width) / 2)

  local win_id = vim.api.nvim_open_win(bufnr, false, {
    relative = 'editor',
    row = row,
    col = col,
    width = width,
    height = height,
    style = 'minimal',
    border = 'double',
    zindex = 250,
  })

  -- Define the "Glow" colors
  -- We use 'IncSearch' or 'CurSearch' for a bright, glowing look
  local hl_on = 'Normal:IncSearch,FloatBorder:IncSearch'
  local hl_off = 'Normal:NormalFloat,FloatBorder:NormalFloat'

  -- Create a timer for the blinking effect
  local blink_timer = uv.new_timer()
  local is_on = true

  if blink_timer then
    blink_timer:start(
      0,
      500,
      vim.schedule_wrap(function()
        if vim.api.nvim_win_is_valid(win_id) then
          vim.api.nvim_set_option_value('winhl', is_on and hl_on or hl_off, { scope = 'local', win = win_id })
          is_on = not is_on
        else
          blink_timer:stop()
          blink_timer:close()
        end
      end)
    )
  end

  -- Return both so you can kill them later
  return { win = win_id, timer = blink_timer }
end

--INFO:
-- stylua: ignore
------------------------------------------------------
function M.closeMessage(status_obj)
  if status_obj then
    if status_obj.timer then
      status_obj.timer:stop()
      status_obj.timer:close()
    end
    if status_obj.win and vim.api.nvim_win_is_valid(status_obj.win) then
      vim.api.nvim_win_close(status_obj.win, true)
    end
  end
end

--INFO:
-- stylua: ignore
------------------------------------------------------
function M.deleteFile(path)
  local file = vim.fn.fnamemodify(path, ':t')
  if vim.fn.filereadable(path) == 1 then
    local success = vim.fn.delete(path)

    if success == 0 then vim.misc.notify('PlatformIO: ' .. file .. ' file removed', 'info')
    else vim.misc.notify('PlatformIO: Failed to delete ' .. file, 'error') end
  else vim.misc.notify('PlatformIO: ' .. file .. ' file not found', 'warn') end
end

--INFO:
--  Version-Safe Path Joining (Fallback for Neovim < 0.10.0)
-- stylua: ignore
------------------------------------------------------
M.joinPath = vim.fs.joinpath or function(...)
  return table.concat({ ... }, '/'):gsub('//+', '/')
end

--INFO:
-- iterrative loop 48ms
-- stylua: ignore
------------------------------------------------------
function M.jsonFormat(root_data)
  local buffer = {}
  -- Stack stores: { val = item, lvl = depth, stage = "start"|"items", keys = {}, index = 0 }
  local stack = { { val = root_data, lvl = 0, stage = 'start' } }

  local function get_indent(lvl) return string.rep('  ', lvl) end

  -- Full JSON Escape Table
  local escapes = {
    ['\\'] = '\\\\',
    ['"']  = '\\"',
    ['\b'] = '\\b',
    ['\f'] = '\\f',
    ['\n'] = '\\n',
    ['\r'] = '\\r',
    ['\t'] = '\\t',
  }

  while #stack > 0 do
    local curr = stack[#stack]
    local val, lvl = curr.val, curr.lvl
    local indent = get_indent(lvl)

    if type(val) == 'table' then
      -- 1. Determine if Array or Object
      local is_array = false

      -- Check if it's explicitly marked as an array by the Neovim parser
      local mt = getmetatable(val)
      if mt and mt.__jsontype == 'array' then
        is_array = true
      -- If not marked, check if it has indexed items or is literally an empty table
      elseif #val > 0 or next(val) == nil then
        is_array = true
      end

      if curr.stage == 'start' then
        table.insert(buffer, (is_array and '[' or '{') .. '\n')
        curr.stage = 'items'
        curr.keys = {}

        -- 2. Collect and Sort Keys (CRITICAL for SHA256 stability)
        if is_array then for i = 1, #val do table.insert(curr.keys, i) end
        else
          for k in pairs(val) do table.insert(curr.keys, k) end
          table.sort(curr.keys, function(a, b) return tostring(a) < tostring(b) end)
        end
        curr.total = #curr.keys
        curr.cursor = 1 -- Point to the first key
      elseif curr.stage == 'items' then
        if curr.cursor <= curr.total then
          local key = curr.keys[curr.cursor]
          local item = val[key]

          -- Add comma for all but the first item
          if curr.cursor > 1 then table.insert(buffer, ',\n') end

          table.insert(buffer, get_indent(lvl + 1))
          if not is_array then table.insert(buffer, '"' .. tostring(key) .. '": ') end

          curr.cursor = curr.cursor + 1
          -- Push next item to process
          table.insert(stack, { val = item, lvl = lvl + 1, stage = 'start' })
        else
          -- 3. Close the block
          table.insert(buffer, '\n' .. indent .. (is_array and ']' or '}'))
          table.remove(stack)
        end
      end
    else
      -- 4. Primitives (String, Number, Bool, Nil)
      local output = ''
      if val == nil or val == vim.NIL then output = 'null'
      elseif val == vim.empty_dict then output = '{}'
      elseif type(val) == 'boolean' then output = tostring(val)
      elseif type(val) == 'string' then
        -- A. Handle standard escapes (\n, \t, etc.)
        local s = val:gsub('[\\"\b\f\n\r\t]', escapes)

        -- B. Handle unprintable control characters (U+0000 to U+001F)
        s = s:gsub('[%z\1-\31]', function(c)
          return string.format('\\u%04x', string.byte(c))
        end)

        -- C. Normalize Windows paths to Unix for cross-platform SHA256 stability
        -- We flip double-backslashes (\\) resulting from the escape to (/)
        s = s:gsub('\\\\', '/')

        output = '"' .. s .. '"'
      else output = tostring(val) end
      table.insert(buffer, output)
      table.remove(stack)
    end
  end
  return table.concat(buffer)
end

--INFO:
-- Example Usage
-- local content = readFile("compile_commands.json")
-- if content then local data = vim.json.decode(content) end
-- stylua: ignore
---@param path string
------------------------------------------------------
function M.readFile(path)
  -- 1. Check if file exists before opening to avoid "noisy" errors
  local stat = uv.fs_stat(path)
  if not stat then return false, 'File does not exist' end

  -- 2. Open the file
  local fd, err = uv.fs_open(path, 'r', 438)
  if not fd then return false, err end

  -- 3. Read the content (using stat.size from our check above)
  local content, read_err = uv.fs_read(fd, stat.size, 0)
  uv.fs_close(fd)

  if read_err then return false, read_err end

  return true, content
end

--INFO:
-- Example
-- local ok, err = writeFiile(path, json)
-- if ok then print("Write complete!") end
-- stylua: ignore
---@param path string
---@param data string
---@param opts table
------------------------------------------------------
function M.writeFile(path, data, opts)
  -- opts.overwrite: boolean (default true)
  -- opts.mkdir: boolean (default true)
  opts = opts or { overwrite = true, mkdir = true }

  local stat = uv.fs_stat(path)
  -- 1. Overwrite protection
  if opts.overwrite == false and stat then
    return false, 'writeFile: File already exists'
  end

  -- 2. Recursive directory creation
  if opts.mkdir ~= false then
    local parent = vim.fn.fnamemodify(path, ':h')
    if not stat or stat.type ~= 'directory' then
      vim.fn.mkdir(parent, 'p', '0700')
    end
  end

  --[[
      Octal	Decimal	Permission
      0700	  448	    Owner only (Full)
      0755	  493	    Owner (Full), Others (Read/Execute)
      0666	  438	    Everyone (Read/Write) - Not recommended for folders
     'w' truncates existing, 'wx' fails if exists (extra safety)
  ]]
  -- 3. Open for writing ('w' flag truncates automatically)
  local fd, err = uv.fs_open(path, 'w', 438)
  if not fd then return false, 'writeFile: Open error: ' .. (err or 'unknown') end

  -- 4. Robust Write Loop
  -- Loop ensures all data is written even if it takes multiple chunks
  local offset = 0
  while offset < #data do
    local bytes_written, w_err = uv.fs_write(fd, data:sub(offset + 1), offset)
    if w_err then
      uv.fs_close(fd)
      return false, 'writeFile: Write error: ' .. w_err
    end
    offset = offset + bytes_written
  end

  -- 5. Force Sync (Crucial for your project.checksum watcher)
  uv.fs_fsync(fd)
  uv.fs_close(fd)

  return true, 'Success'
end

------------------------------------------------------
--[[ 
Targets Windows paths, normalizes slashes, and fixes smashed PlatformIO paths.
Cleans and repairs compiler flags in a command string.
{ "-I", "-L", "-isystem", "-T", "-include" }
1. Library Paths
    -L: Specifies directories to search for library files (.a, .lib, .so).
        Example: -L"C:\Users\lib"
        -L"C:/Users/lib"
    -l (lowercase L): While usually just a name (like -lmath), it can sometimes be a direct path to a specific file.
2. Header Inclusion (Advanced)
    -isystem: Similar to -I, but treats the directory as a "system" header (suppresses warnings). PlatformIO uses this heavily for framework headers (Arduino/ESP-IDF).
    -include: Forces the compiler to include a specific file before anything else.
        Example: -include "C:\project\config.h"
    -iquote: Directories for headers wrapped in double quotes "".
3. Output and Debugging
    -o: The output path for the compiled object file or binary.
    -fdebug-prefix-map=: Used to make builds reproducible by mapping absolute paths to relative ones in the debug symbols.
4. Linker and Frameworks
    -T: Path to a linker script (very common in embedded/PlatformIO for memory mapping).
        Example: -T"C:\project\ld\esp32.ld"
    -F: (macOS/iOS) Path to search for frameworks.
]]
-- stylua: ignore
--- @param flags string: The raw command string (e.g., from compile_commands.json)
--- @return string: The cleaned command string
--INFO:
------------------------------------------------------
function M.normalizeFlags(flags)
  if not flags or flags == '' then
    return ''
  end

  --1. Identify flags that look like paths.
  -- Pattern explanation:
  --   %-      : Matches a literal hyphen (the start of a flag)
  --   %S*     : Matches zero or more non-space characters
  --   \\      : Matches a literal backslash (identifies it as a Windows path)
  --   %S*     : Matches the rest of the non-space characters in that flag
  local cleaned_cmd = flags:gsub('(%-%S-\\S*)', function(flag)
    --2. Normalize Slashes
    -- Replaces any number of backslashes (single \ or JSON-escaped \\) with one forward slash.
    -- Forward slashes are safer and more portable for compilers like GCC/Clang.
    flag = flag:gsub('[\\]+', '/')

    --3. Heal PlatformIO "Smashed" Paths
    -- Fixes the bug where PlatformIO expansions repeat the user home directory.
    -- Example: /Users/name/.platformiopackages/toolchain -> /.platformio/packages/toolchain
    flag = flag:gsub('/Users/[^/]+%.platformio/packages', '/.platformio/packages')

    return flag
  end)

  -- Return only the result string (discarding the replacement count)
  return cleaned_cmd
end

--INFO:
------------------------------------------------------
function M.normalizePath(path)
  -- return path:gsub('[\\]+', '/'):gsub('[//]+', '/')
  return path:gsub('[\\/]+', '/')
end

--INFO:
------------------------------------------------------
function M.strsplit(inputstr, del)
  local t = {}
  if type(inputstr) == 'string' and inputstr and inputstr ~= '' then
    for str in string.gmatch(inputstr, '([^' .. del .. ']+)') do
      table.insert(t, str)
    end
  end
  return t
end

--INFO:
------------------------------------------------------
function M.check_prefix(str, prefix)
  return str:sub(1, #prefix) == prefix
end

--INFO:
------------------------------------------------------
local function pathmul(n)
  return '..' .. string.rep('/..', n)
end

local paths = { '.', '..', pathmul(1), pathmul(2), pathmul(3), pathmul(4), pathmul(5) }

--INFO:
------------------------------------------------------
function M.file_exists(name)
  local f = io.open(name, 'r')
  if f ~= nil then
    io.close(f)
    return true
  else
    return false
  end
end

--INFO:
------------------------------------------------------
function M.set_platformioRootDir()
  if vim.g.platformioRootDir ~= nil then
    return
  end
  for _, path in pairs(paths) do
    if M.file_exists(path .. '/platformio.ini') then
      vim.g.platformioRootDir = path
      return
    end
  end
  vim.misc.notify('Could not find platformio.ini, run :Pioinit to create a new project', 'error')
end

--INFO:
------------------------------------------------------
function M.cd_pioini()
  -- M.set_platformioRootDir()
  vim.cmd('cd ' .. vim.g.platformioRootDir)
end

--INFO:
------------------------------------------------------
function M.pio_install_check()
  local handle = (jit.os == 'Windows') and assert(io.popen('where.exe pio 2>./nul')) or assert(io.popen('which pio 2>/dev/null'))
  local pio_path = assert(handle:read('*a'))
  handle:close()

  if #pio_path == 0 then
    vim.misc.notify('Platformio not found in the path', 'error')
    return false
  end
  return true
end

--INFO:
------------------------------------------------------
function M.async_shell_cmd(cmd, callback)
  local output = {}

  vim.fn.jobstart(cmd, {
    stdout_buffered = true,
    stderr_buffered = false,

    on_stdout = function(_, data)
      if data then
        for _, line in ipairs(data) do
          if line ~= '' then
            table.insert(output, line)
          end
        end
      end
    end,

    on_exit = function(_, code)
      callback(output, code)
    end,
  })
end

--INFO:
------------------------------------------------------
function M.shell_cmd_blocking(command)
  local handle = io.popen(command, 'r')
  if not handle then
    return nil, 'failed to run command'
  end

  local result = handle:read('*a')
  handle:close()

  return result
end

--INFO:
------------------------------------------------------
function M.gitignore_lsp_configs(config_file)
  local gitignore_path = vim.fs.joinpath(vim.g.platformioRootDir, '.gitignore')
  local file = io.open(gitignore_path, 'r')
  local pattern = '^%s*' .. vim.pesc(config_file) .. '%s*$'

  if file then
    for line in file:lines() do
      if line:match(pattern) then
        file:close()
        return
      end
    end
    file:close()
  end

  file = io.open(gitignore_path, 'a')
  if file then
    file:write(config_file .. '\n')
    file:close()
  end
end

return M
