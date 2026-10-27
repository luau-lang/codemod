# Convert Instance Requires Codemod

A codemod to convert from Roblox instance-based requires (`require(script.Parent.Module)` / `require(game.ReplicatedStorage.Module)`)
to Luau string based requires (`require("./Module")`)

## Usage

Follow the main [README](../README.md) instructions for how to install Lute and run codemods with `lute transform`

```
$ lute transform codemod/convert-instance-requires/init.luau <files...> -- --sourcemap <path>
```

Options:

- `--sourcemap <path>`: path to a sourcemap file to support require resolution. Necessary for resolving instance-based requires
