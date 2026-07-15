  -- stylua: ignore start
local misc = require('nvimpio.utils.misc')
local projectDir = OS.project_dir

local M = {}

local boilerplate = {}

-- INFO: platformio.ini
----------------------------------------------------------------------------------------
-- core_dir = %s
boilerplate['platformio.ini'] = {
  rewrite = false,
  read = false,
  plate = [[
[platformio]
platforms_dir = ${platformio.core_dir}/platforms
packages_dir = ${platformio.core_dir}/packages
;libdeps_dir = ./external_libs

;default_envs = uno, nodemcu

;--------------------------------------------------------------------------
[env]
upload_speed = 115200
monitor_speed = 9600

monitor_rts = 1   ; 1 combination to reset esp32c6 (Table 32.3-2. CDC-ACM Settings with RTS and DTR)
monitor_dtr = 0   ; 0 // pio dev mon --rts=0 --dtr=0 then pio dev mon --rts=1 dtr=0

]],
  boiler = function(self)
    local full_path = vim.fs.joinpath(projectDir, 'platformio.ini')
    if vim.uv.fs_stat(full_path) then return false end
    -- local core_dir = require('nvimpio').config.pio_storage_dir

    misc.writeFile(full_path, self.plate, {})
    -- misc.writeFile(full_path, string.format(self.plate, core_dir), {})
    return true
  end,
}

  -- "cmd_env": {
  --   "CLANGD_TRACE": ""
  -- },
-- "--background-index-priority=low",
    -- "--limit-results=100",
-- INFO: .clangd_config
----------------------------------------------------------------------------------------
boilerplate['.clangdConfig.json'] = {
  rewrite = false,
  read = true,
  plate = [[
{
  "cmd": [
    "clangd",
    "--enable-config",
    "--background-index",
    "-j=4",
    "--pch-storage=memory",
    "--clang-tidy",
    "--all-scopes-completion",
    "--completion-parse=always",
    "--completion-style=detailed",
    "--header-insertion=iwyu",
    "--fallback-style={BasedOnStyle: llvm, SortIncludes: false}", 
    "--log=error",
    "--pretty",
    "--ranking-model=decision_forest",
    "--parse-forwarding-functions", 
    "--compile-commands-dir=%s",
    "--query-driver=%s"
  ],
  "filetypes": [
    "c",
    "cpp",
    "objc",
    "objcpp",
    "cuda"
  ],
  "root_markers": [
    ".clangd",
    ".clang-tidy",
    ".clang-format",
    "compile_commands.json",
    "platformio.ini",
    "compile_flags.txt",
    "configure.ac",
    ".git"
  ],
  "init_options": {
    "clangdFileStatus": true,
    "completeUnimported": true,
    "fallbackFlags": [
    ],
    "usePlaceholders": true
  },
  "single_file_support": true,
  "workspace_required": false
}
]],
    -- "compilationDatabasePath": %q,
  boiler = function(self)
    local file_path = vim.fs.joinpath(OS.clangd_config)
    if vim.uv.fs_stat(file_path) then
      if not self.rewrite then
        if self.read then
          local ok, content = misc.readFile(file_path)
          if ok then return content end
        end
        return self.plate
      end
    end
    misc.writeFile(file_path, self.plate, {})
    return self.plate
  end,
}

-- INFO: .clangd
----------------------------------------------------------------------------------------
-- DIALECT DISCOVERY (<0.1ms Structural Verification)
local function is_cpp_project()
  -- A. Check explicit framework metadata states first
  if _G.metadata and _G.metadata.envs then
    local fw = _G.metadata.envs[_G.metadata.active_env].framework:lower()
    if fw:find("arduino", 1, true) or fw:find("mbed", 1, true) then return true end
  end

  local db_path = OS.project_dir .. "/compile_commands.json"
  local f = io.open(db_path, "r")
  if not f then return false end

  local is_cpp = false
  local line_count = 0

  -- Normalize your workspace project root path to match compiler formatting styles
  -- (Converts backslashes to forward slashes or matches casing safely)
  local local_root = OS.project_dir:gsub("\\", "/"):lower()

  -- B. Streams lines sequentially. It drops out the moment a match resolves, 
  -- maximizing speed while preventing huge memory allocations.
  for line in f:lines() do
    line_count = line_count + 1

    -- Safety throttle boundary check: If we read 300 lines and find zero real C++ entries,
    -- this is green-lit as a pure C workspace. Break out to maintain 0ms lag!
    if line_count > 300 then break end

    -- Check if the line maps to an explicit compilation file path property key
    if line:find('"file"') then
      local normalized_line = line:gsub("\\", "/"):lower()

      -- CORE: Only evaluate if the file path is inside your local project root.
      -- This filters out global paths like C:/Users/.../.platformio/packages/...
      if normalized_line:find(local_root, 1, true) then
        -- THE PLATFORMIO DUMMY MASK: Explicitly ignore synthetic compiler primer targets
        if not (normalized_line:find("__dummy") or normalized_line:find("_bare_module")) then
          if normalized_line:find("%.cpp") or normalized_line:find("%.hpp") or normalized_line:find("%.cc") or normalized_line:find("%.cxx") then
            is_cpp = true
            break
          end
        end
      end
    end
  end
  f:close()
  return is_cpp
end

function M.readContent(tbl)
  tbl.start_marker = "# --- AUTOMATICALLY GENERATED BY NVIM-PIO - DO NOT EDIT START: " .. tbl.cache_id .. " ---"
  tbl.end_marker   = "# --- AUTOMATICALLY GENERATED BY NVIM-PIO - DO NOT EDIT END: " .. tbl.cache_id .. " ---"
  local  ok, content = misc.readFile(tbl.file)
  if not ok or not content then content = ''  end
  -- 1. Use pure plain-text indices (100% immune to pattern over-matching bugs!)
  local start_idx = content:find(tbl.start_marker, 1, true)
  local end_idx = content:find(tbl.end_marker, 1, true)

  -- 2. If this specific project session block exists, slice it out cleanly by indices
  if start_idx and end_idx then
    local actual_end = end_idx + #tbl.end_marker
    -- Consume any trailing newline characters following the end marker safely
    -- If it encounters Windows CRLF (\r\n), skip both characters cleanly.
    if content:sub(actual_end, actual_end + 1) == "\r\n" then actual_end = actual_end + 2
    -- If it encounters Linux/macOS LF (\n), skip the single character.
    elseif content:sub(actual_end, actual_end) == "\n" then actual_end = actual_end + 1 end

    local before = start_idx > 1 and content:sub(1, start_idx - 1) or ""
    local after = content:sub(actual_end)

    content = before .. tbl:block() .. after
  else content = content .. (content ~= "" and not content:match("\n$") and "\n" or "") .. tbl:block() end
  return content
end

-- Compiler: "%s"
-- CompilationDatabase: "%s"
boilerplate['.clangd'] = {
  Global = [[
%s
---
If:
  PathMatch: ['%s/.*[.]h$']
CompileFlags:
  BuiltinHeaders: QueryDriver
  Add: [%s]
---
If:
  PathMatch: ['%s/.*%s$']
CompileFlags:
  BuiltinHeaders: QueryDriver
  Remove: [%s]
  Add: [%s]
%s
]],

  Project = [[
%s
---
If:
  PathMatch: ['%s/.*']
CompileFlags:
  BuiltinHeaders: QueryDriver
  Remove: [%s]
  Add: [%s]
%s
]],
  boiler = function(self, project_root_param)
    local project_root = project_root_param or OS.project_dir or vim.uv.cwd() or '.'
    project_root = vim.fs.normalize(project_root)

    -- local core = require('nvimpio')
    if vim.fn.isdirectory(OS.clangd_user_dir) == 0 then
      vim.fn.mkdir(OS.clangd_user_dir, "p")
    end

    ------------------------------------------------------------------------------
    -- A: Force-create an empty default database if missing
    local filter_db_file = vim.fs.joinpath(OS.nvimpio_env_dir,OS.clangd_filter)
    local db_exist = vim.uv.fs_stat(filter_db_file)
    if not db_exist then
      local default_db = { codes = {}, flags = {} }
      local f_init = io.open(filter_db_file, 'wb')
      if f_init then
        f_init:write(misc.jsonFormat and misc.jsonFormat(default_db) or '{\n  "codes": {},\n  "flags": {}\n}')
        f_init:close()
      end
    end
    ------------------------------------------------------------------------------

    ------------------------------------------------------------------------------
    ------------------ start .clangd remove section ------------------------------
    -- 1. SYNC (WITH DIRECT DISK FALLBACK GATING):
    -- local formattedProjRemove = {}

    -- local formattedProjRemove = {'"-x"', '"-std=*"'}
    local formattedProjRemove = {'"-xc"', '"-xc++"', '"-std=*"'}
    -- add diagnostic removed flags
    local success, pio_diag = pcall(require, 'nvimpio.clangd.diagnostic')
    if success and pio_diag and pio_diag.removed_flags and next(pio_diag.removed_flags) then
      for flag, isblocked in pairs(pio_diag.removed_flags) do
        if isblocked then
          table.insert(formattedProjRemove, string.format('%q', flag))
        end
      end
    else
      local f = io.open(filter_db_file, 'r')
      if f then
        local raw = f:read('*a')
        f:close()
        if raw and raw ~= '' then
          local dok, data = pcall(vim.json.decode, raw)
          if dok and data and type(data.flags) == 'table' then
            for flag, isblocked in pairs(data.flags) do
              if isblocked then
                table.insert(formattedProjRemove, string.format('%q', flag))
              end
            end
          end
        end
      end
    end

    -- local formattedGlobRemove = {
    --   '"-x"',
    --   '"-std=*"',
    --   '"-D_ASMLANGUAGE"',
    --   '"-D__ASSEMBLY__"',
    --   '"-D__ASSEMBLER__"',
    --   '"-D_ASSEMBLY_"'
    -- }
    local formattedGlobRemove = {'"-xc"', '"-xc++"', '"-std=*"'}
    -- vim.list_extend(formattedProjRemove, formattedGlobRemove)
    --------------------- end .clangd remove section -----------------------------

    ------------------------------------------------------------------------------
    -- 2. METADATA EXTRACTOR
    local target_meta = nil

    if _G.metadata then
      -- Target A: Check if properties sit directly on the flat root table
      if _G.metadata.includes_build or _G.metadata.cxx_defines then
        target_meta = _G.metadata
      else
        -- Target B: Dynamic deep scan loop. Extract data from the first active nested sub-table env block
        for _, sub_table in pairs(_G.metadata) do
          if type(sub_table) == 'table' and (sub_table.includes_build or sub_table.cxx_defines) then
            target_meta = sub_table
            break
          end
        end
      end
    end

    ------------------------------------------------------------------------------
    ------------------ start .clangd IncAdd section  -----------------------------

    -- Extract all pre-sorted include path using JIT sequential loops
    local formattedIncAdd = {}  -- libdep_includes
    local include_pools = {
      target_meta and target_meta.includes_libdeps or {},
      -- target_meta and target_meta.includes_build or {},
      -- target_meta and target_meta.includes_toolchain or {},
      -- target_meta.includes_compatlib,
    }
    for pool_idx = 1, #include_pools do
      local pool = include_pools[pool_idx]
      for flag_idx = 1, #(pool or {}) do
        local raw_flag = pool[flag_idx]
        if type(raw_flag) == 'string' and raw_flag ~= '' then
          table.insert(formattedIncAdd, string.format('%q', vim.fs.normalize(raw_flag)))
          -- table.insert(formattedIncAdd, vim.fs.normalize(raw_flag))
        end
      end
    end
    --------------------- end .clangd IncAdd section -----------------------------


    -- ------------------------------------------------------------------------------
    -- ------------------ start .clangd formattedCxxAdd section  --------------------
    -- -- local formattedCxxAdd = { }
    -- local formattedCxxAdd = { '"-xc++"', '"-std=gnu++17"'}
    -- vim.list_extend(formattedCxxAdd, formattedIncAdd)
    -- --------------------- end .clangd formattedCxxAdd section --------------------
    --
    -- ------------------------------------------------------------------------------
    -- ------------------ start .clangd formattedCcAdd section  ---------------------
    -- -- local formattedCcAdd = { }
    -- local formattedCcAdd = { '"-xc"', '"-std=gnu17"' }
    -- vim.list_extend(formattedCcAdd, formattedIncAdd)
    -- --------------------- end .clangd formattedCcAdd section ---------------------

    ----------------------------------------------------------------------------------
    -- Create a fast lookup set of all valid extensions
    local extensions = {
        cc = true,
        cxx = true,
        ccm = true,
        C = true,
        ixx = true,
        cppm = true,
        mxx = true,
        i = true,
        ii = true,
        m = true,
        mm = true,
        cuh = true,
        cpp = true,
        c = true,
        cu = true,
        inl = true,
        tcc = true,
    }
    local getMainfile = function ()
      return vim.fs.find(function(name)
          -- Extract the text after the very last dot
          local ext = name:match("%.([^.]+)$")
          -- Return true if the extension exists in our target lookup set
          return extensions[ext] == true
      end, { limit = 1, path = OS.project_dir .. "/src" })[1]
    end
    local check_file = getMainfile()
    ----------------------------------------------------------------------------------

    local is_cpp = is_cpp_project()
    ------------------------------------------------------------------------------
    local formattedProjAdd = is_cpp and {
                                    '"-xc++"', '"-std=gnu++17"'
                                  } or {
                                    '"-xc"', '"-std=gnu17"'
                                  }
    vim.list_extend(formattedProjAdd, formattedIncAdd)
    ------------------------------------------------------------------------------
    local formattedGlobAdd = is_cpp and {
                                    -- '"-x"', '"c++-header"', '"-std=gnu++17"',
                                    '"-xc++"', '"-std=gnu++17"',
                                    -- string.format('"--include=%s"', check_file)
                                  } or {
                                    -- '"-x"', '"c-header"', '"-std=gnu17"',
                                    '"-xc"', '"-std=gnu17"',
                                    -- string.format('"--include=%s"', check_file)
                                  }
    ------------------------------------------------------------------------------

    ------------------------------------------------------------------------------
    ------------------ start .clangd formattedHAdd section  ----------------------
    -- local cpp_extensions = is_cpp and "hpp|cpp|cc|cu|cxx|h" or "hpp|cpp|cc|cxx"
    -- local c_extensions   = is_cpp and "c" or "c|h"
    -- local formattedHAdd = is_cpp and { '"-xc++-header"', '"-std=gnu++17"' } or { '"-xc-header"', '"-std=gnu17"' }
    local formattedHAdd = is_cpp and { '"-xc++-header"' } or { '"-xc-header"' }
    -- vim.list_extend(formattedHAdd, formatteLibdepsAdd)
    -- vim.list_extend(formattedHAdd, formattedIncAdd)

    -- table.insert(formattedHAdd, string.format('"--include=%s/src/mainx.c"', OS.project_dir))
    -- table.insert(formattedHAdd, string.format('"-I%s/src"', OS.project_dir))
    --------------------- end .clangd formattedHAdd section ----------------------

    local function preparePathMatch(raw_path)
      -- 1. Clean up slashes using Neovim's normalizer
      local path = vim.fs.normalize(raw_path)
      -- 2. Strip any trailing slash if it exists, so it fits your "%s/.*" template perfectly
      path = path:gsub("/$", "")
      -- 3. Extract the Windows drive letter if it exists
      local drive, main_path = path:match("^(%a:)(.*)$")
      if drive then
        drive = '[' .. drive:lower() .. drive:upper() .. ']'
        path = main_path
      else drive = "" end -- Linux/macOS
      -- 4. Escape every literal dot inside the folders completely dynamically
      -- path = path:gsub("%.%w+", [[\%0]])  -- this only for passing string.format()
      -- path = path:gsub("%.", ".")  -- this only for passing string.format()
      -- path = path:gsub("/", "[/\\]")  -- this only for passing string.format()
      local finalPath = drive .. path
      -- finalPath = finalPath:gsub("%.", "."):gsub("/", ".")
      finalPath = finalPath:gsub("%.", "[.]")
      -- if finalPath:sub(1, 1) == "." then
      --   finalPath = finalPath:sub(2)
      -- end
      -- path = path:gsub("(%%.)", "\\\\%%1") -- this for everything else
      -- 5. Recombine them seamlessly without a trailing slash
      return finalPath
    end

    -- Simply wrap your dynamic variables before feeding them to string.format
    -- local clean_framework = preparePathMatch(_G.metadata.framework_root)
    -- local clean_toolchain = preparePathMatch(_G.metadata.toolchain_root)
    -- local clean_project   = preparePathMatch(OS.project_dir)
    local clean_packages_dir   = preparePathMatch(_G.metadata.packages_dir)

    ------------------------------------------------------------------------------
    --                config.yaml
    ------------------------------------------------------------------------------
    local userClangd = OS.clangd_user_file
    local clangdFiles = {
      { key = 'userGlob', file = userClangd, content = function (ref) return M.readContent(ref) end,
        cache_id = string.sub(vim.fn.sha256(_G.metadata.packages_dir), 1, 16),
        block = function (ref)
          return string.format( self.Global,
                ref.start_marker,
                clean_packages_dir,                                -- If: PathMatch: ['%s/.*']
                table.concat(formattedHAdd, ',\n    '),--   Remove: [%s]
                clean_packages_dir,                                -- If: PathMatch: ['%s/.*']
                is_cpp and '[.](cpp|cxx|cc|c[+][+]|mxx|cppm|ixx|inl|tcc)' or '[.](c|C|cl|ci',
                -- OS.project_dir,                                    -- CompilationDatabase: "%s"
                table.concat(formattedGlobRemove, ',\n    '),--   Remove: [%s]
                table.concat(formattedGlobAdd, ',\n    '),             --   Add: [%s]
                ref.end_marker)
        end,
        start_marker = '', end_marker   = '', delete= false,
      },
      { key = 'userProj', file = userClangd, content = function (ref) return M.readContent(ref) end,
        cache_id = string.sub(vim.fn.sha256(OS.project_dir), 1, 16),
        block = function (ref)
          return string.format(self.Project,
                ref.start_marker,
                OS.project_dir,                            -- If: PathMatch: ['%s/.*']
                -- OS.project_dir,                            -- CompilationDatabase: "%s"
                table.concat(formattedProjRemove, ',\n    '), --   Remove: [%s]
                table.concat(formattedProjAdd, ',\n    '),     --   Add: [%s]
                ref.end_marker)
        end,
        start_marker = '', end_marker   = '', delete= true,
      },
    }
    for _, tbl in ipairs(clangdFiles) do misc.writeFile(tbl.file, tbl:content(), {}) end
    ------------------------------------------------------------------------------

    vim.schedule(function()
      for _, client in ipairs(vim.lsp.get_clients({ name = 'clangd' })) do
        if client and type(client.notify) == 'function' then
          client:notify('workspace/didChangeConfiguration', { settings = {} })
        end
      end
    end)

    return clangdFiles['userProj'].content
  end,
}

local boiler = function(self)
  for filepath, _ in pairs(self.plates) do
    local full_path = vim.fs.joinpath(projectDir, filepath)
    if vim.uv.fs_stat(full_path) then return false end
  end

  for filepath, val in pairs(self.plates) do
    local full_path = vim.fs.joinpath(projectDir, filepath)
    misc.writeFile(full_path, val, {})
  end
  return true
end
------------------------------------------------------------------
--espidf
boilerplate['espidf'] = {
  plates = {
    ----------------------------------------------------
    --
    ['src/main.c'] = [[
#include <stdio.h>
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "main.h"  // IWYU pragma: keep

void run_system_logic(void) {
    printf("Headache-free ESP-IDF system initialized successfully!\n");
}

void app_main(void) {
    run_system_logic();
    while (1) {
        printf("Loop running...\n");
        vTaskDelay(pdMS_TO_TICKS(1000));
    }
}
]],
    ----------------------------------------------------
    --
    ['include/main.h'] = [[
#ifndef MAIN_H_
#define MAIN_H_

void run_system_logic(void);

#endif /* MAIN_H_ */
]],
    ----------------------------------------------------
    --
    ['src/CMakeLists.txt'] = [[
idf_component_register(
    SRCS "main.c"
    INCLUDE_DIRS "." "../include"
)
]],
    ----------------------------------------------------
    --
    ['CMakeLists.txt'] = [[
cmake_minimum_required(VERSION 3.16.0)
include($ENV{IDF_PATH}/tools/cmake/project.cmake)
project(test)
]],
  },
  boiler = function(self) boiler(self) end,
}

------------------------------------------------------------------
--arduino
boilerplate['arduino'] = {
  plates = {
    ----------------------------------------------------
    --
    ['src/main.cpp'] = [[
#include <Arduino.h>
#include "main.hpp"  // IWYU pragma: keep

void setup() {
    Serial.begin(115200);
    while(!Serial) {
        ; // Wait for serial port to connect
    }
    Serial.println("Arduino template initialized successfully!");
}

void loop() {
    Serial.println("Loop running...");
    delay(1000);
}
]],
    ----------------------------------------------------
    --
    ['include/main.hpp'] = [[
#ifndef MAIN_HPP_
#define MAIN_HPP_

// Arduino specific configuration prototypes go here

#endif /* MAIN_HPP_ */
]],
  },
  boiler = function(self) boiler(self) end,
}

------------------------------------------------------------------
--simba
boilerplate['simba'] = {
  plates = {
    ----------------------------------------------------
    --
    ['src/main.c'] = [[
#include "simba.h"
#include "main.h"  // IWYU pragma: keep

int main() {
    sys_init();
    std::printf("Simba framework template initialized successfully!\r\n");

    while (1) {
        std::printf("Loop running...\r\n");
        time_busy_wait_us(1000000); // 1-second delay
    }

    return (0);
}
]],
    ----------------------------------------------------
    --
    ['include/main.h'] = [[
#ifndef MAIN_H_
#define MAIN_H_

// Simba specific configurations go here

#endif /* MAIN_H_ */
]],
  },
  boiler = function(self) boiler(self) end,
}

------------------------------------------------------------------
--zephyr
boilerplate['zephyr'] = {
  plates = {
    ----------------------------------------------------
    -- 1. Main application code using modern namespace includes
    ['src/main.c'] = [[
#include <zephyr/kernel.h>
#include "main.h"  // IWYU pragma: keep

int main(void) {
    printk("Zephyr v4.4.0 environment initialized via nvim-pio!\n");

    while (1) {
        printk("Loop running...\n");
        k_msleep(1000);
    }

    return 0;
}
]],
    ----------------------------------------------------
    -- 2. Project local header file
    ['include/main.h'] = [[
#ifndef MAIN_H_
#define MAIN_H_
#endif /* MAIN_H_ */
]],
    ----------------------------------------------------
    -- 3. MANDATORY: Kept so PlatformIO's auto-generated CMake can read it
    ['zephyr/prj.conf'] = [[
# Zephyr Kernel configuration flags
CONFIG_PRINTK=y
]],
    ----------------------------------------------------
    -- 4. MANDATORY: Kept so PlatformIO's auto-generated CMake can read it
    ['zephyr/CMakeLists.txt'] = [[
cmake_minimum_required(VERSION 3.20.0)
find_package(Zephyr REQUIRED HINTS $ENV{ZEPHYR_BASE})
project(idedata_gen)

# Locate and apply your app source definitions to the native 'app' build target
FILE(GLOB app_sources ../src/*.c*)
target_sources(app PRIVATE ${app_sources})
]],
  },
  boiler = function(self) boiler(self) end,
}

------------------------------------------------------------------
--mbed
boilerplate['mbed'] = {
  plates = {
    ['src/main.cpp'] = [[
#include "mbed.h"
#include "main.hpp"  // IWYU pragma: keep

// Initialize a digital output pin (e.g., LED1)
DigitalOut led(LED1);

int main() {
    printf("Mbed OS project initialized successfully!\n");

    while (1) {
        led = !led; // Toggle the LED state
        thread_sleep_for(1000); // Sleep thread for 1000ms
    }
}
]],
    ['include/main.hpp'] = [[
#ifndef MAIN_HPP_
#define MAIN_HPP_

// Mbed OS hardware maps and classes go here

#endif /* MAIN_HPP_ */
]],
    ['mbed_app.json'] = [[
{
    "target_overrides": {
        "*": {
            "platform.stdio-baud-rate": 115200
        }
    }
}
]],
  },
  boiler = function(self) boiler(self) end,
}

----------------------------------------------------
--stm32cube
boilerplate['stm32cube'] = {
  plates = {
    ['src/main.c'] = [[
#include "stm32f4xx_hal.h" // Replace 'f4' with your specific family (e.g., g0, l4, h7)
#include "main.h"  // IWYU pragma: keep

void SystemClock_Config(void);

int main(void) {
    // Reset of all peripherals, Initializes the Flash interface and the Systick.
    HAL_Init();
    
    // Configure the system clock
    SystemClock_Config();

    while (1) {
        // Toggle GPIO pins or process loop structures here
        HAL_Delay(1000);
    }
}

void SystemClock_Config(void) {
    // Clock register configurations go here (Generated via STM32CubeMX)
}
]],
    ['include/main.h'] = [[
#ifndef MAIN_H_
#define MAIN_H_

#include "stm32f4xx_hal.h"

#endif /* MAIN_H_ */
]],
  },
  boiler = function(self) boiler(self) end,
}

----------------------------------------------------
--cmsis
boilerplate['cmsis'] = {
  plates = {
    ['src/main.c'] = [[
#include "stm32f4xx.h" // Include native device register mappings directly
#include "main.h"  // IWYU pragma: keep

int main(void) {
    // Directly enable peripheral clocks via reset control registers (RCC)
    RCC->AHB1ENR |= RCC_AHB1ENR_GPIOAEN; 

    while (1) {
        // Manipulate raw bit fields inside registers (e.g., ODR / BSRR)
        for (volatile int i = 0; i < 100000; i++); // Crude software delay loop
    }
}
]],
    ['include/main.h'] = [[
#ifndef MAIN_H_
#define MAIN_H_

// Bare-metal peripheral addressing offsets go here

#endif /* MAIN_H_ */
]],
  },
  boiler = function(self) boiler(self) end,
}

----------------------------------------------------
--libopencm3
boilerplate['libopencm3'] = {
  plates = {
    ['src/main.c'] = [[
#include <libopencm3/stm32/rcc.h>
#include <libopencm3/stm32/gpio.h>
#include "main.h"  // IWYU pragma: keep

int main(void) {
    // 1. Enable the clock for GPIO Port C (Common LED port on blue-pill boards)
    rcc_periph_clock_enable(RCC_GPIOC);

    // 2. Configure Pin 13 as an Output pin
    gpio_set_mode(GPIOC, GPIO_MODE_OUTPUT_2MHZ, GPIO_CNF_OUTPUT_PUSHPULL, GPIO_IO13);

    while (1) {
        gpio_toggle(GPIOC, GPIO_IO13);

        // Crude hardware delay loop loop
        for (int i = 0; i < 800000; i++) {
            __asm__("nop");
        }
    }
    return 0;
}
]],
    ['include/main.h'] = [[
#ifndef MAIN_H_
#define MAIN_H_

// Peripherals parameters can be defined here

#endif /* MAIN_H_ */
]],
  },
  boiler = function(self) boiler(self) end,
}

----------------------------------------------------
--wiringpi
boilerplate['wiringpi'] = {
  plates = {
    ----------------------------------------------------
    -- 1. Main source file utilizing standard WiringPi register bindings
    ['src/main.c'] = [[
#include <stdio.h>
#include <wiringPi.h>
#include "main.h"

#define BLINK_LED_PIN 0 // WiringPi Pin 0 maps to physical chip layout offsets

int main(void) {
    printf("WiringPi project initialized successfully via nvim-pio!\n");

    // Initialize the underlying hardware memory access layers
    if (wiringPiSetup() < 0) {
        fprintf(stderr, "Error: Failed to initialize WiringPi register mappings.\n");
        return 1;
    }

    pinMode(BLINK_LED_PIN, OUTPUT);

    while (1) {
        digitalWrite(BLINK_LED_PIN, HIGH);
        delay(500); // Built-in millisecond execution delay utility
        digitalWrite(BLINK_LED_PIN, LOW);
        delay(500);
    }

    return 0;
}
]],
    ----------------------------------------------------
    -- 2. Local header template
    ['include/main.h'] = [[
#ifndef MAIN_H_
#define MAIN_H_

// Global constants or configurations for WiringPi tasks go here

#endif /* MAIN_H_ */
]],
  },
  boiler = function(self) boiler(self) end,
}

----------------------------------------------------
--energia
boilerplate['energia'] = {
  plates = {
    ['src/main.cpp'] = [[
#include <Energia.h>
#include "main.hpp"

void setup() {
    pinMode(RED_LED, OUTPUT);
}

void loop() {
    digitalWrite(RED_LED, HIGH);
    delay(500);
    digitalWrite(RED_LED, LOW);
    delay(500);
}
]],
    ['include/main.hpp'] = [[
#ifndef MAIN_HPP_
#define MAIN_HPP_
// TI Energia configuration maps go here
#endif
]],
  },
  boiler = function(self) boiler(self) end,
}

----------------------------------------------------
--SPL (Standard Peripheral Library)
boilerplate['spl'] = {
  plates = {
    ['src/main.c'] = [[
#include "stm32f10x.h"
#include "main.h"

void Delay(uint32_t nTime);

int main(void) {
    // Enable peripheral clock for GPIOC
    RCC_APB2PeriphClockCmd(RCC_APB2Periph_GPIOC, ENABLE);

    // Configure PC13 as Output Push-Pull
    GPIO_InitTypeDef GPIO_InitStructure;
    GPIO_InitStructure.GPIO_Pin = GPIO_Pin_13;
    GPIO_InitStructure.GPIO_Speed = GPIO_Speed_50MHz;
    GPIO_InitStructure.GPIO_Mode = GPIO_Mode_Out_PP;
    GPIO_Init(GPIOC, &GPIO_InitStructure);

    while (1) {
        GPIO_SetBits(GPIOC, GPIO_Pin_13);
        Delay(0xFFFFF);
        GPIO_ResetBits(GPIOC, GPIO_Pin_13);
        Delay(0xFFFFF);
    }
}

void Delay(uint32_t nTime) {
    for(; nTime != 0; nTime--);
}
]],
    ['include/main.h'] = [[
#ifndef MAIN_H_
#define MAIN_H_
#include "stm32f10x_gpio.h"
#include "stm32f10x_rcc.h"
#endif
]],
  },
  boiler = function(self) boiler(self) end,
}

----------------------------------------------------
--esp8266-rtos-sdk
boilerplate['esp8266-rtos-sdk'] = {
  plates = {
    ['src/main.c'] = [[
#include <stdio.h>
#include "esp_common.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "main.h"

void hello_task(void *pvParameters) {
    while (1) {
        printf("Hello from ESP8266 RTOS SDK via nvim-pio!\n");
        vTaskDelay(1000 / portTICK_RATE_MS);
    }
}

void user_init(void) {
    printf("SDK version:%s\n", system_get_sdk_version());
    xTaskCreate(hello_task, "hello_task", 256, NULL, 2, NULL);
}
]],
    ['include/main.h'] = [[
#ifndef MAIN_H_
#define MAIN_H_
// ESP8266 system profiles
#endif
]],
  },
  boiler = function(self) boiler(self) end,
}

----------------------------------------------------
--Freedom E SDK (freedom-e-sdk)
boilerplate['freedom-e-sdk'] = {
  plates = {
    ['src/main.c'] = [[
#include <stdio.h>
#include <metal/gpio.h>
#include "main.h"

int main(void) {
    printf("SiFive Freedom E SDK Initialized successfully via nvim-pio!\n");

    struct metal_gpio *gpio = metal_gpio_get_device(0);
    if (!gpio) return 1;

    // Configure pin 5 (typically an on-board LED) as output
    metal_gpio_disable_input(gpio, 5);
    metal_gpio_enable_output(gpio, 5);

    while (1) {
        metal_gpio_toggle_pin(gpio, 5);
        for (volatile int i = 0; i < 500000; i++); // basic delay loop
    }
    return 0;
}
]],
    ['include/main.h'] = [[#ifndef MAIN_H_\n#define MAIN_H_\n#endif]],
  },
  boiler = function(self) boiler(self) end,
}

----------------------------------------------------
--Standalone FreeRTOS (freertos)
boilerplate['freertos'] = {
  plates = {
    ['src/main.c'] = [[
#include <stdio.h>
#include "FreeRTOS.h"
#include "task.h"
#include "main.h"

void vBlinkTask(void *pvParameters) {
    while (1) {
        printf("FreeRTOS thread running loop...\n");
        vTaskDelay(pdMS_TO_TICKS(1000));
    }
}

int main(void) {
    xTaskCreate(vBlinkTask, "Blink", 256, NULL, 1, NULL);
    vTaskStartScheduler();
    while (1);
    return 0;
}
]],
    ['include/main.h'] = [[#ifndef MAIN_H_\n#define MAIN_H_\n#endif]],
  },
  boiler = function(self) boiler(self) end,
}

----------------------------------------------------
--Renesas FSP (fsp)
boilerplate['fsp'] = {
  plates = {
    ['src/main.c'] = [[
#include "hal_data.h"
#include "main.h"

void hal_entry(void) {
    /* Initialize or toggle peripherals using */
    while (1) {
        R_BSP_SoftwareDelay(1000, BSP_DELAY_UNITS_MILLISECONDS);
    }
}
]],
    ['include/main.h'] = [[#ifndef MAIN_H_\n#define MAIN_H_\n#endif]],
  },
  boiler = function(self) boiler(self) end,
}

----------------------------------------------------
-- For pulp-os, pulp-runtime, and pulp-sdk, the syntax is identical
local pulp_boilerplate = {
  plates = {
    ['src/main.c'] = [[
#include <stdio.h>
#include "pmsis.h"
#include "main.h"

void helloworld(void) {
    printf("Hello from Parallel Ultra Low Power RISC-V Core!\n");
    pmsis_exit(0);
}

int main(void) {
    return pmsis_kickoff((void *)helloworld);
}
]],
    ['include/main.h'] = [[#ifndef MAIN_H_\n#define MAIN_H_\n#endif]],
  },
  boiler = function(self) boiler(self) end,
}
boilerplate['pulp-os'] = pulp_boilerplate
boilerplate['pulp-runtime'] = pulp_boilerplate
boilerplate['pulp-sdk'] = pulp_boilerplate

----------------------------------------------------
--Shakti SDK (shakti-sdk)
boilerplate['shakti-sdk'] = {
  plates = {
    ['src/main.c'] = [[
#include <stdio.h>
#include "utils.h"
#include "main.h"

int main() {
    printf("Shakti RISC-V processor initialized via nvim-pio!\n");

    while(1) {
        // Direct peripheral manipulations go here
    }
    return 0;
}
]],
    ['include/main.h'] = [[#ifndef MAIN_H_\n#define MAIN_H_\n#endif]],
  },
  boiler = function(self) boiler(self) end,
}

----------------------------------------------------
--Western Digital SweRV SDK (wd-riscv-sdk)
boilerplate['wd-riscv-sdk'] = {
  plates = {
    ['src/main.c'] = [[
#include <stdio.h>
#include "psp_api.h"
#include "main.h"

int main(void) {
    printf("Western Digital SweRV Core initialized successfully!\n");
    
    while(1) {
        // SweRV hardware execution tasks
    }
    return 0;
}
]],
    ['include/main.h'] = [[#ifndef MAIN_H_\n#define MAIN_H_\n#endif]],
  },
  boiler = function(self) boiler(self) end,
}

function M.boilerplate_gen(framework, from)
  from = from or ''
  local entry = boilerplate[framework]
  if not entry then return false end
  -- Using a colon passes 'entry' as 'self' so we can read its 'plates' table
  return entry:boiler()
end

return M
