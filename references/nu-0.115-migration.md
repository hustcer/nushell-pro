# Nu 0.115 Migration and Review Reference

Use this reference when upgrading to Nu 0.115, reviewing code whose behavior
changed in 0.115, or deciding whether a new 0.115 idiom is compatible with a
project's supported Nushell range.

For newer targets see [Nu 0.116](nu-0.116-migration.md): nested `finally`,
SemVer comparison inference and missing-file IDE checks are fixed; raw YAML
`null` is accepted and list indentation uses a different flag. Historical
0.115.0 reproductions below remain relevant to that version. The separate
YAML `--non-roundtrip 'lossy'` rejection still reproduces on 0.116.0.

## Contents

- [Establish the compatibility target](#establish-the-compatibility-target)
- [Breaking changes and migration blockers](#breaking-changes-and-migration-blockers)
- [High-frequency command improvements](#high-frequency-command-improvements)
- [Correctness fixes that affect reviews](#correctness-fixes-that-affect-reviews)
  - [Nested `finally` cleanup is still unreliable](#nested-finally-cleanup-is-still-unreliable)
- [Secondary additions and performance](#secondary-additions-and-performance)
- [Migration review checklist](#migration-review-checklist)
- [Focused validation](#focused-validation)
- [Related references](#related-references)

## Establish the Compatibility Target

Check the project's documented minimum/maximum version and CI matrix before
using the local binary as evidence:

```console
nu --version
```

From inside Nushell:

```nu
version | get version
```

Direct comparison operators on `semver` values were added in 0.115. If a
script must still run on 0.114, use a `semver-range` membership test rather than
putting a 0.115-only comparison in the compatibility gate.

## Breaking Changes and Migration Blockers

### YAML now defaults to 1.2 and enforces explicit contracts

`from yaml` now defaults to YAML 1.2. Values such as `yes` and `off` remain
strings, leading-zero decimal values are decimal, octal uses the `0o` prefix,
and YAML 1.1 sexagesimal (base-60) scalars stay strings. Use `--spec 1.1` only
for an input contract that intentionally relies on YAML 1.1 coercion:

```nu
'yes' | from yaml              # string
'yes' | from yaml --spec 1.1   # bool

'0247' | from yaml             # decimal 247
'0247' | from yaml --spec 1.1  # octal 0o247

'190:20:30' | from yaml             # string '190:20:30'
'190:20:30' | from yaml --spec 1.1  # 685230 (base-60)
```

The sexagesimal case is the easiest one to miss during review: colon-bearing
scalars such as timestamps, ID fields, and `HH:MM:SS` durations changed type in
both directions with no error on either side.

The parser is also stricter at the boundaries where YAML does not map cleanly
to Nushell values:

- Plain mapping keys that resolve to bool, number, or null error because Nu
  record keys are strings; this is `--key-resolution strict`, the default. Use
  `--key-resolution verbatim` only when retaining the original key text is the
  intended contract.
- Unknown tags error. Use `--ignore-tags` only when discarding tag semantics is
  safe; it is not a validation mechanism.
- `--multiple auto` returns one document directly but a list for multiple
  documents. Use `--multiple list` for a stable list-shaped API or
  `--multiple single` to reject streams.
- Anchors, aliases, and merge keys now resolve correctly. Re-test code that
  previously worked around missing merge behavior.

`to yaml` now errors on values such as closures that cannot round-trip. Keep
that safe default and opt out only when the caller explicitly accepts data loss
or Nushell-specific tags. Generated quoting, indentation, and tags also changed,
so semantic round-trip assertions are more stable than byte-for-byte golden
files.

The opt-out value must be quoted. A bare `null` parses as the `nothing`
literal, not as the string the flag expects:

```nu
{a: {|| $in}} | to yaml --non-roundtrip null    # parse error: expected string
{a: {|| $in}} | to yaml --non-roundtrip 'null'  # a: null
{a: {|| $in}} | to yaml --serialize             # a: !closure "{|| $in}"
```

Verified by reproduction on 0.115.0: `to yaml --non-roundtrip 'lossy'` is
rejected with an "expected `error`, `null` or `lossy`" incompatible-parameters
error even though `lossy` is exactly what was passed. Only `'error'` (the
default) and `'null'` work on `to yaml`; use `--serialize` where a lossy
encoding is genuinely wanted. `to kdl --non-roundtrip 'lossy'` is unaffected.
Do not build a contract on `--serialize` either — the release notes call it
"still available but will probably be deprecated in the future". The durable
fix is to keep non-round-trippable values out of the writer.

Useful explicit writer options include `--spec`, `--add-directives`,
`--multiple`, `--indent`, `--compact-list-indent`, `--quote`,
`--non-roundtrip`, and `--serialize`. On the writing side `to yaml --multiple`
emits each item of a list as its own YAML document, mirroring
`from yaml --multiple` on the reading side.

### Parser keywords and `$ans` are reserved

Commands, aliases, module names, exports, and wildcard imports must not shadow
parser keywords. `export main` also fails when the _module_ is named to shadow
a keyword — the conflict is on the module name, not on `main` itself. Check the
final imported namespace, not just the local `def` declarations.

`$ans` is reserved for the last successful REPL result. Rename older bindings
such as `let ans = ...`; do not use `$ans.last` as script state. At the REPL,
the record exposes `last`, `exit_code`, `duration`, and `command`.
`$ans.last` storage is opt-in through `$env.config.max_last_result_size` and
defaults to `0b`, so code must not assume the previous output is retained.

### Test and index commands removed

- `nu --testbin` no longer exists. Replace it with a small Nushell fixture or a
  purpose-built test executable.
- `idx import` and `idx export` were removed. Build the in-memory index with
  `idx init`; use `--no-watch` only when live watching is not wanted.

## High-Frequency Command Improvements

### Preserve raw script CLI tokens with `external_arg`

Use `external_arg` on `main` parameters when a script intentionally needs the
caller's token spelling rather than Nushell literal coercion. For example,
unquoted `0001` and `true` stay token-like `glob` values instead of becoming an
integer and a boolean:

```nu
def main [
    revision: external_arg
    --define (-D): external_arg
    ...rest: external_arg
] {
    let revision_text = ($revision | into string)
    let rest_text = ($rest | each { into string })
    {revision: $revision_text, define: $define, rest: $rest_text}
}
```

Prefer concrete types such as `string`, `int`, or `path` when coercion and type
validation are part of the API. `external_arg` preserves a token; it does not
sanitize it. Validate it before using it as a path or pattern, and pass it as a
separate argv value rather than interpolating it into `nu -c` or a shell
command string. See [Security](security.md) for the containment rules that
apply to any externally supplied path or pattern.

Nu 0.115 also accepts arguments after `--` for `nu -c` / `nu --commands`.
When a nested Nu process is genuinely required, keep the command text constant,
define a typed `main`, and pass data separately:

```console
nu -c 'def main [value: external_arg] { $value | into string }' -- 0001
```

### Use row conditions with `any` and `all`

Simple predicates can now use the same row-condition syntax as `where`:

```nu
[9 8 7 6] | enumerate | any item == index * 2
[1sec 1min 1hr] | all ($it | describe) == duration
```

Keep a closure when the predicate needs local setup, destructuring, or reuse.
During review, verify that a direct column name is evaluated against a table
row and is not mistaken for an outer variable.

### Slice binary data with filesize counts

`chunks`, `first`, `last`, `take`, `skip`, and `drop` accept `filesize` counts;
`drop` now also accepts binary input. This makes byte intent visible:

```nu
open --raw archive.7z | chunks 10MiB
open --raw packet.bin | first 16b
open --raw packet.bin | skip 8b | take 4b
```

Use an integer for lists/tables unless a byte-sized count is genuinely clearer.
Do not assume a binary chunk is text; decode only after validating its encoding
or at a known character boundary.

### Compare and convert SemVer values directly

Nu 0.115 supports `==`, `!=`, `<`, `<=`, `>`, and `>=` on `semver` values. A
valid version string is accepted on the right-hand side:

```nu
let actual = ('2.0.1' | into semver)
$actual >= '2.0.0'
('1.0.0-alpha' | into semver) < '1.0.0'
```

`into semver` also accepts lists and cell paths. Use `--loose` only for the
documented `v`-style prefixes (`v1.2.3`, `v.1.2.3`, `v:1.2.3`, `v-1.2.3`, or
`v_1.2.3`); it should not replace validation of arbitrary version text. A
loose value converts successfully to the `semver` custom type but retains its
original prefix when converted back to a string; do not assume normalization.
The release notes do not state this — it is verified by reproduction on 0.115.0
and locked by the repository smoke test.

Nu 0.115.0 has a parser inference edge case that the release notes do not
mention; it is verified by reproduction. When a comparison is passed to a
parameter declared `bool` (for example `assert (<comparison>)`), the parser
reports `expected bool, found semver`. Binding it with `let` fails the other
way: the parser infers `semver`, then the runtime reports
`expected semver, got bool`. Bare expressions and `if (<comparison>)` are
unaffected, so this is narrower than "any boolean context".
Until the supported Nu patch release fixes this, evaluate the comparison in an
unconstrained one-item list and extract it at the use site, for example
`assert equal ([($actual >= '2.0.0')] | first) true`. Keep this workaround
version-scoped; do not replace semantic version comparison with lexical string
comparison.

### Include the stopping boundary in stream prefixes

`take while` and `take until` accept `--include (-i) N`. `--include 1` commonly
includes the first item that would otherwise stop the command:

```nu
[1 2 3 4] | take until --include 1 {|n| $n == 3 }  # [1 2 3]
[1 2 3 4] | take while --include 1 {|n| $n < 3 }   # [1 2 3]
```

Review off-by-one behavior explicitly. Values greater than one include more
items after the original stopping point and may trigger additional upstream
side effects on a lazy stream.

Keep flags before the predicate for compatibility with 0.116's row-condition
parser; the old trailing-flag form fails to parse there.

### Preserve null groups deliberately

`group-by` now treats null consistently across direct values, cell paths, and
closures. Record output omits the null group because record keys must be
strings; null no longer collapses into the empty-string key. Use table output
when null is data:

```nu
[a '' null] | group-by --to-table
[{x: a} {x: null}] | group-by x --to-table
```

Optional cell paths such as `group-by x?` still skip missing and null values.
This is different from a required path with `--to-table`, which retains the
null group.

### Apply math commands to selected record columns

Reducing commands such as `math avg`, `math sum`, `math max`, and `math
variance`, plus element-wise commands such as `math abs`, `math floor`, and
`math sqrt`, now accept optional cell paths for records containing list-valued
columns:

```nu
{alice: [1 2 3], bob: [4 5 6]} | math avg alice
{alice: [-1 -2], bob: [-3 -4]} | math abs alice
```

Check whether unselected columns intentionally remain unchanged; selecting one
column is not a whole-record reduction.

## Correctness Fixes That Affect Reviews

- Nested `try/finally` no longer consumes an outer error handler: the error
  now reaches the outer `catch`. The inner `finally` still does not run in that
  shape — see [Nested `finally` cleanup is still
  unreliable](#nested-finally-cleanup-is-still-unreliable) before removing a
  pre-0.115 workaround.
- `error make` rejects malformed labels. A spanned label is
  `{text: ..., span: {start: ..., end: ...}}`, not the old flat
  `{text: ..., start: ..., end: ...}` record.
- `scope variables`, `scope commands`, `scope aliases`, `scope modules`, and
  `scope externs` include active local scopes. `scope commands` also exposes
  `deprecation_info` as a table, so read a single command's entry with
  `deprecation_info.0`. Review tooling can use it instead of maintaining a
  hard-coded deprecated-command list.
- `source` can see current outer variables after a rebinding. Reassess
  pre-0.115 workarounds, but keep source targets trusted and parse-time known.
- `path type` on an empty string returns `null`, not `dir`. An empty or missing
  type must fail validation rather than being treated as a directory.
- Saving structured data to an unknown/no-extension file still requires an
  explicit serializer. 0.115 only made the failure message clearer; it did not
  add new enforcement. Use `to json | save ...`, another `to ...` converter, or
  render a table intentionally.
- `seq` now errors on a zero increment and terminates safely at integer bounds.
  Validate a user-supplied step before calling it to provide domain-specific
  feedback.
- Quoted `#` values now pass correctly as script parameters. Remove shell-style
  escaping workarounds that alter values such as hex colors.
- Assigning `$env.config.keybindings = []` or `.menus = []` merges with defaults
  and no longer clears them. Use a matching binding with `event: null` to
  unbind a key. Setting only part of `$env.config.color_config` now keeps the
  defaults for the parts that were not set; unlike keybindings, the stored
  record still shows only the keys you assigned, so assert on rendered colors
  rather than on `$env.config.color_config | columns`.
- Incompatible right-hand-side uses of `$in` in typed math are now reported at
  parse time, matching the existing left-hand-side behavior. For example
  `def f []: string -> int { 2 + $in }` no longer parses. Code that relied on
  the mismatch surfacing at runtime now fails earlier and more visibly.
- Quotes inside `(...)` subexpressions of interpolated strings now lex
  correctly, so `$"('" "')"` prints `" "`. This does not relax the separate
  rule that a _literal_ parenthesis still requires `$"..."` with `\(`; see
  [Anti-Patterns](anti-patterns.md).
- `stor import --file-name` with a missing path now fails instead of creating
  an empty file and silently discarding the in-memory database.
- `generate` accepts `null` pipeline input the same way it accepts empty input.
- `match` arms accept constant expressions, and `oneof` parameters accept
  negative numeric arguments. Both remove workarounds rather than break code.

### Nested `finally` cleanup is still unreliable

Verified by reproduction on 0.115.0. When a `try { ... } finally { ... }` is
lexically nested inside an outer `try` whose handler is `catch` — or inside a
bare `try` with no handler — the inner `finally` is silently skipped:

```nu
try {
    try { error make {msg: 'inner'} } finally { print 'INNER-CLEANUP' }
} catch {|e| print $'outer caught: ($e.msg)' }
# outer caught: inner        <- INNER-CLEANUP never printed
```

A bare outer `try` is worse: the error is swallowed, the exit code stays `0`,
and the cleanup is still skipped. A plain runtime error such as
`[1 2 3] | get 99` behaves identically, so this is not specific to
`error make`.

Both of these shapes do run the inner cleanup on 0.115.0:

```nu
# The outer handler is `finally` rather than `catch`
try {
    try { error make {msg: 'inner'} } finally { print 'INNER-CLEANUP' }
} finally { print 'OUTER-CLEANUP' }

# The inner `try/finally` sits behind a `do` or a custom-command boundary
try {
    do { try { error make {msg: 'inner'} } finally { print 'INNER-CLEANUP' } }
} catch {|e| print $'outer caught: ($e.msg)' }
```

Do not delete a pre-0.115 cleanup workaround on the strength of the release
note alone. Where cleanup must happen, prefer the outer-`finally` shape and
assert afterwards that the owned state is actually gone. See
[Daemon & E2E Smoke Tests](daemon-and-e2e-smoke-tests.md) for the job/fixture
ownership pattern that already follows this rule.

## Secondary Additions and Performance

- `from kdl` and `to kdl` support `--spec 1|2` and default to KDL 2. Their
  `--format` defaults differ: `from kdl` uses `nodes` (KDL AST rows), while
  `to kdl` uses JSON-in-KDL (`jik`). Pin both `--spec` and `--format` at
  file/API boundaries.
- `lines` now produces a list stream lazily even for an in-memory string value.
  Avoid collecting it unless later code needs random access or reuse.
- Large binary slicing and repeated access to large lists/tables are much
  cheaper. Keep streaming for bounded memory; do not add manual caching solely
  to work around the old copy cost without re-measuring.
- `str replace --regex` and `--multiline` are substantially faster on nested
  string data, and built-in regex parameters use a cache. Prefer the built-in
  structured transform before introducing an external text-processing step.
- `date floor` and `date ceil` are available from `std-rfc/date` for duration
  boundary rounding.
- `idx watch` streams indexed filesystem changes and supports filtering,
  timeout, and maximum-event bounds.
- The new `matrix` custom value provides dedicated arithmetic, linear algebra,
  mapping, and reduction commands. Build one with `into matrix` from a table or
  a `list<list<number>>`; bare `matrix` is only the subcommand namespace and
  accepts no pipeline input. Standard `each`, `par-each`, and `reduce`
  intentionally reject matrices, so use `matrix map`, `matrix reduce --fold`,
  and `matrix into-nu` at ordinary Nu-data boundaries.

## Migration Review Checklist

1. Record the project's supported Nu range and reproduce on the lowest relevant
   version before recommending 0.115-only syntax.
2. Search YAML call sites and make spec, key, tag, multiple-document, and
   round-trip expectations explicit at external boundaries.
3. Search definitions/imports for parser-keyword names and bindings named
   `ans`.
4. Replace `nu --testbin`, `idx import`, and `idx export` dependencies.
5. Decide whether each script argument wants Nushell typing or raw-token
   preservation; do not apply `external_arg` mechanically.
6. Check `group-by` consumers for null-key loss and empty-string conflation.
7. Check `error make` labels and tests that compare rendered diagnostics.
8. Check `path type`, unknown-extension `save`, and keybinding-reset code for
   assumptions changed in 0.115.
9. Use `scope commands` deprecation metadata to identify active deprecated
   commands, including commands imported into local scopes.
10. Add focused tests for boundary values: YAML 1.1 scalars, multi-document
    inputs, null groups, SemVer prereleases, binary chunk sizes, and include
    counts of zero/one/many.

## Focused Validation

Run the repository smoke test when Nu 0.115 is the active target:

```console
nu --no-config-file tests/nu-0.115-smoke.nu
```

For a migrated script, start with parsing and a no-config execution seam:

```console
nu --no-config-file --ide-check 100 path/to/script.nu
nu --no-config-file path/to/test-script.nu
```

Remember that `--ide-check` requires parsing its JSON Lines output; exit status
alone is not proof that the script has no error diagnostics.

## Related References

- [Nu 0.114 Migration](nu-0.114-migration.md) for the previous release's
  stricter typing, explicit submodule imports, and `run`.
- [Security](security.md) for `external_arg`, path containment, and the rules
  that govern any nested `nu -c` invocation.
- [String Formats](string-formats.md) for quoting rules, including the
  interpolation and literal-parenthesis constraints referenced above.
- [Data & Type System](data-and-types.md) for `oneof<T, nothing>`, null
  handling, and conversion semantics behind the YAML and `group-by` changes.
- [Daemon & E2E Smoke Tests](daemon-and-e2e-smoke-tests.md) for the cleanup
  ownership pattern that survives the nested-`finally` defect.
- [Script Review](script-review.md) and [Anti-Patterns](anti-patterns.md) for
  the checklist items these changes add.
