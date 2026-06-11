--INFO: Install platformio
-- stylua: ignore start
------------------------------------------------------
local function pioCompileDB()

  local meta = require('nvimpio.pio.metadata')
  -- local pio = require('nvimpio.pio.upkeep')
  local parser = require('nvimpio.device.parser')
  -- local active_env = pio.get_active_env('PIO db: ')
  local active_env, _ = meta.get_active_env('PIO db: ')

  local cb = function(status)
    parser.handlePioDB(status, active_env, function(success)
      if success then do end end
    end)
  end
  -- local cb = pio.handlePioDB
  local cmd1 = 'ls'
  local cmd = 'pio run -t compiledb -e ' .. active_env

  parser.run_sequence({ cmnds = { cmd1, cmd }, cb = cb , from = 'PioCompileDB:'})
end

return {
  pioCompileDB = pioCompileDB,
}
