# Nushell Script Review Checklist

Comprehensive checklist for reviewing Nushell scripts. Check items in order of priority.

## Contents

- [Review method](#review-method)
- [Security](#1-security-critical)
- [Correctness](#2-correctness)
- [Style and idiom](#3-style--idiom)
- [Performance](#4-performance)
- [Robustness](#5-robustness)
- [Review workflow](#review-workflow)

---

## Review Method

Before listing findings:

1. Read the repository instructions, supported Nu versions, changed files, and
   relevant call sites/tests. A local `nu --version` is evidence about the test
   environment, not necessarily the project's compatibility target.
2. Summarize the script's entry points, pipeline contracts, external inputs,
   side effects, and trust boundaries. Follow changed helpers into their callers
   when the bug depends on a wider data flow.
3. Run the narrowest safe check that can falsify a suspected issue. Prefer a
   minimal Nu 0.115 reproduction for version-sensitive semantics, then run the
   project's focused test.
4. Separate blocking correctness/security defects from migration notes,
   maintainability suggestions, and measured performance opportunities.
5. If no actionable defect remains, say so and identify any validation gap or
   compatibility version that was not available.

### Finding quality

Each finding should contain:

- A severity (`P0` critical, `P1` high, `P2` medium, or `P3` low) based on
  impact and likelihood, not how easy the fix is.
- A concise title and the smallest useful `file:line` location.
- The concrete input/state that triggers it, the observable impact, and why the
  current tests do not prevent it.
- Evidence from the language contract, command signature, minimal reproduction,
  or focused test. Mark version-dependent conclusions explicitly.
- A focused repair direction; do not require unrelated refactoring.

Do not report speculative failures that cannot be connected to a reachable
input, stylistic preferences already enforced by project tooling, or behavior
that changed in the supported Nu version without first reproducing it.

---

## 1. Security (Critical)

### Code injection

- [ ] No `nu -c $variable` with untrusted input
- [ ] No `source $variable` with runtime paths (must be `const`)
- [ ] No `run` of untrusted `.nu` script paths; `run` targets must be parse-time constants
- [ ] No `^sh -c`, `^bash -c`, or `^cmd.exe /C` with interpolated user input
- [ ] No `run-external` with user-controlled command names
- [ ] `external_arg` values are treated as untrusted raw tokens, not as
      sanitized strings or safe paths/patterns

### Path safety

- [ ] Existing user-provided paths validated with strict expansion + `path relative-to`; no string-prefix containment checks
- [ ] No raw `open $user_input` without path traversal guard
- [ ] `..` sequences in user paths detected and rejected
- [ ] Base directory enforcement for file operations

### Credential handling

- [ ] No hardcoded secrets in source code
- [ ] Credentials scoped with `with-env`, not set on `$env` directly
- [ ] Secrets read from files/stdin, not passed as command-line arguments
- [ ] No credentials logged via `print` or written to non-secure files

### Destructive operations

- [ ] `rm` operations validate target path (not `/`, not `$nu.home-dir`)
- [ ] Glob patterns from user input are validated (no unintended expansion)
- [ ] `--depth` limits on `glob` to prevent DoS on large trees

### Temp files

- [ ] Temp files created with built-in `mktemp`, not predictable paths
- [ ] Temp files cleaned up in `try/catch` or equivalent
- [ ] Temp directories use `mktemp --directory`

### Environment safety

- [ ] `$env.PATH` not modifiable by untrusted input
- [ ] Dangerous env vars (`LD_PRELOAD`, `DYLD_INSERT_LIBRARIES`) cleared before running untrusted commands
- [ ] `with-env` used for scoped environment changes in security-sensitive contexts

---

## 2. Correctness

### Type safety

- [ ] All exported commands have type annotations on parameters
- [ ] I/O pipeline signatures (`]: type -> type {`) match actual behavior
- [ ] Complex types use proper syntax: `record<name: string>`, `list<int>`, `table<col: type>`
- [ ] Optional parameters use `?` suffix: `name?: string`
- [ ] Optional params and typed named options without defaults are handled as `oneof<T, nothing>`; boolean switch flags remain `bool`
- [ ] Rest parameters typed: `...args: string`
- [ ] Runtime assignment annotations are valid under Nu 0.114's default `enforce-runtime-annotations`
- [ ] `external_arg` is used only where raw CLI token spelling matters; values
      are converted/validated before structured use
- [ ] No command/module/export shadows a parser keyword, and no binding uses
      reserved `ans` on Nu 0.115+

### Error handling

- [ ] Fallible operations wrapped in `try/catch`
- [ ] External commands checked with `complete` when exit code matters
- [ ] Tests do not assert raw nested-Nu diagnostics without normalizing ANSI, PTY wrapping, and `|` gutters
- [ ] `catch` blocks include meaningful error context (not empty)
- [ ] `finally` used for cleanup side effects, not as the returned value
- [ ] `catch` blocks read `$err.details` for structured diagnostics, not removed `$err.json`
- [ ] Custom errors include `label` with `span` for good error messages
- [ ] No bare `error make {msg: '...'}` without span when metadata is available
- [ ] Nu 0.115 labels use `{text: ..., span: {start: ..., end: ...}}`, not flat
      `{text, start, end}` records
- [ ] No `try/finally` is nested directly inside an outer `try` whose handler is
      `catch`; on Nu 0.115.0 the inner `finally` is silently skipped, so cleanup
      needs an outer `finally` or a `do`/command boundary

### Null safety

- [ ] Optional record fields accessed with `?`: `$rec.field?`
- [ ] `default` used for fallback values: `$val | default 'N/A'`
- [ ] No bare field access on records from external/untrusted sources
- [ ] `$in` captured early with `let` when used multiple times
- [ ] `group-by` uses `--to-table` when null groups must survive or remain
      distinct from empty strings

### Logic correctness

- [ ] `for` not used as final expression (returns null, use `each`)
- [ ] `mut` variables not captured in closures (will error)
- [ ] `source`/`use` paths are `const`, not `let`
- [ ] Long `if`/`else if` chains on one value prefer `match` unless `if` is clearer
- [ ] `if`/`match` expressions have `else`/`_` fallbacks when a non-null output is required
- [ ] `each` not used on single records (use `items` or `transpose`)
- [ ] `parse` gets `lines` first when line-by-line parsing of stream input is intended
- [ ] Correct operator: `>` in non-pipeline context is comparison, not redirect
- [ ] Multiline custom command calls with named flags are one-line or wrapped in parentheses
- [ ] SemVer logic uses `into semver`, direct comparison on Nu 0.115 (including
      the 0.115.0 bool-context inference workaround when required),
      `into semver-range`, or `semver bump`, not string surgery
- [ ] `take while/until --include` has boundary tests for include counts zero,
      one, and greater than one when off-by-one behavior matters

### Data-format contracts

- [ ] Namespace-sensitive XML does not rely on `from xml` records: element and
      attribute prefixes/URIs are dropped, and attributes such as `id` and
      `r:id` collide with the later value winning (verified on Nu 0.115.1)
- [ ] YAML call sites pin `--spec` when upstream YAML 1.1/1.2 semantics matter
- [ ] `from yaml --multiple` produces a stable expected shape (`list` or
      `single`) at API boundaries instead of relying unintentionally on `auto`
- [ ] Non-string YAML keys and unknown tags are rejected or explicitly handled;
      `--key-resolution verbatim` / `--ignore-tags` are not used as validation
- [ ] `to yaml` non-round-trip handling is deliberate, and golden tests compare
      semantics unless exact formatting is the contract
- [ ] `--non-roundtrip` values are quoted (`'null'`); bare `null` is a parse
      error and `to yaml --non-roundtrip 'lossy'` is rejected on 0.115.0
- [ ] YAML call sites that read colon-bearing scalars (`HH:MM:SS`, IDs) account
      for the 1.1 sexagesimal / 1.2 string split
- [ ] KDL spec and `nodes`/`jik` format are pinned when files cross a system
      boundary

### External commands

- [ ] External commands prefixed with `^` when name conflicts with builtins
- [ ] `find` (Nushell builtin) vs `^find` (Unix) distinction maintained
- [ ] `sort` (Nushell builtin) vs `^sort` (Unix) distinction maintained
- [ ] Arguments to external commands separated (not concatenated strings)
- [ ] Format strings passed to external commands use double quotes for simple escapes, or `char tab` / `char nl` when interpolation is needed
- [ ] CLI tests use real fixtures rather than removed `nu --testbin` on Nu
      0.115+

---

## 3. Style & Idiom

### Naming

- [ ] Commands: `kebab-case` (`fetch-user`, not `fetchUser` or `fetch_user`)
- [ ] Variables/params: `snake_case` (`$user_id`, not `$userId`)
- [ ] Env vars: `SCREAMING_SNAKE_CASE` (`$env.APP_VERSION`)
- [ ] Flags: `kebab-case` (`--output-dir`, not `--output_dir`)
- [ ] Full words preferred (`$user_name`, not `$usr_nm`)

### String format priority

- [ ] Bare words in arrays: `[foo bar]` not `["foo" "bar"]`
- [ ] Single quotes for simple strings: `'hello'` not `"hello"`
- [ ] Single-quoted interpolation preferred: `$'val: ($x)'` not `$"val: ($x)"`
- [ ] Strings needing a **literal** `(` use `$"...\(..."`, never `$'...'` — in
      `$'...'` the paren always opens an expression and `\(` does not escape it
- [ ] Double quotes only when escape sequences needed: `"\n"`, `"\t"`
- [ ] Raw strings for regex: `r#'pattern'#`
- [ ] `str uppercase` / `str lowercase` used instead of deprecated `str upcase` / `str downcase`

### Pipeline & functional style

- [ ] Pipelines preferred over imperative loops
- [ ] `$items | get price | math sum` instead of `mut total; for ...`
- [ ] `ls | where size > 1mb` instead of manual filtering
- [ ] `enumerate` instead of manual index counters
- [ ] `reduce` instead of `mut` accumulator + `for`
- [ ] `match` preferred for multi-branch dispatch on a single value
- [ ] Simple `any`/`all` predicates may use Nu 0.115 row conditions; closures
      remain when they improve scope clarity or support older Nu versions

### Formatting

- [ ] No space before `|params|` in closures: `{|x| ...}` not `{ |x| ...}`
- [ ] Spaces around pipe: `cmd | cmd` not `cmd|cmd`
- [ ] Commas omitted in lists: `[1 2 3]` not `[1, 2, 3]`
- [ ] One space after `:` in records: `{x: 1}` not `{x:1}`
- [ ] Multi-line format for expressions >80 chars

### Documentation

- [ ] Exported commands have `#` comment above `def`
- [ ] Parameter descriptions as inline `#` comments
- [ ] `@example` attributes for non-trivial commands
- [ ] `@category` for organization when applicable

### Modules

- [ ] Only necessary definitions are `export`-ed
- [ ] `export def main` used when command matches module name
- [ ] Submodules are re-exported explicitly when callers need the submodule namespace in Nu 0.114+
- [ ] Private helpers are not exported
- [ ] `export-env` for environment setup blocks

---

## 4. Performance

### Parallelism

- [ ] `par-each` is suggested only for independent work with safe concurrency;
      ordering, rate limits, shared state, and side effects are accounted for
- [ ] `--threads` is bounded when resource usage or service limits matter
- [ ] Performance findings include a scale argument or measurement; do not flag
      every sequential `each` mechanically

### Streaming & memory

- [ ] `each --flatten` for streaming nested results
- [ ] Large files not loaded entirely when streaming suffices
- [ ] `lines` + pipeline for line-by-line processing of large files
- [ ] Nu 0.115 lazy `lines` output is not collected unless random access or
      repeated traversal requires materialization
- [ ] `peek` used for stream metadata/sample inspection instead of collecting
- [ ] `first N` / `take while` to limit processing early
- [ ] Binary byte windows use `filesize` counts (`first 16b`, `chunks 10MiB`)
      where this makes units and boundaries clearer

### Caching & computation

- [ ] Expensive results cached in `let` bindings, not recomputed
- [ ] `glob` with `--depth` to avoid scanning huge trees
- [ ] Built-in commands preferred over external for small data
- [ ] External tools (`^rg`, `^jq`) used for large-scale operations

---

## 5. Robustness

### Input validation

- [ ] Parameter types annotated (catches misuse at parse time)
- [ ] Range/value checks at function entry for critical params
- [ ] User-facing commands validate inputs before processing
- [ ] Consistent return types (don't mix null and value unexpectedly)

### File operations

- [ ] `path exists` checked before `open` when file may not exist
- [ ] `save --force` used intentionally (overwrites without warning)
- [ ] File encoding handled appropriately (`open --raw` for binary)
- [ ] Structured output uses a recognized extension or an explicit `to ...`
      serializer before `save`
- [ ] Empty input is rejected before `path type`; Nu 0.115 returns `null` for
      `'' | path type`
- [ ] `from xlsx` / `from ods` output handled as a record of sheet tables
- [ ] Spreadsheet imports use `--noheaders`, `--first-row`, or `--prefer-integers` instead of removed `--header-row`
- [ ] `mkdir -v` / `mv -v` / `rm -v` outputs treated as tables, not parsed text
- [ ] `rm` / `mkdir` partial-success behavior considered when multiple paths are passed

### Process management

- [ ] Long-running external processes have timeouts or cancellation
- [ ] Background jobs (`job spawn`) tracked and cleaned up
- [ ] Exit codes checked for critical external commands

### Tests and compatibility

- [ ] Generated scripts are checked before their first real side effects;
      `nu-check --debug` is the default, with `--as-module` only for modules
- [ ] A plain `nu-check` boolean is consumed; exit `0` alone cannot prove it passed
- [ ] `source` is used for intentional execution/loading, never as a parse-only check
- [ ] Generated messages/payloads have output or consumer round-trip assertions;
      valid but unintended interpolation can pass every parser check
- [ ] Tests cover success, invalid input, boundary values, and external-command
      failure for changed behavior
- [ ] Side-effecting tests use isolated temp fixtures and assert after the
      `try`/`finally` that the owned state is gone, or record partial-success
      state explicitly
- [ ] Version-sensitive tests run on the project's lowest supported Nu version
      as well as the current target when compatibility is claimed
- [ ] `--ide-check` JSON Lines are parsed for error diagnostics; exit code `0`
      and empty output are not accepted blindly
- [ ] On Nu 0.115+, `scope commands` `deprecation_info` is used to confirm
      deprecations instead of relying only on memory or rendered help text; it
      is a table, so read a single command's entry as `deprecation_info.0`

---

## Review Workflow

1. **Establish scope and versions** — Read instructions, diff, callers, tests,
   and supported Nu range.
2. **Model data and trust flow** — Trace entry points, types, paths, external
   processes, serialization, and side effects.
3. **Security pass** — Check Section 1 systematically.
4. **Correctness and migration pass** — Verify types, null handling, errors,
   data-format contracts, process status, and 0.114/0.115 behavior.
5. **Robustness and tests pass** — Exercise boundary/failure paths and cleanup.
6. **Maintainability/performance pass** — Report only actionable, non-tooling
   issues and performance claims with a scale argument or measurement.
7. **Falsify and rank findings** — Reproduce version-sensitive claims, remove
   false positives, then report by severity with precise locations.
