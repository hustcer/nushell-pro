---
name: nushell-pro
description: |
  Comprehensive Nushell scripting best practices, idioms, security, and evidence-driven code review. Use when writing, reviewing, auditing, debugging, or refactoring Nushell (.nu) scripts, modules, custom commands, pipelines, config, and tests. Also use for Bash/POSIX-to-Nushell conversion and Nu 0.114/0.115 migration issues such as stricter types, YAML 1.2, `external_arg`, `run`, SemVer, optional `nothing`, subprocess diagnostics, and explicit submodule imports.
---

# Nushell Pro

Write secure, idiomatic, portable, and testable Nushell. Keep the main workflow
in this file; load detailed references only when the task needs them.

## Operating Workflow

1. Identify the task: new script, debugging, review, refactor, module design,
   migration, performance work, security audit, or Bash conversion.
2. Read the target `.nu` files, nearby tests, `AGENTS.md`, and existing project
   conventions before changing code.
3. Establish both the project's supported Nu range (from CI, documentation, or
   project configuration) and the active local version. Do not assume the local
   binary defines the compatibility target. Prefer the official English docs;
   translations can lag. When local docs/source checkouts are available, inspect
   them and record their revision separately from the installed Nu version.
   From any shell, prefer:

   ```console
   nu --version
   ```

   When already inside Nushell or when structured version data is needed, use:

   ```nu
   version | get version
   ```

4. Load the smallest relevant reference set:

   | Task                                                 | Reference                                                                                     |
   | ---------------------------------------------------- | --------------------------------------------------------------------------------------------- |
   | Nu 0.115 migration, YAML, CLI args, command changes  | [Nu 0.115 Migration](references/nu-0.115-migration.md)                                        |
   | Nu 0.114 migration and version compatibility         | [Nu 0.114 Migration](references/nu-0.114-migration.md)                                        |
   | Strings, regex/globs, generated JS/JSON              | [String Formats](references/string-formats.md)                                                |
   | Security, paths, credentials, destructive operations | [Security](references/security.md)                                                            |
   | Script/code review                                   | [Script Review](references/script-review.md) and [Anti-Patterns](references/anti-patterns.md) |
   | Bash/POSIX conversion                                | [Bash to Nushell](references/bash-to-nushell.md)                                              |
   | Modules, exports, scripts, tests                     | [Modules & Scripts](references/modules-and-scripts.md)                                        |
   | Daemons, background jobs, E2E smoke tests            | [Daemon & E2E Smoke Tests](references/daemon-and-e2e-smoke-tests.md)                          |
   | Types, records, lists, conversions                   | [Data & Type System](references/data-and-types.md)                                            |
   | Streaming, closures, performance, diagnostics        | [Advanced Patterns](references/advanced-patterns.md)                                          |
   | Large columnar data                                  | [Dataframes](references/dataframes.md)                                                        |
   | Common mistakes                                      | [Anti-Patterns](references/anti-patterns.md)                                                  |

5. Apply the cross-cutting guardrails below before style or performance cleanup.
6. Before a generated script's first real run, use `nu-check --debug` in the
   intended scope. Assert exact output for tricky strings/serialized payloads,
   then run the relevant tests; parsing alone cannot detect unintended but
   valid interpolation. Use `--ide-check` when structured diagnostics are needed.
7. Report security/correctness findings before style and performance notes.

If a referenced file is unavailable, say so and continue with this file rather
than inventing its contents.

## Cross-Cutting Guardrails

These rules apply across task types. Load the routed reference before relying
on syntax or behavior that changed between Nushell releases.

### Types and pipeline contracts

- Declare pipeline input in the I/O signature rather than as a positional
  parameter. Capture `$in` once when it must be reused because streams can be
  single-pass.
- Type exported command parameters and input/output signatures.
- Treat external/config records as untrusted; use optional access such as
  `$record.field?` and validate the resulting type/value.
- Remember that `default` evaluates its fallback argument eagerly. Make the
  fallback null-safe or branch explicitly when it can fail or is expensive.
- Keep return types consistent. Avoid `any` unless the function is genuinely
  polymorphic.
- Use `external_arg` on `main` parameters only when the CLI must preserve the
  caller's token spelling instead of applying Nushell literal coercion. It
  produces `glob`/`list<glob>` values in Nu 0.115, so validate or convert them
  before treating them as structured application data.
- Prefer `match` for several branches on one value; use `if` for one-off boolean
  predicates.

### External commands and errors

- Pass external arguments as separate values, never as an interpolated command
  string. Use `complete` and check `exit_code` when status matters.
- Prefer `try/catch` and `$err.details` for structured in-process errors.
- On Nu 0.115, a spanned `error make` label has the shape
  `{text: ..., span: {start: ..., end: ...}}`. Do not use the obsolete flat
  `{text, start, end}` form.
- On Nu 0.115.0, a `try/finally` nested directly inside an outer `try` whose
  handler is `catch` silently skips the inner `finally`. Give the outer block a
  `finally`, or put the inner one behind a `do`/command boundary, and assert
  that the owned state is gone.
- Treat rendered nested-Nu diagnostics as presentation text, not a stable
  protocol. For CLI tests, normalize ANSI styling, gutters, and PTY wrapping
  before matching a long, domain-specific phrase.

### Security stop checkpoint

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

For output paths that do not exist yet, validate the existing parent directory
with the same containment rule, then join only a validated leaf name.

### Strings and formatting

- Prefer simple literals and raw regex strings; use double quotes only when
  actual escapes are required.
- Remember that `$'...'` interpolates but does not process escape sequences.
- **A literal `(` directly inside interpolation requires `$"..."`.** Since `$'...'` does no escape processing,
  every `(` inside it opens an interpolation expression and `\(` cannot prevent
  that. Write `$"\(abc)($var)"`, never `$'\(abc)($var)'`. The failure is often
  silent rather than an error: `$'(1 + 1) items'` evaluates to `2 items`. See
  [String Formats](references/string-formats.md). For generated code with many
  delimiters, join plain literal fragments and serialized data instead.
- Keep code and data separate across interpreters: pass argv/stdin/JSON to a
  fixed program. If an API only accepts source, use a fixed, trusted template
  with target-language serialization; a single argv string is still code when
  the receiving tool evaluates it. Do not concatenate raw values into source.
- Use kebab-case for commands/flags, snake_case for variables/parameters, and
  SCREAMING_SNAKE_CASE for environment variables.

### Data formats and grouping

- `from xml` loses XML namespace identity (reproduced on Nu 0.115.1): it
  stores only local names for elements and attributes, with no namespace URI
  or declaration in the result. For example,
  `<x xmlns:r="urn:r" id="plain" r:id="rel"/>` becomes an `attributes` record
  containing only `id: rel`; reversing the two attributes leaves `id: plain`.
  Later attributes overwrite earlier ones when their local names collide.
  Do not use this record for namespace-sensitive XML lookups, edits, or
  round-trips. Use a namespace-aware XML parser or, when the `query xml` plugin
  is available, XPath with `--namespaces` (and `--output-names` when names
  matter). Match namespace URI plus local name, not prefix spelling.
- Nu 0.115 makes `from yaml` default to YAML 1.2 with strict non-string keys
  and tags. Pin `--spec`, `--multiple`, tag handling, and key resolution when
  the input contract is controlled by another system instead of inheriting
  defaults accidentally.
- Let `to yaml` reject non-round-trippable values by default. Opt out only when
  that data loss is part of the documented contract, and quote the value:
  `--non-roundtrip 'null'`. A bare `null` is a parse error, and
  `--non-roundtrip 'lossy'` is rejected by `to yaml` on 0.115.0, so use
  `--serialize` when a lossy encoding is genuinely wanted.
- `group-by` record output cannot represent a null key and omits that group in
  Nu 0.115. Use `group-by --to-table` when null groups must be retained or
  distinguished from empty strings.

### Data flow and performance

- Prefer pipelines and immutable `let` bindings.
- Use `where`, `select`, `update`, `insert`, `items`, `transpose`, `reduce`, and
  `enumerate` instead of manual parsing and mutable accumulation.
- Do not capture `mut` variables in closures.
- `for` is appropriate for sequential side effects but is not a transforming
  expression; use `each` when a list result is required.
- Use `par-each` only when concurrency is safe and beneficial; preserve `each`
  when order or sequential side effects matter.
- Add `lines` before `parse` when line-by-line stream parsing is intended.
- Prefer direct row conditions for simple `any`/`all` predicates on Nu 0.115;
  retain closures when the predicate needs setup, destructuring, or reuse.
- Use native tables for small interactive data and Polars for large columnar
  group-by/join/aggregation workloads.

### Modules and scripts

- Export only the intended API; keep helpers private.
- Use `export def main` when the command should match the module name.
- Use `def --env`/`export def --env` for caller-visible environment changes.
- Do not name commands, aliases, modules, or exports after parser keywords.
  Also treat `$ans` as reserved in Nu 0.115; rename older `ans` bindings.
- `source`, `use`, and `run` targets must be trusted and available at parse time.
- Test at the correct seam: direct functions for stable structured errors, CLI
  subprocesses for argument parsing/process boundaries, and both when needed.

## Review Order

When reviewing code, report findings in this order:

1. Security: injection, traversal, credentials, destructive operations, temp
   files, environment poisoning.
2. Correctness: types, null handling, parse-time constraints, exit codes,
   cleanup/rollback, data-format contracts, platform/version behavior, stable
   tests.
3. Maintainability: naming, module boundaries, duplication, documentation.
4. Performance: streaming, unnecessary collection, safe parallelism, Polars.

Skip issues already enforced by the project's formatter/linter unless the tool
output shows they are currently failing.

## Validation

For ordinary script/module validation, prefer `nu-check --debug`. It parses
without running the target's top-level commands and reports parse-time type
errors as well as syntax errors. Use the matching parse mode:

```bash
nu --no-config-file -c 'nu-check --debug path/to/script.nu'
nu --no-config-file -c 'nu-check --debug --as-module path/to/module.nu'
nu --no-config-file path/to/test-script.nu
```

- Without `--debug`, invalid content returns `false` and the surrounding `nu`
  process can still exit `0`; consume the boolean explicitly. With `--debug`,
  a parse error throws, so an uncaught failure exits nonzero. Missing files are
  errors. Neither mode proves runtime correctness or provides a sandbox.
- Pass the file path directly when checking a saved script with relative
  imports. Piping its text to `nu-check` checks an anonymous source; the optional
  path does not restore the file's import context when pipeline input is present.
- For editor/CI integrations needing spans and diagnostic records, use
  `nu --no-config-file --ide-check 100 path/to/script.nu`.
- `--ide-check` emits JSON Lines on stdout and may still exit with code `0`
  when a record has `type: "diagnostic"` and `severity: "Error"`. It also
  exits `0` with empty output when the target file does not exist, so verify
  the path exists before treating an empty result as a pass. Parse every
  non-empty line with `from json`; do not use the process exit code alone.
  Treat `severity: "Error"` diagnostics as blockers, surface other severities
  such as `Warning` without blocking, and ignore `type: "hint"` records.
  Handle a non-zero exit code or stderr separately as a CLI startup or I/O
  failure.
- Prefer `--no-config-file` for reproducible standalone checks. Omit it when
  the script intentionally depends on commands or environment from user
  configuration, and document that dependency.
- `source` executes top-level code; it is not a syntax check. Use it only when
  intentionally loading audited definitions/setup. Validate side-effecting
  scripts with `nu-check`/`--ide-check`, then execute in an owned temp fixture.
  When saving structured values, use a recognized data extension or
  serialize explicitly (`to json`, `to yaml`, `to nuon`, and so on) before
  `save`.
- Do not use `nu --testbin` in Nu 0.115+. Recreate the required behavior with
  Nushell itself or a purpose-built test fixture.
- Reproduce terminal-sensitive tests under a narrow PTY when diagnostics or
  tables are involved, for example `stty cols 24 && nu tests/example.nu`.
- Check diffs for debug markers and accidental changes before finishing.
- If validation fails, fix the smallest reproducible issue and rerun the exact
  failing command before broadening the test suite.
