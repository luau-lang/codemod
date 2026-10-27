# Flag Clipper Codemod

Codemod to clean up references of a FFlag, either with a value of true or false

## Usage

Follow the main [README](../README.md) instructions for how to install Lute and run codemods with `lute transform`

```
$ lute transform codemod/flag-clipper/init.luau <files...> -- --flag <name> --value <true> --sourcemap <path>
```

Options:

- `--flag <name>`: the name of the FFlag to clear up
- `--value true` / `--value false`: How to interpret the FFlag value. If not specified, defaults to `true`
- `--sourcemap <path>`: path to a sourcemap file to support require resolution. Necessary for resolving instance-based requires
