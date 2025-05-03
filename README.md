# Name TBD

A code modification tool for the [Luau](https://luau.org/) programming language, powered by [lute](https://github.com/luau-lang/lute).
This tool provides a driver application to run any codemods on a particular set of files / directories.

## Usage

To install, ensure the [lute](https://github.com/luau-lang/lute) runtime is available, and clone this repository:

```sh
$ git clone https://github.com/luau-lang/codemod.git
```

Usage:

```
$ lute codemod/main.luau <codemod file> [codemod options...] <files...>
```

This loads the provided codemod file and executes it on the set of files / directories provided.
Any codemod options are parsed and passed to the running codemod.

## Writing a codemod

### Transformer function

In its simplest form, a codemod is just a function that takes in the source code of a file, and
returns a modified source code result.

A sample codemod file may look like below:

```luau
function codemod(ctx)
    -- transform the provided ctx.source
    return ctx.source
end

return codemod
```

The function is provided the following codemod context (`ctx`):

```luau
type CodemodContext = {
    path: string, -- The path to the file the codemod is currently applying on
    source: string, -- The source code of the file
}
```

The driver will then apply this function on all provided files. It is the driver's responsibility to filter the file
input on provided glob patterns / ignore lists, as well as perform the necessary filesystem operations to read the file
and then write the result.

The codemod driver itself does not perform any AST parsing or printing. However, Lute comes with a built-in Luau parser,
available at `@batteries/syntax`:

```luau
local parser = require("@batteries/syntax/parser")
local printer = require("@batteries/syntax/printer")

function codemod(ctx)
    local parsedResult = parser.parsefile(ctx.source)
    return printer.printfile(parsedResult)
end

return codemod
```

A visitor mechanism is also available for basic AST traversal and modification.

```luau
local parser = require("@batteries/syntax/parser")
local printer = require("@batteries/syntax/printer")
local visitor = require("@batteries/syntax/visitor")

function codemod(ctx)
    local parsedResult = parser.parsefile(ctx.source)

    local uppercaseVisitor = visitor.createVisitor()

    uppercaseVisitor.visitLocalReference = function(node)
        node.token.text = node.token.text:upper()
    end

    visitor.visitBlock(parsedResult.block, uppercaseVisitor)

    return printer.printfile(parsedResult)
end

return codemod
```

### Deleting a file

If the codemod wishes to delete the file given, it should return the deletion marker, available at `codemod/types.luau`

```luau
local driver = require("codemod/types")

local function codemod(ctx)
    if shouldDeleteFile(ctx.source) then
        return driver.DELETION_MARKER
    end

    -- ...
end
```

If the deletion marker is returned, the driver will defer deletion of the codemod script until after all files have been
processed. This is to allow require resolution to still work even if a file is to-be-deleted.

### Codemod Configuration

More complex codemods may wish to allow configuration to control how the codemod behaves.
To do so, the codemod module can return a table instead of just a function. This table must contain a `transform`
function, and may contain an `options` table to parse particular flags:

```luau
local function codemod(ctx)
    -- ...
end

return {
    options = {
        { name = "NAME", kind = "KIND", default = ... },
        ...
    },
    transform = codemod
}
```

An option follows the following schema:

```luau
type CodemodOption =
    | { name: string, kind: "string", default: string? }
    | { name: string, kind: "boolean", default: boolean? }
```

It is the responsibility of the driver to ensure the options are parsed and provided to the codemod. If a default is
specified, the flag is optional, otherwise it must be specified. Currently, only `string` and `boolean` configuration
are supported.

The resolved options are then made available as part of the codemod context

```luau
type CodemodContext<Options = {}> = {
    path: string,
    source: string,
    options: Options
}
```

To use the options on the command line, they should be passed as flags after the codemod module path, e.g.:

For the following codemod:

```luau
type Options = {
    name: string,
    value: boolean
}


local function codemod(ctx: CodemodContext<Options>)
    local name = ctx.options.name
    local value = ctx.options.value
    -- ...
end

return {
    options = {
        { name = "name", kind = "string" },
        { name = "value", kind = "boolean", default = true }
    }
    transform = codemod,
}
```

The flags are passed as:

```
$ lute codemod/main.luau transform.luau --name STRING --value BOOLEAN <files...>
```
