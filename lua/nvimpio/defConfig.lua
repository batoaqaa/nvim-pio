local defConfig = {
  pio = {
    pio_runtime_dir = vim.fs.joinpath(OS.defaultHome, '.platformio'),
    pio_storage_dir = vim.fs.joinpath(OS.defaultHome, '.platformio'),
  },
  clangd = {
    support = true,
    install = false,
  },
  menu_key = '<leader>\\', -- replace this menu key  to your convenience
  menu_name = 'PlatformIO', -- replace this menu name to your convenience

  menu_bindings = {
    { node = 'item', desc = '[B]lock diagnostic', shortcut = 'b', command = 'ClangdFilter' },
    { node = 'item', desc = '[C]li terminal', shortcut = 'c', command = 'Piocli' },
    { node = 'item', desc = 'Switch [E]nv', shortcut = 'e', command = 'PioPickEnv' },
    { node = 'item', desc = '[I]nitiate project', shortcut = 'i', command = 'Pioinit' },
    { node = 'item', desc = '[L]ist terminals', shortcut = 'l', command = 'PioTermList' },
    { node = 'item', desc = '[M]onitor terminal', shortcut = 'm', command = 'Piomon' },
    { node = 'item', desc = 're[S]art clangd', shortcut = 's', command = 'Clangdrestart' },
    {
      node = 'menu',
      desc = '[A]dvanced',
      shortcut = 'a',
      items = {
        { node = 'item', desc = '[T]est', shortcut = 't', command = 'Piocli test' },
        { node = 'item', desc = '[C]heck', shortcut = 'c', command = 'Piocli check' },
        { node = 'item', desc = '[D]ebug', shortcut = 'd', command = 'Piocli debug' },
        { node = 'item', desc = 'Compilation Data[b]ase', shortcut = 'b', command = 'PioCompileDB' },
        {
          node = 'menu',
          desc = '[V]erbose',
          shortcut = 'v',
          items = {
            { node = 'item', desc = 'Verbose [B]uild', shortcut = 'b', command = 'Piocli run -v' },
            { node = 'item', desc = 'Verbose [U]pload', shortcut = 'u', command = 'Piocli run -v -t upload' },
            { node = 'item', desc = 'Verbose [T]est', shortcut = 't', command = 'Piocli test -v' },
            { node = 'item', desc = 'Verbose [C]heck', shortcut = 'c', command = 'Piocli check -v' },
            { node = 'item', desc = 'Verbose [D]ebug', shortcut = 'd', command = 'Piocli debug -v' },
          },
        },
      },
    },
    {
      node = 'menu',
      desc = '[D]ependencies',
      shortcut = 'd',
      items = {
        { node = 'item', desc = '[L]ist packages', shortcut = 'l', command = 'Piocli pkg list' },
        { node = 'item', desc = '[O]utdated packages', shortcut = 'o', command = 'Piocli pkg outdated' },
        { node = 'item', desc = '[U]pdate packages', shortcut = 'u', command = 'Piocli pkg update' },
      },
    },
    {
      node = 'menu',
      desc = '[F]lash',
      shortcut = 'f',
      items = {
        { node = 'item', desc = '[B]uild file system', shortcut = 'b', command = 'Piocli run -t buildfs' },
        { node = 'item', desc = 'Program [S]ize', shortcut = 's', command = 'Piocli run -t size' },
        { node = 'item', desc = '[U]pload file system', shortcut = 'u', command = 'Piocli run -t uploadfs' },
        { node = 'item', desc = '[E]rase Flash', shortcut = 'e', command = 'Piocli run -t erase' },
      },
    },
    {
      node = 'menu',
      desc = '[G]eneral',
      shortcut = 'g',
      items = {
        { node = 'item', desc = '[B]uild', shortcut = 'b', command = 'Piocli run' },
        { node = 'item', desc = '[C]lean', shortcut = 'c', command = 'Piocli run -t clean' },
        { node = 'item', desc = '[D]evice list', shortcut = 'd', command = 'Piocli device list' },
        { node = 'item', desc = '[F]ull clean', shortcut = 'f', command = 'Piocli run -t fullclean' },
        { node = 'item', desc = '[P]arameters hardware setup', shortcut = 'p', command = 'PioSelectPort' },
        { node = 'item', desc = '[U]pload', shortcut = 'u', command = 'Piocli run -t upload' },
      },
    },
    {
      node = 'menu',
      desc = '[P]latformIO',
      shortcut = 'p',
      items = {
        { node = 'item', desc = '[U]pgrade PlatformIO Core', shortcut = 'u', command = 'Piocli upgrade' },
        { node = 'item', desc = '[I]nstall PlatformIO Core', shortcut = 'i', command = 'PioInstall' },
        { node = 'item', desc = '[G]it ignore', shortcut = 'g', command = 'PioGitIgnore' },
      },
    },
    {
      node = 'menu',
      desc = '[R]emote',
      shortcut = 'r',
      items = {
        { node = 'item', desc = 'Remote [U]pload', shortcut = 'u', command = 'Piocli remote run -t upload' },
        { node = 'item', desc = 'Remote [T]est', shortcut = 't', command = 'Piocli remote test' },
        { node = 'item', desc = 'Remote [M]onitor', shortcut = 'm', command = 'Piomon remote run -t monitor' },
        { node = 'item', desc = 'Remote [D]evices', shortcut = 'd', command = 'Piocli remote device list' },
      },
    },
  },
}

return defConfig
