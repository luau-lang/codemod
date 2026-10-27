# Luau Codemods

A collection of code migrations (also known as codemods or transformations) for the [Luau](https://luau.org/)
programming language, along with the libraries that support them. Everything here is built on
[Lute](https://github.com/luau-lang/lute) and its syntax libraries.

> [!WARNING]
> The codemod driver in this repository (`main.luau`, along with its supporting `lib/arguments.luau`, `lib/files.luau`
> and `lib/ignore.luau`) is **deprecated**. Use Lute's built-in [`lute transform`](https://github.com/luau-lang/lute/blob/primary/docs/cli/transform.md)
> command to run codemods instead. The codemods in this repository are compatible with `lute transform` as-is.

## Contents

### Codemods

| Codemod | Description |
| --- | --- |
| [`flag-clipper`](./flag-clipper) | Removes references to a fast flag, simplifying the code as if the flag were always `true` or `false` |
| [`remove-unused`](./remove-unused) | Removes unused local variables and functions, e.g. those left behind after a flag cleanup |
| [`convert-instance-requires`](./convert-instance-requires) | Converts Roblox instance-based requires (`require(script.Parent.Module)`) to string requires (`require("./Module")`) |
| [`roundtrip.luau`](./roundtrip.luau) | Parses and reprints each file unchanged; useful for checking that the parser and printer preserve source exactly |

### Libraries

| Library | Description |
| --- | --- |
| [`require-resolver`](./require-resolver) | Detects `require` calls and resolves them to modules, using a Rojo sourcemap for instance-based requires |
| [`config-resolver`](./config-resolver) | Reads `.luaurc` files and resolves the require aliases that apply to a given file |
| [`lib`](./lib) | Shared utilities (paths, strings) and the deprecated driver's argument parsing, file discovery and ignore handling |

## Running a codemod

Install [Lute](https://github.com/luau-lang/lute), then clone this repository:

```sh
$ git clone https://github.com/luau-lang/codemod.git
```

Run a codemod with `lute transform`, passing the path to the codemod's `init.luau`, the files or directories to
transform, and then the codemod's options after a `--` separator:

```sh
$ lute transform codemod/flag-clipper/init.luau src/ -- --flag MyFlag --value true --sourcemap sourcemap.json
```

- The migration path must point at a file (e.g. `codemod/flag-clipper/init.luau`), not a directory.
- Directories are searched recursively for `.luau` and `.lua` files, honouring `.gitignore` files. If no files are
  given, the current directory is used.
- Codemod options are passed as `--name value` pairs after `--`. Boolean options take `true` or `false`.
- Use `--dry-run` to run without writing or deleting any files, `--interactive` (`-i`) to review a diff of each change
  before it is written, and `--output <path>` (`-o`) to write the result to a separate file when transforming a single
  file.

See each codemod's README for its options.

## Writing a codemod

A codemod is a Luau module that `lute transform` loads and applies to each file. In its simplest form, it returns a
function that takes a context and returns the new source code for the file:

```luau
local function transform(ctx)
    -- transform the provided ctx.source
    return ctx.source
end

return transform
```

The context has the following shape. Its type is available as `Context` from the `@transform` alias, which
`lute setup --with-luaurc` adds to the `.luaurc` in the current directory.

```luau
type Context<Options = { [any]: any }> = {
    path: string, -- The path to the file being transformed
    source: string, -- The source code of the file
    parseresult: syntax.CstParseResult, -- The parsed concrete syntax tree (CST) of the file
    options: Options, -- The parsed codemod options
}
```

A transform may return either the new source as a `string`, or a table of replacements mapping nodes of
`ctx.parseresult` to their new text. Lute then prints the file with those replacements applied.

### Query-based transforms

The CST in `ctx.parseresult` is immutable. For most codemods, the simplest approach is to select nodes with
`@std/syntax/query` and return replacements for them:

```luau
local query = require("@std/syntax/query")
local utils = require("@std/syntax/utils")

local function transform(ctx)
    return query.findAllFromRoot(ctx.parseresult, utils.isExprConstantNumber):replace(function(number)
        return `{number.value * 2}`
    end)
end

return transform
```

Visitors from `@std/syntax/visitor` can also be used to traverse the tree and build up a replacements table.

### Mutating the tree in place

Codemods that restructure code heavily, like `flag-clipper` and `remove-unused`, can instead parse a mutable tree with
`parseMutable` from `@lute/syntax/parser`, modify its nodes directly, and return the printed result:

```luau
local parser = require("@lute/syntax/parser")
local printer = require("@std/syntax/printer")
local visitor = require("@std/syntax/visitor")

local function transform(ctx)
    local parsedResult = parser.parseMutable(ctx.source)

    local uppercaseVisitor = visitor.create()

    uppercaseVisitor.visitExprLocal = function(node)
        node.token.text = node.token.text:upper()
        return true
    end

    visitor.visitBlock(parsedResult.root, uppercaseVisitor)

    return printer.printFile(parsedResult)
end

return transform
```

### Deleting a file

To delete the file being transformed, return the deletion marker, available as `DELETION_MARKER` from `@transform`:

```luau
local transformTypes = require("@transform")

local function transform(ctx)
    if shouldDeleteFile(ctx.source) then
        return transformTypes.DELETION_MARKER
    end

    -- ...
end
```

Deletions are deferred until all files have been processed, so require resolution still works for files that are about
to be deleted.

### Options and initialization

A codemod can return a table instead of a function. The table must contain a `transform` function, and may contain an
`options` list and an `initialize` function:

```luau
type Options = {
    name: string,
    value: boolean,
}

local function initialize(ctx: { options: Options })
    -- runs once, before any file is transformed
    -- e.g. parsing a sourcemap for require resolution
end

local function transform(ctx)
    local name = ctx.options.name
    local value = ctx.options.value
    -- ...
end

return {
    options = {
        { name = "name", kind = "string" },
        { name = "value", kind = "boolean", default = true },
    },
    initialize = initialize,
    transform = transform,
}
```

Options are either `string` or `boolean`. An option with a `default` is optional; any other option must be passed on
the command line:

```sh
$ lute transform transform.luau src/ -- --name STRING --value BOOLEAN
```

## Deprecated: the codemod driver

Before `lute transform` existed, codemods were run with this repository's driver:

```sh
$ lute codemod/main.luau ./flag-clipper --flag MyFlag --value true --sourcemap sourcemap.json src/
```

The driver accepts the same module shape (`transform`, `options` and `initialize`) and the same deletion marker, but
it does not provide `ctx.parseresult` and only accepts a `string` result. It resolves the codemod path relative to
`main.luau` rather than the working directory. It is no longer recommended, and may be removed in the future.

## Development

Tests are plain Lute scripts, run with `lute <path>`; see [`.github/workflows/ci.yml`](./.github/workflows/ci.yml) for
the full list. Code is formatted with [StyLua](https://github.com/JohnnyMorganz/StyLua) (`stylua --check .`).
