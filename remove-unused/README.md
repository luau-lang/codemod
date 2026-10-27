# Remove Unused Variables and Functions Codemod

A codemod that identifies and removes unused variables and functions from Lua/Luau code. This tool is designed to clean up your codebase by eliminating dead code, focusing on variables and functions that are declared but never used. It is particularly useful in conjunction with flag cleanup, which often leaves unused code in its wake.

## Overview

The remove-unused codemod performs the following operations:

1. Parses Lua/Luau source code into an abstract syntax tree (AST)
2. Analyzes the AST to identify all variable and function declarations
3. Tracks usage throughout the code
4. Removes variables and functions with zero usage counts
5. Preserves comments and formatting when removing code

## Key Features

- Identifies and removes completely unused local variables and functions
- Preserves variables prefixed with underscore (`_`) as they indicate intentional non-usage 
- Handles multiple variable declarations in a single statement
- Respects selene linting exclusions
- Properly maintains comments and code formatting

## Edge Cases

The remove-unused codemod handles the following unique cases:

- **Multiple Variables from Single Function Call**: When multiple variables are assigned from a single function call (e.g., `local a, b = func()`), the codemod will only remove unused variables if all variables are unused. This preserves the function call semantics and prevents breaking code.

- **Variable assignments Are Not Uses**: When a variable is assigned a value but not used elsewhere (e.g., `x = 5`), the assignment itself is not considered a "use" of the variable, consistent with linting rules.

- **Underscore-Prefixed Variables**: Variables that begin with an underscore (e.g., `_ignored`) are intentionally skipped, as the underscore prefix conventionally indicates intentional non-usage in Lua/Luau.

- **Function Parameters**: Function parameters are not analyzed for usage, as having unused parameters is acceptable in many codebases and linting configurations.

## Usage

Follow the main [README](../README.md) instructions for how to install Lute and run codemods with `lute transform`

```
$ lute transform codemod/remove-unused/init.luau <files...> -- --selene <path>
```

### Options

- `--selene <path>`: Path to a selene.toml file so variable removal respects files excluded from linting.

## Algorithm

The codemod uses a two-phase approach:

1. **Function and Variable Usage Analysis**: 
   - Traverses the AST to find all variable and function declarations
   - Tracks references to these items throughout the code
   - Builds a usage count for each variable and function

2. **Code Transformation**:
   - Removes completely unused variable and function declarations
   - For declarations with multiple variables, removes only the unused ones
   - Preserves comments and formatting of removed statements by carefully handling trivia nodes

## Examples

### Basic Variable Removal

Before
```lua
local unused = 123
local used = 456
print(used)
```

After
```lua
local used = 456
print(used)
```

### Multiple Variable Declaration

Before
```lua
local a, b, c = 1, 2, 3
print(a, c)
```

After
```lua
local a, c = 1, 3
print(a, c)
```

### Function Removal

Before
```lua
local function unusedFunction()
    return "never called"
end

local function usedFunction()
    return "important"
end

print(usedFunction())
```

After
```lua
local function usedFunction()
    return "important"
end

print(usedFunction())
```
### Comment Preservation

Before
```lua
-- This comment is for x and should be preserved
local x = 1
-- This comment is for unused and should move to the next statement
local unused = 2
-- This comment is for y
local y = 3
print(x, y)
```

After
```lua
-- This comment is for x and should be preserved
local x = 1
-- This comment is for unused and should move to the next statement
-- This comment is for y
local y = 3
print(x, y)
```

### Complex Function Analysis

Before
```lua
local function helper(x, y)
    return x + y
end

local function unusedHelper(a, b)
    return a * b
end

local function calculate(input)
    -- This calls helper but not unusedHelper
    return helper(input, 5) + input
end

print(calculate(10))
```

After
```lua
local function helper(x, y)
    return x + y
end

local function calculate(input)
    -- This calls helper but not unusedHelper
    return helper(input, 5) + input
end

print(calculate(10))
```