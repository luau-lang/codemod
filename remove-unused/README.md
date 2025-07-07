# Convert Instance Requires Codemod

A codemod to remove unused variables based on selene linting rules.

## Usage

Follow the main [README](../README.md) instructions for how to install the codemod driver

```
$ lute codemod/main.luau ./codemod/remove-unused --selen <path> <files...>
```

Options:

- `--selene <path>`: path to a selene toml file so variable removal respects files excluded from linting.