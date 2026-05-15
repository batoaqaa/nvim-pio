local defConfig = {
  pio = {
    pio_runtime_dir = OS.platformio_dir,
    pio_storage_dir = OS.platformio_dir,
  },
  clangd = {
    support = false,
    install = false,
  },
  menu_key = '<leader>\\', -- replace this menu key  to your convenience
  menu_name = 'PlatformIO', -- replace this menu name to your convenience
  debug = false,

  menu_bindings = {
    { node = 'item', desc = '[I]nitiate project', shortcut = 'i', command = 'Pioinit' },
    { node = 'item', desc = '[L]ist terminals', shortcut = 'l', command = 'PioTermList' },
    { node = 'item', desc = 're[S]art clangd', shortcut = 's', command = 'Pioclangdrestart' },
    { node = 'item', desc = '[T]erminal Core CLI', shortcut = 't', command = 'Piocmdf' },
    {
      node = 'menu',
      desc = '[A]dvanced',
      shortcut = 'a',
      items = {
        { node = 'item', desc = '[T]est', shortcut = 't', command = 'Piocmdf test' },
        { node = 'item', desc = '[C]heck', shortcut = 'c', command = 'Piocmdf check' },
        { node = 'item', desc = '[D]ebug', shortcut = 'd', command = 'Piocmdf debug' },
        { node = 'item', desc = 'Compilation Data[b]ase', shortcut = 'b', command = 'PioCompileDB' },
        {
          node = 'menu',
          desc = '[V]erbose',
          shortcut = 'v',
          items = {
            { node = 'item', desc = 'Verbose [B]uild', shortcut = 'b', command = 'Piocmdf run -v' },
            { node = 'item', desc = 'Verbose [U]pload', shortcut = 'u', command = 'Piocmdf run -v -t upload' },
            { node = 'item', desc = 'Verbose [T]est', shortcut = 't', command = 'Piocmdf test -v' },
            { node = 'item', desc = 'Verbose [C]heck', shortcut = 'c', command = 'Piocmdf check -v' },
            { node = 'item', desc = 'Verbose [D]ebug', shortcut = 'd', command = 'Piocmdf debug -v' },
          },
        },
      },
    },
    {
      node = 'menu',
      desc = '[D]ependencies',
      shortcut = 'd',
      items = {
        { node = 'item', desc = '[L]ist packages', shortcut = 'l', command = 'Piocmdf pkg list' },
        { node = 'item', desc = '[O]utdated packages', shortcut = 'o', command = 'Piocmdf pkg outdated' },
        { node = 'item', desc = '[U]pdate packages', shortcut = 'u', command = 'Piocmdf pkg update' },
      },
    },
    {
      node = 'menu',
      desc = '[F]lash',
      shortcut = 'f',
      items = {
        { node = 'item', desc = '[B]uild file system', shortcut = 'b', command = 'Piocmdf run -t buildfs' },
        { node = 'item', desc = 'Program [S]ize', shortcut = 's', command = 'Piocmdf run -t size' },
        { node = 'item', desc = '[U]pload file system', shortcut = 'u', command = 'Piocmdf run -t uploadfs' },
        { node = 'item', desc = '[E]rase Flash', shortcut = 'e', command = 'Piocmdf run -t erase' },
      },
    },
    {
      node = 'menu',
      desc = '[G]eneral',
      shortcut = 'g',
      items = {
        { node = 'item', desc = '[B]uild', shortcut = 'b', command = 'Piocmdf run' },
        { node = 'item', desc = '[C]lean', shortcut = 'c', command = 'Piocmdf run -t clean' },
        { node = 'item', desc = '[D]evice list', shortcut = 'd', command = 'Piocmdf device list' },
        { node = 'item', desc = '[F]ull clean', shortcut = 'f', command = 'Piocmdf run -t fullclean' },
        { node = 'item', desc = '[M]onitor', shortcut = 'm', command = 'Piocmdh run -t monitor' },
        { node = 'item', desc = '[U]pload', shortcut = 'u', command = 'Piocmdf run -t upload' },
      },
    },
    {
      node = 'menu',
      desc = '[P]latformIO',
      shortcut = 'p',
      items = {
        { node = 'item', desc = '[U]pgrade PlatformIO Core', shortcut = 'u', command = 'Piocmdf upgrade' },
        { node = 'item', desc = '[I]nstall PlatformIO Core', shortcut = 'i', command = 'PioInstall' },
        { node = 'item', desc = '[G]it ignore', shortcut = 'g', command = 'PioGitIgnore' },
      },
    },
    {
      node = 'menu',
      desc = '[R]emote',
      shortcut = 'r',
      items = {
        { node = 'item', desc = 'Remote [U]pload', shortcut = 'u', command = 'Piocmdf remote run -t upload' },
        { node = 'item', desc = 'Remote [T]est', shortcut = 't', command = 'Piocmdf remote test' },
        { node = 'item', desc = 'Remote [M]onitor', shortcut = 'm', command = 'Piocmdh remote run -t monitor' },
        { node = 'item', desc = 'Remote [D]evices', shortcut = 'd', command = 'Piocmdf remote device list' },
      },
    },
  },
}

return defConfig
