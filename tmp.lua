function M.get_active__env(from)
  local msg = (type(from) == 'string' and from ~= '') and from or 'PIO: '

  -- 1. Find the path using modern cross-platform Neovim API
  local files = vim.fs.find('platformio.ini', {
    path = vim.api.nvim_buf_get_name(0):match('(.*[/\\])') or vim.uv.cwd(),
    upward = true,
    stop = OS.home,
  })

  local path = files[1]
  if not path then
    OS.notify(msg .. 'platformio.ini not found.', 'error')
    return nil
  end

  -- 2. Read the configuration file safely
  local ok, content = misc.readFile(path)
  if not ok or not content then
    OS.notify(msg .. 'Could not read platformio.ini at ' .. path, 'warn')
    return nil
  end

  local default_envs_raw = ''
  local first_env = nil
  local valid_envs = {}
  local in_platformio_block = false

  -- 3. Parse lines and isolate environment configurations
  for line in vim.gsplit(content, '[\r\n]+') do
    -- Trim whitespace
    line = line:gsub('^%s+', ''):gsub('%s+$', '')

    -- Match section headers [section]
    local section = line:match('^%[(.+)%]$')
    if section then
      in_platformio_block = (section == 'platformio')

      -- Only match specific env configurations (e.g., [env:myboard]), ignore plain [env]
      local env_name = section:match('^env:(.+)')
      if env_name then
        if not first_env then
          first_env = env_name
        end
        valid_envs[env_name] = true
      end
    end

    -- Extract default environments if inside the [platformio] block
    if in_platformio_block then
      local def = line:match('^default_envs%s*=%s*(.*)')
      if def then
        default_envs_raw = def
      end
    end
  end

  -- 4. Return the valid default environment if it explicitly exists
  if default_envs_raw ~= '' then
    for env_name in default_envs_raw:gmatch('([^%s,]+)') do
      if valid_envs[env_name] then
        return env_name
      end
    end
  end

  -- 5. Final fallback to the first discovered target block
  return first_env
end
