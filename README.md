# Name TBD

A code migration tool for the [Luau](https://luau.org/) programming language, powered by [lute](https://github.com/luau-lang/lute).
This tool provides a driver application to run any migrations (also known as transformations or codemods) on a particular set of files / directories.

## Usage

To install, ensure the [lute](https://github.com/luau-lang/lute) runtime is available, and clone this repository:

```sh
$ git clone https://github.com/luau-lang/codemod.git
```

Usage:

```
$ lute codemod/main.luau <codemod file> [migration options...] <files...>
```

This loads the provided code migration file and executes it on the set of files / directories provided.
Any options are parsed and passed to the running migration.

> [!NOTE]
> Due to the way Lute works, the path of `<codemod file>` must be relative to the location of `codemod/main.luau`.
> e.g., to use the `flag-clipper` codemod, you would pass `./flag-clipper`. [Upstream Issue](https://github.com/luau-lang/lute/issues/321)

## Writing a code migration

### Transformer function

In its simplest form, a code migration is just a function that takes in the source code of a file, and
returns a modified source code result.

A sample migration file may look like below:

```luau
function migration(ctx)
    -- transform the provided ctx.source
    return ctx.source
end

return migration
```

The function is provided the following migration context (`ctx`):

```luau
type MigrationContext = {
    path: string, -- The path to the file the migration is currently applying on
    source: string, -- The source code of the file
}
```

The driver will then apply this function on all provided files. It is the driver's responsibility to filter the file
input on provided glob patterns / ignore lists, as well as perform the necessary filesystem operations to read the file
and then write the result.

The migration driver itself does not perform any AST parsing or printing. However, Lute comes with a built-in Luau parser,
available at `@std/syntax`:

```luau
local parser = require("@std/syntax/parser")
local printer = require("@std/syntax/printer")

function migration(ctx)
    local parsedResult = parser.parse(ctx.source)
    return printer.printfile(parsedResult)
end

return migration
```

A visitor mechanism is also available for basic AST traversal and modification.

```luau
local parser = require("@std/syntax/parser")
local printer = require("@std/syntax/printer")
local visitor = require("@std/syntax/visitor")

function migration(ctx)
    local parsedResult = parser.parse(ctx.source)

    local uppercaseVisitor = visitor.createVisitor()

    uppercaseVisitor.visitLocalReference = function(node)
        node.token.text = node.token.text:upper()
    end

    visitor.visitBlock(parsedResult.block, uppercaseVisitor)

    return printer.printfile(parsedResult)
end

return migration
```

For a more declarative approach, you can use a query-based select function:

```luau
local parser = require("@std/syntax/parser")
local printer = require("@std/syntax/printer")
local query = require("@std/syntax/query")

function migration(ctx)
    local parsedResult = parser.parse(ctx.source)

    local requireCalls = query.selectExpression(parsedResult.root, function(node)
        return isRequireCall(node)
    end)

    for _, call in requireCalls do
        call.arguments[1].node = convertToStringRequire(call.arguments[1])
    end

    return printer.printfile(parsedResult)
end

return migration
```

### Deleting a file

If the migration wishes to delete the file given, it should return the deletion marker, available at `codemod/lib/types.luau`

```luau
local driver = require("codemod/lib/types")

local function migration(ctx)
    if shouldDeleteFile(ctx.source) then
        return driver.DELETION_MARKER
    end

    -- ...
end
```

If the deletion marker is returned, the driver will defer deletion of the input script until after all files have been
processed. This is to allow require resolution to still work even if a file is to-be-deleted.

### Migration Configuration

More complex migrations may wish to allow configuration to control how the migration behaves.
To do so, the migration module can return a table instead of just a function. This table must contain a `transform`
function, and may contain an `options` table to parse particular flags:

```luau
local function migration(ctx)
    -- ...
end

return {
    options = {
        { name = "NAME", kind = "KIND", default = ... },
        ...
    },
    transform = migration
}
```

An option follows the following schema:

```luau
type MigrationOption =
    | { name: string, kind: "string", default: string? }
    | { name: string, kind: "boolean", default: boolean? }
```

It is the responsibility of the driver to ensure the options are parsed and provided to the migration. If a default is
specified, the flag is optional, otherwise it must be specified. Currently, only `string` and `boolean` configuration
are supported.

The resolved options are then made available as part of the migration context

```luau
type MigrationContext<Options = {}> = {
    path: string,
    source: string,
    options: Options
}
```

To use the options on the command line, they should be passed as flags after the migration module path, e.g.:

For the following migration:

```luau
type Options = {
    name: string,
    value: boolean
}


local function migration(ctx: MigrationContext<Options>)
    local name = ctx.options.name
    local value = ctx.options.value
    -- ...
end

return {
    options = {
        { name = "name", kind = "string" },
        { name = "value", kind = "boolean", default = true }
    }
    transform = migration,
}
```

The flags are passed as:

```
$ lute codemod/main.luau transform.luau --name STRING --value BOOLEAN <files...>
```

### Migration Initialization

Some migrations have initialization steps they wish to take before executing the migration on each file.
For example, this may include parsing and loading a sourcemap for require resolution, or installing a pre-requisite
dependency for the migration.

To do so, the migration module can return a table with an `initialize` function:

```luau
local function initialize(ctx)
    -- ...
end

local function migration(ctx)
    -- ...
end

return {
    options = {
        ...
    },
    initialize = initialize,
    transform = migration
}
```

The initialize function is executed once at the start by the driver, before the transform is applied on files.
