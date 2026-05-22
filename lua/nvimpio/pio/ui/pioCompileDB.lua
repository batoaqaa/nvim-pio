--INFO: Install platformio
-- stylua: ignore start
------------------------------------------------------
local function pioCompileDB()

  local meta = require('nvimpio.pio.metadata')
  local pio = require('nvimpio.pio.upkeep')
  -- local active_env = pio.get_active_env('PIO db: ')
  local active_env, _ = meta.get_active_env('PIO db: ')
  local cb = pio.handlePioDB
  local cmd = 'pio run -t compiledb -e ' .. active_env

  pio.run_sequence({ cmnds = { cmd }, cb = cb , from = 'PioCompileDB:'})
end

return {
  pioCompileDB = pioCompileDB,
}
