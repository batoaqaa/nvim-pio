function M.extract_removals_from_idedata(idedata, project_root)
  if _G.metadata and type(_G.metadata.cxx_flags) == 'table' then
    local boiler = require('nvimpio.boilerplate')
    local pio_diag = require('nvimpio.clangd.diagnostic')

    local flags_updated = false

    -- Loop through every compiler flag supplied by idedata.json
    for _, flag in ipairs(_G.metadata.cxx_flags) do
      if type(flag) == 'string' then
        -- Rule A: It's an architecture machine directive flag (e.g., -mlongcalls)
        local is_machine_directive = flag:match('^%-m[%w%-]+')

        -- Rule B: It's a heavy compiler loop/optimization tweak (e.g., -fno-tree-switch-conversion)
        local is_problematic_opt = flag:match('^%-fno%-tree%-') or flag:match('^%-fno%-jump%-')

        if (is_machine_directive or is_problematic_opt) and not pio_diag.removed_flags[flag] then
          -- Permanently register the flag inside your plugin's dynamic databases
          pio_diag.removed_flags[flag] = true
          flags_updated = true
        end
      end
    end

    -- Trigger your boilerplate writer to output the updated .clangd file to disk instantly
    if flags_updated and boiler.boilerplate_gen then
      pcall(boiler.boilerplate_gen, '.clangd', project_root)

      -- Save the newly tracked flags down to your .filter.json file
      local filter_db_path = vim.fs.joinpath(project_root, '.filter.json')
      local f = io.open(filter_db_path, 'wb')
      if f then
        local payload = { codes = pio_diag.manual_blocked_codes, flags = pio_diag.removed_flags }
        f:write(require('nvimpio.utils.misc').jsonFormat(payload))
        f:close()
      end
    end
  end
end
