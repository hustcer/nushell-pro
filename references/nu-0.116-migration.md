# Nu 0.116 Migration and Review Reference

Use for 0.116 upgrades, custom completion/config maintenance, and reviews of
wrappers, data pipelines, or cleanup code. Keep the project's minimum Nu version
separate from the local binary; the syntax below targets 0.116 unless stated.

## Evidence and scope

Verified on macOS arm64 with Nu **0.116.0**, binary commit
`2459fdd134ea4fdbae42efd6924e2b41201cf363` (also the local source HEAD).
Release notes: `nu-docs` commit `4c2f11558a9fb15f592f417ba8c6ce8922ca7e82`,
[`blog/2026-09-26-nushell_v0_116_0.md`](https://github.com/nushell/nushell.github.io/blob/4c2f11558a9fb15f592f417ba8c6ce8922ca7e82/blog/2026-09-26-nushell_v0_116_0.md).
The originally supplied October 23 path was renamed in commit `dc92785b`.
Both checkouts matched fetched `origin/main`; no pull was needed.

Run [the smoke suite](../tests/nu-0.116-smoke.nu):

```console
nu --no-config-file -c 'nu-check --debug tests/nu-0.116-smoke.nu'
nu --no-config-file tests/nu-0.116-smoke.nu
```

The 0.115/0.116 suites launch nested Nu through `$nu.current-exe`, so an
explicit binary selection is preserved even when PATH points elsewhere. The
chained `par-each` regression runs in an isolated process with a deadline;
the suite also exercises forced timeout and verifies job/process cleanup.
These harness checks were rerun on 0.116.0; no older binary was revalidated
in this follow-up review.

Core examples and regressions below are CLI-tested. Interactive terminal
ownership, editor DAP sessions, plugins, Windows fixes, and performance claims
are release-note guidance, not measured results on those environments.

## Breaking changes and migration blockers

### Custom completion inputs and outputs

Parameter, command-wide, external and menu completers now share named inputs.
Declare positional parameters named `token`, `place`, or `buffer` in any order:

```nu
def complete-branch [token: record] {
    ^git branch --format '%(refname:short)' | lines
    | where {|branch| $branch | str starts-with $token.text }
}
```

- `token.text` is the current token; `token.span` is its source range.
- `place.command` is the command's shell-word list, with aliases expanded.
  Use it instead of splitting `buffer` on spaces: quoting, pipelines, closures,
  separators, and incomplete arguments make that split unreliable.
- `place` describes the cursor/site; `flag`, `index`, and `shape` are conditional.
  Use optional access when the site can vary.
- `buffer` contains the line through the cursor. Prefer it to calling
  `commandline` inside a completer, which can be empty in some editor states.
- Migrate old `[context offset]`, `[input pos]`, menu `[buffer position]` and
  external `spans` interfaces to these named inputs. The notes mention legacy
  `spans` compatibility; new code should use `place.command`. Arbitrary positional
  names are not aliases for `token`. Contrary to the notes' blanket claim that
  unknown names receive `nothing`, this build bridges the first two unrecognized
  positions to legacy inputs, with deprecation warnings. A parameter completer
  `[anything]` still receives a context string (CLI-tested). Do not depend on
  that bridge: later unrecognized positions are not equivalent to named inputs.

```nu
$env.config.completions.external.completer = {|place|
    ^carapace $place.command.0 nushell ...$place.command | from json
}
```

Return `null` to decline; strings, lists and suggestion records are accepted.
An envelope `{completions: [...], options: {...}, fallback: true}` keeps the
suggestions and continues to other sources. Parameter completers filter by
default, while command-wide/external completers normally filter themselves.
Set `options.filter` explicitly when composing sources. A failing parameter
completer now returns no suggestions rather than falling back to the directory.

The global `background-completions` option is removed. Mark terminal-owning
commands (fzf, `input list`) with `@interactive`; external completion closures
can call an annotated command. Do not test this merely by direct invocation:
the completion engine supplies inputs and decides terminal ownership.

```nu
'git checkout mai' | commandline complete --input
'choose al' | commandline complete --detailed
# Built-in source composition:
'./' | commandline complete --type directory
```

`--input` cannot combine with `--detailed` or `--type`. The release-note sample
shows `place.kind: positional` and `shape: external-argument` for `git`; the
tested binary instead returns `kind: external-arg` with no `shape` for this
undeclared external command. Do not hard-code the sample's whole record.
Source corroboration: `crates/nu-cli/src/completions/completer.rs`,
`CompletionSiteKind` display mapping at the recorded revision.
Legacy bridge source: `crates/nu-cli/src/completions/custom_completions/mod.rs`,
`LegacyInputs::when_needed` and `LegacyInputKind`.

### YAML writer options

Replace `--compact-list-indent` with `--list-indent compact`; choose
`--list-indent indented` when that layout is required. The old flag fails to
parse. Round-trip structured data rather than asserting formatting unless the
format itself is the contract.

`to yaml --non-roundtrip null` now accepts the bare literal. Quoted `'null'`
still works and remains portable to 0.115. **`--non-roundtrip 'lossy'` alone is
still rejected on 0.116.0**; `--serialize` remains available for deliberate lossy
serialization. Prefer removing unsupported values to silently dropping them.
Confirmed in `crates/nu-command/src/formats/to/yaml.rs`: lossy handling requires
the serialize flag. The raw-null fix did not fix the separate lossy behavior.

### Additional parser compatibility changes

- Quote external literal arguments beginning with `{`; they now parse as
  records/closures. Keep argv data separate from command source.
- `[1; 2]`, list patterns using semicolon separators, and header-only
  `[[a b];]` now fail instead of silently losing content. Use ordinary list
  separators or complete table rows.
- `take until`, `take while`, `skip until`, `skip while`, and `chunk-by` accept
  row conditions. Put flags **before** the predicate; this also works on 0.115:

  ```nu
  [1 2 3 4] | take until --include 1 {|n| $n == 3 } # [1 2 3]
  [1 2 3 4] | take until $it == 3                  # [1 2]
  ```

  CLI reproduction found that the former `take until {|n| ... } --include 1`
  form fails to parse on 0.116. The release notes do not call out this migration.

## Named flags and wrapper commands

Internal/custom commands accept records spread into named flags:

```nu
def options [--count: int = 5, --nullable: oneof<int, nothing> = 7, --verbose] {
    {count: $count, nullable: $nullable, verbose: $verbose}
}
options ...{count: null, nullable: null, verbose: false}
# {count: 5, nullable: null, verbose: false}
```

A null value omits a flag whose type excludes `nothing`, preserving defaults.
Types accepting `nothing` (`any`, `oneof<int, nothing>`) receive explicit null.
For switches, true enables; false/null omits. Unknown names and incompatible
field values error at runtime. Validate/filter untrusted records before forwarding
flags, rather than granting arbitrary options to a wrapped command.

For explicit typed flags, `--count=(null)` works; bare `--count=null` can fail
parse-time checks. List spreads still mean positional/rest arguments, not flags.

## Correctness fixes and data transformations

- Nested `finally` now runs before an outer `catch`, innermost first. `return`,
  `break` and `continue` unwind cleanup, too. An error in `finally` replaces
  the original error. Keep cleanup ownership tests, but do not impose the
  0.115.0 `do`-boundary workaround on projects requiring 0.116.
- `$in` and the optional `finally` parameter receive the successful value,
  the error record on failure, or `nothing` on control-flow exit (release-note
  contract). Cleanup remains for side effects, not replacing the return value.
- Both `semver | into string` inference and the old comparison-to-bool inference
  workaround were retested successfully. Direct `let newer = ($v > '1.0.0')`
  and `assert ($v > '1.0.0')` work on 0.116.
- `--ide-check` now reports unreadable/missing files with a nonzero exit.
  Parse JSONL diagnostics for existing files as before; semantic errors can
  still accompany exit zero. Keep explicit path checks for older Nu versions.
- `length`, `columns`, `is-empty`/`is-not-empty`, and `each while` surface stream
  errors instead of silently returning misleading values. Tests must consume
  the stream. Fix invalid upstream predicates rather than ignoring new errors.
- `default 5 a.b` fills a nested field (creating parents); `default 5 'a.b'`
  targets a literal dotted key. This changes existing unquoted dotted arguments.
- `flatten` now renames nested fields colliding with later top-level names to
  `<parent>_<field>`, matching the opposite field order. This does not guarantee
  lossless flattening: on 0.116.0, if the generated name already exists, a value
  is still silently overwritten depending on field order. For example,
  `{nested: {x: 1}, nested_x: 3, x: 2} | flatten` yields
  `[{nested_x: 3, x: 2}]`; putting `nested` last instead leaves `nested_x: 1`.
  Check generated names or explicitly rename conflicts before flattening when
  all values must survive; also review downstream expected column names.
- `update cells --recursive` visits nested leaf values. Default behavior remains
  nonrecursive; heterogeneous leaves require a type-aware closure.
- `lines --skip-empty` now drops empty lines for string/byte-stream inputs.
  YAML text such as `a.infra`/`a.nanotube` stays a string rather than a float.
- `save --force` creates missing parent directories as well as permitting
  overwrites. Validate the destination before calling it; a missing parent is
  no longer a guard against an unintended write.
- `mkdir --fail-if-exists` opts into rejecting existing paths. Ordinary `mkdir`
  is still idempotent; verbose rows report `created: false` for existing dirs.
- Template-based `mktemp --directory` now uses the working directory. Prefer
  no-template `mktemp --directory` for the usual temporary root.
- Chained equal-size `par-each` pools no longer deadlock. Keep bounded tests
  and choose concurrency for independent work; this does not promise output order.

## Optional tools and configuration

Use `tui debug` to test widget layouts and key sequences without a terminal:

```nu
[{name: a} {name: b}] | tui table --id items
| tui debug --size [40 10] --keys [down enter] | get selected.name # b
```

Use stable explicit widget IDs when connecting widgets. `tui run` returns
`{action, focused, selected, page, values, rows, live}`; debug adds layout/screen
fields. Hooks returning `{action: submit, selected: ...}` or `{action: quit}`
close the UI; other non-null output replaces shared data. Unbounded producers
belong in the outer pipeline, not collected child lists. Actual terminal
restoration and interactive pickers still need a PTY/manual check.

Other release-note items worth routing on demand:

| Area                | Guidance                                                                                                                                                                                                                    |
| ------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Debugging           | `nu --dap` serves DAP over stdio; validate with a DAP client, not as a syntax checker.                                                                                                                                      |
| Source inspection   | `view source --dependencies` includes transitive private helpers and captured constants; inspect output before sharing it.                                                                                                  |
| Logging             | `std/log` emitters accept `--context` records; keep credentials out of context.                                                                                                                                             |
| Conversion/hash     | `into float` accepts decimal commas; `hash sha512` is available. Do not confuse decimal commas with thousands grouping.                                                                                                     |
| Completion menus    | `completions.persistent_menus` defaults false; true keeps menus open while editing.                                                                                                                                         |
| Keybindings         | `SwitchMode`, `vi_visual`, and its cursor shape are new; `vi_normal` bindings no longer apply in visual mode.                                                                                                               |
| Polars              | New `date-range`, `date-ranges`, `datetime-range`, `datetime-ranges`; requires the plugin, absent in this validation environment.                                                                                           |
| MCP                 | HTTP bind default is now loopback `127.0.0.1`; remote clients need explicit configuration, not a broad-bind workaround by default.                                                                                          |
| Startup/performance | `$nu.startup-time` measures through first prompt readiness; hooks see provisional timing. Do not compare it directly with older measurements. Source caching/parser/plugin startup improved; benchmark the actual workload. |
| Windows             | Dot-glob deletion skips `.`/`..`; interactive rm prompt handling fixed. Retain deletion/path guards.                                                                                                                        |
| Display/tools       | Locale date formatting, narrow tables, redirected help, `idx search` limits and `query web` headerless tables have fixes; retest affected integrations.                                                                     |

## Review checklist

1. Migrate all completion entry points, menu sources, and background settings.
2. Search YAML writer flags, unquoted dotted `default` keys, brace-leading
   external literals, list semicolons, and flags following row predicates.
3. Check null/default intent and allowed keys in record-spread wrappers.
4. Replace only the reproduced obsolete workarounds; preserve old-version support.
5. Recheck stream failure handling, cleanup ordering, save destinations and
   expected flattened columns; run existing tests as well as new release tests.

See [0.115 history](nu-0.115-migration.md), [Script Review](script-review.md),
[Data & Types](data-and-types.md), and [Modules & Scripts](modules-and-scripts.md).
