# Nu 0.114 Migration Reference

Use this reference when upgrading scripts to Nu 0.114+, reviewing code written
for an older release, or diagnosing behavior that may depend on the active Nu
version.

## Contents

- Establish the active version
- Type and control-flow changes
- Scripts, modules, and pipeline execution
- Commands, values, and data formats
- Errors, diagnostics, and validation

## Establish the Active Version

From any shell, prefer the direct CLI check:

```console
nu --version
```

When already inside Nushell or when structured version data is needed, use:

```nu
version | get version
```

Confirm the project-supported version before rewriting working compatibility
code. For broader command-level changes, also read the command behavior notes
in [Advanced Patterns](../advanced-patterns.md).

## Type and Control-Flow Changes

- Optional positional parameters and typed named options without defaults are
  `oneof<T, nothing>`. Boolean switch flags remain `bool`.
- `if` without `else` and `match` without `_` may return `nothing`; provide a
  fallback when the surrounding signature requires a non-null value.
- Runtime assignment annotations are enforced by default.
- Declare mutable bindings with `mut name[: type] = value`; `let mut` is not
  valid Nushell syntax.
- A bare negative number in command-argument position can be parsed as a flag.
  Wrap it as an expression (`default (-1)`) or use `default -- -1` when the
  command supports the POSIX-style separator.
- Homogeneous arrays of records loaded from JSON commonly describe as
  `table<...>`, even though tables remain list-like. Use a typed `list`
  parameter when both lists and tables should be accepted, or inspect the
  structured result of `describe --detailed`.

```nu
def maybe-add [value?: int]: nothing -> int {
  ($value | default 0) + 1
}

mut errors: list<string> = []
```

See [Data & Type System](../data-and-types.md) for unions, collection types,
runtime annotations, and null-safe `default` patterns.

## Scripts, Modules, and Pipeline Execution

- Exported submodules are not imported implicitly. Re-export the intended
  namespace with `export use sub`, or flatten it deliberately with
  `export use sub *`.
- Use `run` when a script should act as an isolated pipeline stage. The target
  file must exist when the calling block is parsed.
- Use `run --full-reparse script.nu` when the script can change between
  invocations, such as watch loops or tests that regenerate the file.
- Keep pipeline input in the command's input/output signature. It is not a
  substitute for a positional parameter, and streams may be single-pass.

See [Modules & Scripts](../modules-and-scripts.md) for module exports, `main`,
parse-time resolution, pipeline scripts, and test seams.

## Commands, Values, and Data Formats

- Use `into semver`, `into semver-range`, and `semver bump` instead of lexical
  sorting or manual version splitting.
- Use `str uppercase` and `str lowercase`; `str upcase` and `str downcase` are
  deprecated.
- `from xlsx` and `from ods` return records of sheet tables. Use
  `--noheaders`, `--first-row`, and `--prefer-integers` instead of removed
  header flags.
- Nu 0.114 supports POSIX-style `--` for builtins and ordinary custom commands.
  Wrapped commands and known externs preserve or forward it to rest arguments.

```nu
['1.10.0' '1.2.0'] | each { into semver } | sort
'1.2.3' | into semver | semver bump minor
open workbook.xlsx | get Sheet1
```

## Errors, Diagnostics, and Validation

- In `catch`, structured diagnostics live at `$err.details`; `$err.json` was
  removed.
- Prefer structured `try/catch` assertions for in-process tests.
- Rendered errors from nested `nu ... | complete` calls are presentation text.
  ANSI styling, diagnostic gutters, and PTY wrapping make raw or contiguous
  substring assertions unstable. Normalize both values and match a long,
  domain-specific phrase when testing a CLI boundary.

Validate migrations narrowly before running the full suite:

```console
nu -c 'source path/to/module.nu'
nu path/to/test-script.nu
```

When diagnostics or tables are involved, repeat the focused regression under a
narrow PTY, for example `stty cols 24 && nu tests/example.nu`.

For implementation patterns, continue with [Advanced Patterns](../advanced-patterns.md)
and [Modules & Scripts](../modules-and-scripts.md). For a migration-focused review,
use [Anti-Patterns](../anti-patterns.md) and [Script Review](../script-review.md).
