M = {}

M.core_dir = ''

local boilerplate = {}

-- INFO: main.cpp
--- stylua: ignore
boilerplate['arduino'] = {
  rewrite = false,
  read = false,
  content = [[
#include <Arduino.h>

void setup() {

}

void loop() {

}
]],
}

-- INFO: platformio.ini
boilerplate['platformio.ini'] = {
  rewrite = false,
  read = false,
  template = [[
[platformio]
core_dir = %s
platforms_dir = ${platformio.core_dir}/platforms
packages_dir = ${platformio.core_dir}/packages
;libdeps_dir = ./external_libs

default_envs =
;default_envs = uno, nodemcu

;--------------------------------------------------------------------------
[env]
framework = arduino
upload_speed = 115200
monitor_speed = 9600

monitor_rts = 1   ; 1 combination to reset esp32c6 (Table 32.3-2. CDC-ACM Settings with RTS and DTR)
monitor_dtr = 0   ; 0 // pio dev mon --rts=0 --dtr=0 then pio dev mon --rts=1 dtr=0

extra_scripts =
;post:generate_compileDB.py
;    pre:enable_toolchain.py ; enabled global env 'PLATFORMIO_SETTING_COMPILATIONDB_INCLUDE_TOOLCHAIN'

lib_ldf_mode = chain   ;Library dependencies Finder ldf

;[env:seeed_xiao_esp32c3]
;platform = espressif32
;board = seeed_xiao_esp32c3

]],
  content = function(self)
    return string.format(self.template, M.core_dir)
  end,
}

-- "--config-file=%s"
-- =============================================================================
-- DYNAMIC CLANGD CONFIGURATION TEMPLATE
-- =============================================================================
-- Note: %q is used for paths to handle escaping and spaces automatically.
-- INFO: .clangd_config
boilerplate['.clangd_config'] = {
  rewrite = false,
  read = true,
  content = [[
{
  cmd = {
    "clangd",
    "--all-scopes-completion",
    "--background-index",
    "--clang-tidy",
    "--compile_args_from=filesystem",
    "--enable-config",
    "--completion-parse=always",
    "--completion-style=detailed",
    "--header-insertion=iwyu",
    "--fallback-style=llvm",
    "--log=verbose",
    "--pch-storage=memory",
    "--pretty",
    "--ranking-model=decision_forest",
    "--sync",
    "--offset-encoding=utf-16",
    "--query-driver=%s"
  },
  filetypes = { 'c', 'cpp', 'objc', 'objcpp', 'cuda', 'proto' },
  root_markers = {
    'platformio.ini',
    'CMakeLists.txt',
    '.clangd',
    '.clang-tidy',
    '.clang-format',
    'compile_commands.json',
    'compile_flags.txt',
    'configure.ac',
    '.git',
  },
  workspace_required = true,
  single_file_support = true,
  init_options = {
    usePlaceholders = true,
    completeUnimported = true,
    fallbackFlags = {%s},
    clangdFileStatus = true,
    compilationDatabasePath = %q,
  }
}
]],
}
-- CompileFlags:
--   Add:
--     - "-xc++"
--     - "-std=c++17"
--     - "-D__cplusplus=201703L"
--     - "-isystemC:/Users/batoaqaa/.platformio/packages/toolchain-riscv32-esp/riscv32-esp-elf/include/c++/14.2.0"
--     - "-isystemC:/Users/batoaqaa/.platformio/packages/toolchain-riscv32-esp/riscv32-esp-elf/include/c++/14.2.0/riscv32-esp-elf"
--     - "-isystemC:/Users/batoaqaa/.platformio/packages/toolchain-riscv32-esp/lib/gcc/riscv32-esp-elf/14.2.0/include"
--     - "-isystemC:/Users/batoaqaa/.platformio/packages/toolchain-riscv32-esp/lib/gcc/riscv32-esp-elf/14.2.0/include-fixed"
--     - "-isystemC:/Users/batoaqaa/.platformio/packages/toolchain-riscv32-esp/riscv32-esp-elf/include"
--   Remove:
--     - "-target=*"
--     - "-target"
--     - "riscv32-esp-elf"
--     - "-fno-fat-lto-objects"
--     - "-fno%%-fat%%-lto%%-objects"
--     - "-fno%%-canonical%%-system%%-headers"
--     - "-misc-definitions-in-headers"
--     - "-fno-tree-switch-conversion"
--     - "-mtext-section-literals"
--     - "-mlong-calls"
--     - "-mlongcalls"
--     - "-fstrict-volatile-bitfields"
--     - "-free*"
--     - "-fipa-pta*"
--     - "-march=*"
--     - "-mabi=*"
--     - "-mcpu=*"
-- Diagnostics:
--   Suppress:
--     - "misc-definitions-in-headers"
--     - "pp_including_mainfile_in_preamble"
--     - "misc-unused-using-decls"
--     - "unused-includes"
--   ClangTidy:
--     Remove:
--       - "readability-*"
--       - "cert-err58-cpp"
--       - "llvmlibc-*"
--       - "fuchsia-*"
--       - "hicpp-avoid-c-arrays"
--       - "cppcoreguidelines-*"
--       - "llvm-*"
--       - "google-*"
--       - "bugprone-*"
--       - "hicpp-vararg"
--       - "modernize-*"
-- Index:
--   Background: Build
--   External:
--     File: .clangd_index

-- INFO: .clangd
-- boilerplate['.clangd']
boilerplate['.clangd'] = {
  rewrite = false,
  read = false,
  -- template = [[
  content = [[
---
CompileFlags:
  Add:
    - "-xc++"
    - "-std=gnu++17"
    - "-Wno-pragma-system-header-outside-header"
    - "-Wno-unknown-warning-option"
    - "-Wno-unused-includes"
  Remove: 
    - "-Wunknown-warning-option"
    - "-fno-tree-switch-conversion"
    - "-fno-fat-lto-objects"
    - "-fno-canonical-system-headers"
    - "-mtext-section-literals"
    - "-mlong-calls"
    - "-fstrict-volatile-bitfields"
    - "-march=.*"
    - "-mabi=.*"
    - "-mcpu=.*"
    - "-fipa-pta.*"
Diagnostics:
  Suppress: 
    - "pp_file_not_found"
    - "pp_file_not_found_angled_not_fatal"
    - "pp_included_file_not_found"
    - "pp_including_mainfile_in_preamble"
    - "unused-includes"
    - "misc-definitions-in-headers"
  ClangTidy:
    Remove: ["readability-*", "modernize-*", "bugprone-*", "cert-err58-cpp"]
]],
  -- content = function(self)
  --   local sysroot = '--sysroot=' .. _G.metadata.sysroot
  --   local triplet = '--target=' .. _G.metadata.triplet
  --   return string.format(self.template, triplet, sysroot)
  -- end,
}

-- INFO: .clang-format
boilerplate['.clang-format'] = {
  rewrite = false,
  read = false,
  content = [[
---
Language:        Cpp
# BasedOnStyle:  LLVM
AccessModifierOffset: -2
AlignAfterOpenBracket: Align
AlignArrayOfStructures: None
AlignConsecutiveAssignments:
  Enabled:         false
  AcrossEmptyLines: false
  AcrossComments:  false
  AlignCompound:   false
  AlignFunctionPointers: false
  PadOperators:    true
AlignConsecutiveBitFields:
  Enabled:         false
  AcrossEmptyLines: false
  AcrossComments:  false
  AlignCompound:   false
  AlignFunctionPointers: false
  PadOperators:    false
AlignConsecutiveDeclarations:
  Enabled:         false
  AcrossEmptyLines: false
  AcrossComments:  false
  AlignCompound:   false
  AlignFunctionPointers: false
  PadOperators:    false
AlignConsecutiveMacros:
  Enabled:         false
  AcrossEmptyLines: false
  AcrossComments:  false
  AlignCompound:   false
  AlignFunctionPointers: false
  PadOperators:    false
AlignConsecutiveShortCaseStatements:
  Enabled:         false
  AcrossEmptyLines: false
  AcrossComments:  false
  AlignCaseColons: false
AlignEscapedNewlines: Right
AlignOperands:   Align
AlignTrailingComments:
  Kind:            Always
  OverEmptyLines:  0
AllowAllArgumentsOnNextLine: true
AllowAllParametersOfDeclarationOnNextLine: true
AllowBreakBeforeNoexceptSpecifier: Never
AllowShortBlocksOnASingleLine: Never
AllowShortCaseLabelsOnASingleLine: false
AllowShortCompoundRequirementOnASingleLine: true
AllowShortEnumsOnASingleLine: true
AllowShortFunctionsOnASingleLine: All
AllowShortIfStatementsOnASingleLine: Never
AllowShortLambdasOnASingleLine: All
AllowShortLoopsOnASingleLine: false
AlwaysBreakAfterDefinitionReturnType: None
AlwaysBreakAfterReturnType: None
AlwaysBreakBeforeMultilineStrings: false
AlwaysBreakTemplateDeclarations: MultiLine
AttributeMacros:
  - __capability
BinPackArguments: true
BinPackParameters: true
BitFieldColonSpacing: Both
BraceWrapping:
  AfterCaseLabel:  false
  AfterClass:      false
  AfterControlStatement: Never
  AfterEnum:       false
  AfterExternBlock: false
  AfterFunction:   false
  AfterNamespace:  false
  AfterObjCDeclaration: false
  AfterStruct:     false
  AfterUnion:      false
  BeforeCatch:     false
  BeforeElse:      false
  BeforeLambdaBody: false
  BeforeWhile:     false
  IndentBraces:    false
  SplitEmptyFunction: true
  SplitEmptyRecord: true
  SplitEmptyNamespace: true
BreakAdjacentStringLiterals: true
BreakAfterAttributes: Leave
BreakAfterJavaFieldAnnotations: false
BreakArrays:     true
BreakBeforeBinaryOperators: None
BreakBeforeConceptDeclarations: Always
BreakBeforeBraces: Attach
BreakBeforeInlineASMColon: OnlyMultiline
BreakBeforeTernaryOperators: true
BreakConstructorInitializers: BeforeColon
BreakInheritanceList: BeforeColon
BreakStringLiterals: true
ColumnLimit:     80
CommentPragmas:  '^ IWYU pragma:'
CompactNamespaces: false
ConstructorInitializerIndentWidth: 4
ContinuationIndentWidth: 4
Cpp11BracedListStyle: true
DerivePointerAlignment: false
DisableFormat:   false
EmptyLineAfterAccessModifier: Never
EmptyLineBeforeAccessModifier: LogicalBlock
ExperimentalAutoDetectBinPacking: false
FixNamespaceComments: true
ForEachMacros:
  - foreach
  - Q_FOREACH
  - BOOST_FOREACH
IfMacros:
  - KJ_IF_MAYBE
IncludeBlocks:   Preserve
IncludeCategories:
  - Regex:           '^"(llvm|llvm-c|clang|clang-c)/'
    Priority:        2
    SortPriority:    0
    CaseSensitive:   false
  - Regex:           '^(<|"(gtest|gmock|isl|json)/)'
    Priority:        3
    SortPriority:    0
    CaseSensitive:   false
  - Regex:           '.*'
    Priority:        1
    SortPriority:    0
    CaseSensitive:   false
IncludeIsMainRegex: '(Test)?$'
IncludeIsMainSourceRegex: ''
IndentAccessModifiers: false
IndentCaseBlocks: false
IndentCaseLabels: false
IndentExternBlock: AfterExternBlock
IndentGotoLabels: true
IndentPPDirectives: None
IndentRequiresClause: true
IndentWidth:     2
IndentWrappedFunctionNames: false
InsertBraces:    false
InsertNewlineAtEOF: false
InsertTrailingCommas: None
IntegerLiteralSeparator:
  Binary:          0
  BinaryMinDigits: 0
  Decimal:         0
  DecimalMinDigits: 0
  Hex:             0
  HexMinDigits:    0
JavaScriptQuotes: Leave
JavaScriptWrapImports: true
KeepEmptyLinesAtTheStartOfBlocks: true
KeepEmptyLinesAtEOF: false
LambdaBodyIndentation: Signature
LineEnding:      DeriveLF
MacroBlockBegin: ''
MacroBlockEnd:   ''
MaxEmptyLinesToKeep: 1
NamespaceIndentation: None
ObjCBinPackProtocolList: Auto
ObjCBlockIndentWidth: 2
ObjCBreakBeforeNestedBlockParam: true
ObjCSpaceAfterProperty: false
ObjCSpaceBeforeProtocolList: true
PackConstructorInitializers: BinPack
PenaltyBreakAssignment: 2
PenaltyBreakBeforeFirstCallParameter: 19
PenaltyBreakComment: 300
PenaltyBreakFirstLessLess: 120
PenaltyBreakOpenParenthesis: 0
PenaltyBreakScopeResolution: 500
PenaltyBreakString: 1000
PenaltyBreakTemplateDeclaration: 10
PenaltyExcessCharacter: 1000000
PenaltyIndentedWhitespace: 0
PenaltyReturnTypeOnItsOwnLine: 60
PointerAlignment: Right
PPIndentWidth:   -1
QualifierAlignment: Leave
ReferenceAlignment: Pointer
ReflowComments:  true
RemoveBracesLLVM: false
RemoveParentheses: Leave
RemoveSemicolon: false
RequiresClausePosition: OwnLine
RequiresExpressionIndentation: OuterScope
SeparateDefinitionBlocks: Leave
ShortNamespaceLines: 1
SkipMacroDefinitionBody: false
SortIncludes:    CaseSensitive
SortJavaStaticImport: Before
SortUsingDeclarations: LexicographicNumeric
SpaceAfterCStyleCast: false
SpaceAfterLogicalNot: false
SpaceAfterTemplateKeyword: true
SpaceAroundPointerQualifiers: Default
SpaceBeforeAssignmentOperators: true
SpaceBeforeCaseColon: false
SpaceBeforeCpp11BracedList: false
SpaceBeforeCtorInitializerColon: true
SpaceBeforeInheritanceColon: true
SpaceBeforeJsonColon: false
SpaceBeforeParens: ControlStatements
SpaceBeforeParensOptions:
  AfterControlStatements: true
  AfterForeachMacros: true
  AfterFunctionDefinitionName: false
  AfterFunctionDeclarationName: false
  AfterIfMacros:   true
  AfterOverloadedOperator: false
  AfterPlacementOperator: true
  AfterRequiresInClause: false
  AfterRequiresInExpression: false
  BeforeNonEmptyParentheses: false
SpaceBeforeRangeBasedForLoopColon: true
SpaceBeforeSquareBrackets: false
SpaceInEmptyBlock: false
SpacesBeforeTrailingComments: 1
SpacesInAngles:  Never
SpacesInContainerLiterals: true
SpacesInLineCommentPrefix:
  Minimum:         1
  Maximum:         -1
SpacesInParens:  Never
SpacesInParensOptions:
  InCStyleCasts:   false
  InConditionalStatements: false
  InEmptyParentheses: false
  Other:           false
SpacesInSquareBrackets: false
Standard:        Latest
StatementAttributeLikeMacros:
  - Q_EMIT
StatementMacros:
  - Q_UNUSED
  - QT_REQUIRE_VERSION
TabWidth:        8
UseTab:          Never
VerilogBreakBetweenInstancePorts: true
WhitespaceSensitiveMacros:
  - BOOST_PP_STRINGIZE
  - CF_SWIFT_NAME
  - NS_SWIFT_NAME
  - PP_STRINGIZE
  - STRINGIZE
...
]],
}
-- stylua: ignore
function M.boilerplate_gen(framework, src_path, filename)
  filename = filename or framework
  local entry = boilerplate[framework]
  if not entry then return '' end
  local file_path = vim.fs.normalize(src_path .. '/' .. filename)

  if vim.uv.fs_stat(file_path) then
    if not entry.rewrite then
      if entry.read then
        local ok, content = vim.misc.readFile(file_path)
        if ok then return content end
        -- local fr = io.open(file_path, 'r')
        -- if fr then return (fr:read('*a')) end
      end
      return ''
    end
  end
  --
  local template = type(entry.content) == 'function' and entry:content() or entry.content
  vim.misc.writeFile(file_path, template, {})

  if entry.read then
    return template
  else return '' end
end

return M
