# NeoHScript for VS Code

VS Code extension for NeoHScript (`.hxs`), written in Haxe and compiled to JavaScript. It reuses the `neohscript` library from `../neohscript`, so the editor and your game see exactly the same analysis.

## Features

| Feature | Details |
|---|---|
| Diagnostics | Every syntax error and analyzer problem at once, with exact ranges; unused code and inactive `#if` regions are dimmed |
| Hover | Types, signatures (including generics) and JSDoc for variables, functions, members, classes, enums, imports and host symbols |
| Completion | Visible symbols, members after `.` by type (including `this`), host globals, classes and enums, type names after `:` and `new`, import paths, snippets and keywords |
| Auto-import | Symbols from other modules and host packages appear in completion and insert the `import` line automatically |
| Signature help | Function, method and constructor signatures with per-parameter docs |
| Navigation | Go to definition (across modules, into host `.hx` sources and JSON definitions), find references (workspace-wide), document highlights, document and workspace symbols, folding |
| Rename | Local symbols, exported module symbols and class members, across files; host symbols are rejected |
| Quick fixes | Import a missing name, remove unused declarations and imports, prefix unused parameters with `_`, add `override`, add missing `switch` cases, add an inferred type annotation |
| Inlay hints | Inferred types and parameter names |
| Semantic tokens | Parameters, variables, properties, methods, classes, enums, enum members, namespaces and modifiers |
| Formatting | Indentation, blank lines and trailing whitespace; respects tabs or spaces |
| Highlighting | TextMate grammar with JSDoc, interpolation, preprocessor and all declarations |
| JSON validation | Schema for `neohscript.types.json` and `neohscript.generated.json` |
| Commands | `NeoHScript: Reload type definitions`, `NeoHScript: Generate API documentation` |

## Modules and imports

`import util.Strings;` resolves to `util/Strings.hxs` under a source root (`neohscript.sourceRoots`, default: the workspace root). All `.hxs` files in the workspace are indexed, open editors override files on disk, and dependents are re-analyzed when a module changes.

## Host type definitions

Place `neohscript.types.json` and/or `neohscript.generated.json` in the workspace (the second one is produced by `Bridge.expose` from your Haxe classes). Other files can be added with `neohscript.definitions`. Definitions reload automatically and problems are reported in the JSON file.

## Settings

| Setting | Default | Description |
|---|---|---|
| `neohscript.definitions` | `["neohscript.types.json", "neohscript.generated.json"]` | Workspace glob patterns of definition files |
| `neohscript.globals` | `["print", "Math", "Std"]` | Untyped host globals |
| `neohscript.analysis.strictness` | `basic` | `off`, `basic` or `strict` (null safety and enforced inferred types) |
| `neohscript.sourceRoots` | `[""]` | Workspace-relative roots for module paths |
| `neohscript.defines` | `[]` | Defines for `#if` |
| `neohscript.inlayHints.types` | `true` | Show inferred types |
| `neohscript.inlayHints.parameters` | `true` | Show parameter names at call sites |

## Build and package

```
haxelib install vscode
haxe build.hxml
npx @vscode/vsce package
```

Press F5 with this folder open to launch a development host. To try the features, open `../neohscript/examples/modules` (imports, generics, enums, interfaces) or `../neohscript/examples/host` (host classes generated from Haxe) in the development window.

## Notes

- Parsing and analysis recover from errors, so every feature keeps working on incomplete code while you type.
- Positions of host members come from the `source` entries written by `Bridge.expose`; without them, go to definition on host members is unavailable.
- Requires VS Code 1.80 or newer.
