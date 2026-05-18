--INFO: Install platformio
-- stylua: ignore start
------------------------------------------------------
local function pioCompileDB()

  local pio = require('nvimpio.pio.upkeep')
  local active_env = pio.get_active_env('PIO db: ')
  local cb = pio.handlePioDB
  local cmd = 'pio run -t compiledb -e ' .. active_env

  pio.run_sequence({ cmnds = { cmd }, cb = cb })
end

return {
  pioCompileDB = pioCompileDB,
}
