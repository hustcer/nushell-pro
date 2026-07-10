---
name: nushell-pro
description: |
  Comprehensive Nushell scripting best practices, idioms, security, and code review. Use when writing, reviewing, auditing, debugging, or refactoring Nushell (.nu) scripts, modules, custom commands, pipelines, and tests. Also use for Bash/POSIX-to-Nushell conversion and Nu 0.114+ migration issues such as stricter type checking, `run`, SemVer, optional `nothing`, subprocess diagnostics, and explicit submodule imports.
---

# Nushell Pro

Write secure, idiomatic, portable, and testable Nushell. Keep the main workflow
in this file; load detailed references only when the task needs them.

## Operating Workflow

1. Identify the task: new script, debugging, review, refactor, module design,
   migration, performance work, security audit, or Bash conversion.
2. Read the target `.nu` files, nearby tests, `AGENTS.md`, and existing project
   conventions before changing code.
3. Confirm the active version for version-sensitive behavior:

   ```nu
   version | get version
   ```

4. Load the smallest relevant reference set:

   | Task                                                 | Reference                                              |
   | ---------------------------------------------------- | ------------------------------------------------------ |
   | String quoting, interpolation, regex, globs          | [String Formats](references/string-formats.md)         |
   | Security, paths, credentials, destructive operations | [Security](references/security.md)                     |
   | Script/code review                                   | [Script Review](references/script-review.md) and [Anti-Patterns](references/anti-patterns.md) |
   | Bash/POSIX conversion                                | [Bash to Nushell](references/bash-to-nushell.md)       |
   | Modules, exports, scripts, tests                     | [Modules & Scripts](references/modules-and-scripts.md) |
   | Types, records, lists, conversions                   | [Data & Type System](references/data-and-types.md)     |
   | Streaming, closures, performance, diagnostics        | [Advanced Patterns](references/advanced-patterns.md)   |
   | Large columnar data                                  | [Dataframes](references/dataframes.md)                 |
   | Common mistakes                                      | [Anti-Patterns](references/anti-patterns.md)           |

5. Apply the critical checks below before style or performance cleanup.
6. Validate with the narrowest safe command, then run the relevant tests.
7. Report security/correctness findings before style and performance notes.

If a referenced file is unavailable, say so and continue with this file rather
than inventing its contents.

## Critical Nu 0.114+ Semantics

- Optional positional parameters and typed named options without defaults are
  `oneof<T, nothing>`. Boolean switch flags remain `bool`.
- `if` without `else` and `match` without `_` may return `nothing`; add a
  fallback when the surrounding signature requires a non-null value.
- Runtime assignment annotations are enforced by default.
- Exported submodules are not imported implicitly; re-export the intended
  namespace with `export use sub` or flatten deliberately with
  `export use sub *`.
- Use `run` for isolated pipeline scripts. The file must exist at parse time;
  use `run --full-reparse` in watch/repeated-run workflows.
- Use `into semver`, `into semver-range`, and `semver bump` instead of lexical
  sorting or manual version splitting.
- Use `str uppercase` and `str lowercase`; the old case-conversion commands are
  deprecated.
- `from xlsx` and `from ods` return records of sheet tables. Use
  `--noheaders`, `--first-row`, and `--prefer-integers` instead of removed
  header flags.
- In `catch`, structured diagnostics live at `$err.details`; `$err.json` is
  removed.

## Pipeline Input Is Not a Parameter

Declare pipeline input in the I/O signature. Parameters and `$in` have different
calling and evaluation semantics.

```nu
# Wrong: caller must pass the list as a positional argument.
def append-value [items: list, value: any] {
  $items | append $value
}

# Correct: caller pipes the list.
def append-value [value: any]: list -> list {
  $in | append $value
}

[1 2 3] | append-value 4
```

Capture `$in` once when it must be reused because streams can be single-pass.

## Type and Null Safety

- Type exported command parameters and I/O signatures.
- Treat external/config records as untrusted; use optional access such as
  `$record.field?` and validate the resulting type/value.
- Remember that `default` evaluates its fallback argument eagerly. Make the
  fallback null-safe or branch explicitly when it can fail or is expensive.
- Keep return types consistent. Avoid `any` unless the function is genuinely
  polymorphic.
- Prefer `match` for several branches on one value; use `if` for one-off boolean
  predicates.

```nu
def maybe-add [value?: int]: nothing -> int {
  ($value | default 0) + 1
}

# The fallback itself is null-safe.
$primary | default ($record.secondary? | default 0)
```

## External Commands and Errors

Pass arguments separately and use `complete` when exit status matters.

```nu
let result = (^cargo build | complete)
if $result.exit_code != 0 {
  error make {msg: $'Build failed: ($result.stderr)'}
}
```

Do not treat rendered Nushell diagnostics as a stable machine format. Nested
`nu ... | complete` errors contain ANSI styling and `|` gutters, and Nu hard-wraps
them according to the caller's PTY width, including inside words. Prefer direct
`try/catch` and `$err.details` when testing in-process behavior. When a CLI
integration test must inspect rendered `stderr`, normalize both actual and
expected text before matching:

```nu
use std/assert

def diagnostic-text [value: any]: nothing -> string {
  $value
  | into string
  | ansi strip
  | str replace --all --regex r#'[\s|]+'# ''
}

def assert-diagnostic-contains [value: any, expected: string] {
  assert str contains (diagnostic-text $value) (diagnostic-text $expected)
}
```

Use a long, domain-specific expected phrase so normalization does not weaken the
assertion into a generic substring check.

## Security Stop Checkpoint

Before approving code that executes commands, deletes files, reads credentials,
or accepts paths/patterns, confirm these boundaries:

- Never pass untrusted strings to `nu -c`, `source`, `run`, `^sh -c`,
  `^bash -c`, or `^cmd.exe /C`.
- Pass external command arguments as separate values, not an interpolated shell
  command string.
- For existing paths restricted to a base directory, expand both paths and use
  `path relative-to` to prove containment. A string `starts-with` check is
  unsafe because `/safe/base2` starts with `/safe/base`.
- Prefer Nu's built-in `mktemp`/`mktemp --directory`; it is portable and returns
  a path directly. Do not use predictable temp names.
- Scope secrets with `with-env`; do not log them or pass them in argv when a
  stdin/config-file mechanism exists.
- Guard destructive paths against root, `$nu.home-dir`, unexpected types, and
  untrusted globs. Consider TOCTOU and partial-success behavior.

```nu
def safe-open [name: string, --base-dir: path = '.'] {
  let base = $base_dir | path expand --strict
  let full = ($base | path join $name | path expand --strict)
  try {
    $full | path relative-to $base | ignore
  } catch {
    error make {msg: $'Path escapes base directory: ($name)'}
  }
  open $full
}

let tmp_file = mktemp --suffix .json
let tmp_dir = mktemp --directory
```

For output paths that do not exist yet, validate the existing parent directory
with the same containment rule, then join only a validated leaf name.

## Strings and Formatting

Choose string forms in this order:

1. Bare words in data contexts: `[foo bar baz]`
2. Raw strings for regex or heavy quoting: `r#'\d+'#`
3. Single quotes for ordinary literals: `'hello world'`
4. Single-quoted interpolation without escapes: `$'Hello ($name)'`
5. Backticks for path/glob arguments containing spaces
6. Double quotes only for actual escapes: `"line1\nline2"`
7. Double-quoted interpolation only when interpolation and escapes are both
   required

Non-negotiable details:

- `$'...'` does not process `\n`, `\t`, or `\'`.
- Do not build command strings for execution.
- Use raw regex strings to keep backslashes auditable.
- Keep short custom-command calls with named flags on one line. Wrap the whole
  invocation in `(...)` when flags span lines.
- Use kebab-case for commands/flags, snake_case for variables/parameters, and
  SCREAMING_SNAKE_CASE for environment variables.

## Idiomatic Data Flow

- Prefer pipelines and immutable `let` bindings.
- Use `where`, `select`, `update`, `insert`, `items`, `transpose`, `reduce`, and
  `enumerate` instead of manual parsing and mutable accumulation.
- Do not capture `mut` variables in closures.
- `for` is appropriate for sequential side effects but is not a transforming
  expression; use `each` when a list result is required.
- Use `par-each` only when concurrency is safe and beneficial; preserve `each`
  when order or sequential side effects matter.
- Add `lines` before `parse` when line-by-line stream parsing is intended.
- Use native tables for small interactive data and Polars for large columnar
  group-by/join/aggregation workloads.

## Modules and Scripts

- Export only the intended API; keep helpers private.
- Use `export def main` when the command should match the module name.
- Use `def --env`/`export def --env` for caller-visible environment changes.
- `source`, `use`, and `run` targets must be trusted and available at parse time.
- Test at the correct seam: direct functions for stable structured errors, CLI
  subprocesses for argument parsing/process boundaries, and both when needed.

## Review Order

When reviewing code, report findings in this order:

1. Security: injection, traversal, credentials, destructive operations, temp
   files, environment poisoning.
2. Correctness: types, null handling, parse-time constraints, exit codes,
   cleanup/rollback, platform behavior, stable tests.
3. Maintainability: naming, module boundaries, duplication, documentation.
4. Performance: streaming, unnecessary collection, safe parallelism, Polars.

Skip issues already enforced by the project's formatter/linter unless the tool
output shows they are currently failing.

## Validation

Use the narrowest safe commands first:

```bash
nu -c 'source path/to/module.nu'
nu path/to/test-script.nu
```

- For scripts with side effects, source/parse-check them or run against a temp
  fixture.
- Reproduce terminal-sensitive tests under a narrow PTY when diagnostics or
  tables are involved, for example `stty cols 24 && nu tests/example.nu`.
- Check diffs for debug markers and accidental changes before finishing.
- If validation fails, fix the smallest reproducible issue and rerun the exact
  failing command before broadening the test suite.

## Detailed References

- [String Formats](references/string-formats.md)
- [Security](references/security.md)
- [Script Review](references/script-review.md)
- [Bash to Nushell](references/bash-to-nushell.md)
- [Modules & Scripts](references/modules-and-scripts.md)
- [Data & Type System](references/data-and-types.md)
- [Advanced Patterns](references/advanced-patterns.md)
- [Dataframes](references/dataframes.md)
- [Anti-Patterns](references/anti-patterns.md)
