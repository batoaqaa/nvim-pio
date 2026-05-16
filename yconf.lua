return {
  'username/platformio-wizard.nvim',
  -- Load immediately on startup block phase [1]. Your new lightweight init.lua
  -- consumes less than 1 millisecond of boot lag, registering commands flawlessly.
  lazy = false,
  opts = {
    -- The user can pass any configuration parameters they like here
    pio = {
      pio_runtime_dir = '/opt/custom_pio',
    },
    menu_name = 'Embedded Studio',
  },
  config = function(_, opts)
    -- Locks user variables down globally instantly into 'M.options' inside init.lua
    require('platformio').setup(opts)
  end,
}
