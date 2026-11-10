# Nu 0.117 Migration and Review Reference

Use for 0.117 upgrades, typed APIs, record pipelines, external wrappers, dotenv,
and config maintenance. Syntax in this guide requires 0.117 unless stated.
Keep the project's minimum version separate from the binary used to validate it.

## Evidence and scope

Verified **2026-11-10** on macOS arm64 with Nu **0.117.0**, commit
`a4819256a2d875ca42c8600242388da291f3beaa`, target
`aarch64-apple-darwin`, Rust 1.97.1, release build, no installed plugins.
The binary reports build time `2026-11-09 21:16:02 +00:00` and default
`pipefail=true`; no experimental options were changed for these tests.

- [Official release](https://github.com/nushell/nushell/releases/tag/0.117.0):
  published `2026-11-10T00:39:45Z`; the stable target and blog baseline are both
  0.117.0. The intervening 0.116.1 patch notes were also read.
- Docs repository `nushell/nushell.github.io`, fetched SHA
  `59b5e991fbf186c587501e63649565eda454935d`:
  [release notes](https://github.com/nushell/nushell.github.io/blob/59b5e991fbf186c587501e63649565eda454935d/blog/2026-11-09-nushell_v0_117_0.md).
  It was clean and already matched the fetched main commit.
- Source repository `nushell/nushell`, fetched SHA
  `a4819256a2d875ca42c8600242388da291f3beaa`: clean main was fast-forwarded
  by 26 commits. The remotely queried `refs/tags/0.117.0` and the binary commit
  both match this SHA, so the implementation evidence is release-specific.

Run [the regression suite](../tests/nu-0.117-smoke.nu) with Nu 0.117.0 selected
on PATH:

```console
nu --version
nu --no-config-file -c 'nu-check --debug tests/nu-0.117-smoke.nu'
nu --no-config-file tests/nu-0.117-smoke.nu
```

All 11 groups pass. Nested Nu processes use `$nu.current-exe`. Files are created
only below an owned temporary directory and removed in `finally`. Potentially
hanging external-stream tests run in child processes with a five-second deadline.
The original forced-timeout check observed only direct child PIDs; a follow-up
review reproduced a surviving nested Nu. Both version suites now share
[process support](../tests/support/nu-process.nu), which registers a launcher
before allowing the fixture to run, then kills its entire inherited Unix process
group and uses `kill -0` to poll until it disappears. Ownership falls back to
system `ps` when an older Nu lacks the process-group column. Windows uses
`taskkill /T`; that branch has not been run on Windows. Fixtures must not detach
into new sessions/groups.
The [process cleanup suite](../tests/process-cleanup-smoke.nu) verifies nested
timeout cleanup, startup cancellation, literal argv, failures and preflight checks
on the same 0.117.0 binary. A 0.117-based wrapper simulating the old macOS schema
checks both system-ps fallback and failure before release when ps is missing;
this simulation is separate from the later real 0.116.1 run recorded below.
The suite also passed in a 24-column PTY (`stty cols 24`, then the same selected
Nu executable), checking nested diagnostic assertions under narrow wrapping.

The existing 0.115, 0.116, strings/validation, and validation/daemon suites also
pass on this binary after making the old flatten assertion version-aware.
The historical 0.115.0/0.116.0 binaries were not rerun; their evidence remains in
their guides. A later local-binary matrix on the same macOS arm64 host passed:

| Nu version | Commit                                     | Suites passed                                                        |
| ---------- | ------------------------------------------ | -------------------------------------------------------------------- |
| 0.116.1    | `b632ef0994e07b5176ec45171e8cee2c127c5563` | 0.115, 0.116, process cleanup, validation/daemon, strings/validation |
| 0.117.0    | `a4819256a2d875ca42c8600242388da291f3beaa` | All six, including the 0.117 suite                                   |

Both binaries passed matching parse checks, including the shared launcher and
support module. The cleanup suite asserts that the nested process version
matches its selected parent binary. The 0.116.1 run exposed two compatibility
mistakes in the initial repair: `-$pid` is a string before 0.117, and the legacy
schema fixture must allow an already-absent column. Arithmetic `0 - $pid` and
`reject --optional` now work on both versions. For side-by-side installations,
set `NU_0116` to your Nu 0.116.1 executable and run these checks from Nushell:

```nu
let nu_0116 = ($env.NU_0116 | path expand --strict)
^$nu_0116 --version # Expect 0.116.1
^$nu_0116 --no-config-file tests/nu-0.116-smoke.nu
^$nu_0116 --no-config-file tests/process-cleanup-smoke.nu
```

REPL rendering, Ctrl+C behavior, Windows/BSD/Linux process fields, plugins,
LSP/DAP/MCP server sessions, experimental globbing, and speedups are upstream
guidance rather than measurements from this validation.

## Migration map

| Change                                | Impact and migration                                                 | CLI evidence / guidance location                             |
| ------------------------------------- | -------------------------------------------------------------------- | ------------------------------------------------------------ |
| `type` and `oneof` literal preference | Rename commands called `type`; quote numeric tokens intended as text | Types/parser group; Data & Types                             |
| Typed grouping and spread `get`       | Review key comparisons, nested paths and result cardinality          | Get/grouping group; Data & Types                             |
| Config list replacement               | Reset from defaults before appending custom entries                  | Config/process group; Modules & Scripts                      |
| Dynamic flags and `run` validation    | Quote positional flags; forward named options with record spreads    | Dynamic and file/run groups; Modules & Scripts               |
| Record transforms and flatten fix     | Avoid generated-key loss; consume closure errors                     | Record/data groups; Data & Types                             |
| Dotenv and env conversions            | Decide expansion, raw text, allowed keys and conversion policy       | Dotenv/env and file groups; Security                         |
| External stream fixes                 | Preserve channels/status; collect before dependent side effects      | Bounded external group; Advanced Patterns                    |
| Standardized `ps`                     | Update removed columns and handle nullable fields                    | Local macOS schema and own process checked; daemon reference |

## Types, parser rules, and removals

```nu
type Point = record<x: float, y: float>
type Polygon = list<Point>
def first-x [poly: Polygon]: nothing -> float { $poly.0.x }

module geometry { export type Count = int }
use geometry Count
def increment [n: Count]: nothing -> int { $n + 1 }
```

Aliases must be defined before use, cannot refer to themselves, and are local to
their block. Import exported aliases explicitly (`use geometry Count`, a list,
or `*`); bare `use geometry` does not import them. Help expands aliases rather
than preserving their spelling. Custom types such as `semver` now work directly
in annotations; plugin types still require the corresponding plugin.

`type` is a parser keyword. Rename definitions/aliases/externs with that name;
use `which` to inspect commands or `^type` for an actual external executable.

`oneof<string, int>` now prefers a matching integer literal regardless of member
order: `007` becomes integer 7, while `'007'` remains a string. The rule also
affects defaults, list elements, and extern arguments. Use plain `string` or
`external_arg` when raw spelling is the interface contract.

Additional breaking rules to search for:

- `not $a == $b` now means `not ($a == $b)`; `-$n` and `-(expr)` negate values
  in internal expressions. External argument spelling is unchanged.
- Overflowing integer/filesize/duration literals and invalid date-like literals
  now fail. Integer unit literals preserve their exact 64-bit value.
- Special floats use `inf`, `nan`, or `NaN`; `[INF]` contains a string.
- Duplicate literal fields, duplicate parameter/flag names or short flags,
  parameters after rest, and redefining `--help` are errors.
- `while`/`loop` cannot be pipeline stages. Aliases cannot contain pipelines or
  redirections; use `def`. Definitions with numeric-looking or uncallable names
  are rejected earlier.
- `get/select/reject --ignore-errors` are removed: use `--optional`. `get
  --sensitive` is removed; use normal case-sensitive paths or `!` for an
  insensitive member. Replace `filter` with `where`.
- Completer result `positional` is removed; use
  `completion_algorithm: substring` when substring matching is intended.
  Legacy `plugin.nu` files are no longer converted; register with `plugin add`.

The notes first claim `unlet` errors on constants, then describe a later fix.
**CLI result:** `const n = 1; unlet $n` succeeds, and a subsequent `$n` fails to
parse. This agrees with release
[parser handling](https://github.com/nushell/nushell/blob/a4819256a2d875ca42c8600242388da291f3beaa/crates/nu-parser/src/parse_pipelines.rs)
and [constant-hiding tests](https://github.com/nushell/nushell/blob/a4819256a2d875ca42c8600242388da291f3beaa/crates/nu-command/tests/commands/unlet.rs).
Do not turn the earlier bullet into a blanket prohibition.

## Grouping, extraction, and reduction contracts

```nu
[true 'true' 1 '1' null] | group-by --to-table
# five groups; key types: bool, string, int, string, nothing

{a: {b: 1}, 'a.b': 2} | get ...['a.b' $.a.b] # [2 1]
{a: 1} | get ...[a]                         # [1], not 1
{a: 1} | get ...[]                          # []
{a: 1} | get                                # {a: 1}
```

Table grouping uses typed value identity, preserving filesizes/datetimes/lists
as keys. Remove string-only comparisons/conversions that assumed formatted keys.
Default record grouping still uses display strings, merges `true` with `'true'`,
and cannot retain a null key. Exact integer filesizes such as `1000000b` and
`1001000b` remain distinct even when their displayed labels coincide.

Any spread passed to `get` forces a list result; a spread string is one literal
column name, so use `$.a.b` rather than `'a.b'` for nesting. Bare `get` with no
input now parses but fails at runtime with an empty-pipeline error.

`math sum/avg/product/max/min/median/mode/stddev/variance` with column names
reduce those columns across all table rows, returning one record:

```nu
[[a b]; [1 10] [2 20]] | math sum a # {a: 3}
[[a]; [[1 2]] [[3 4]]] | update a { math sum } # per-row list sums
```

List-valued table columns now error with `math sum a`; use `update` for the
former per-row behavior. Record fields containing lists still reduce as before.
`join` now errors when a nonempty table has no row with its join column.
`join --anti` retains unmatched left rows.

## Record transforms and repaired data loss

```nu
{a: 1, b: 2} | record where value > 1
{a: '', b: 2} | record where --values { is-not-empty }
{a: 1} | record each {|key, value| [($key | str uppercase) ($value * 2)] }
{a: 1, b: {c: [2 3]}} | record walk {|value| $value * 2 }
{age: '42', email: 'A@B.COM'}
| record apply {age: {into int}, email: {str lowercase}}
```

`record where` row conditions see `key`/`value`; its ordinary closure and
`record each` receive key and value as two arguments, with empty `$in`.
With `record where --keys/--values`, only that component is passed, including as
`$in`. Put these flags before the condition.

`record each` accepts a record, `[new_key new_value]`, or null to drop a field.
Duplicate output keys deliberately keep the later value; validate generated
names when every field matters. `record walk` receives leaf value and cell path,
also passing the value as `$in`; `--containers` visits containers after children,
and `--no-lists` handles each list as one leaf. `record apply` skips absent fields
unless `--strict` is set. All four commands also stream table rows.

`flatten` now rejects the previously lossy generated-name collision in either
field order with `nu::shell::column_defined_twice`:

```nu
{nested: {x: 1}, nested_x: 3, x: 2} | flatten # error, no silent overwrite
```

Ordinary collisions still get the `<parent>_<field>` name. Rename conflicts
before flattening, and consume the result when testing errors. Release source:
[flatten tests](https://github.com/nushell/nushell/blob/a4819256a2d875ca42c8600242388da291f3beaa/crates/nu-command/tests/commands/flatten.rs).

Migrate `update cells -c [a b] { ... }` to `update cells { ... } a b`;
the old flag still works with a deprecation warning. Closure failures now escape
`update cells`, including recursive traversal. `each/par-each/items` expose the
underlying message/code instead of a wrapper code; custom `error make` without
an explicit code still has `details.code: null` despite a rendered fallback code.

The old skill's `default` rule was too broad: ordinary arguments are eager, but
a closure **literal** is lazy. This is clarified behavior, not a new 0.117 feature:

```nu
1 | default { error make {msg: unused} } # 1; closure does not run
null | default { 42 }                   # 42
let fallback = { 42 }
null | default $fallback                # closure value, not 42
```

## Config lists, process tables, and environment files

`$env.config.keybindings = [...]` and `.menus = [...]` now replace the whole
list. `= []` clears it, including Nu's default menu bindings. Preserve defaults
and avoid repeated-source duplication by rebuilding deliberately:

```nu
$env.config.keybindings = (config default).keybindings
$env.config.keybindings ++= $custom_bindings
$env.config.menus = (config default).menus
$env.config.menus ++= $custom_menus
```

Last binding for the same key/mode wins; last menu with the same name wins.
Use `event: null` to unbind Reedline-owned keys. Invalid list entries now reject
the assignment and leave its old list intact; config evaluation stops on error.

`ps` now has `pid ppid name user status cpu cpu_time mem`; `ps --long` adds
`virtual private command exe start_time user_id process_group_id session_id
priority nice threads read written cwd environment`. Replace `process_threads`
with `threads`, `working/paged` with an appropriate metric (often `private`),
and Windows `user_sid` with `user_id`. More processes are visible with null
fields; compact nullable columns before regex matching or numeric ranking.
On macOS, own-process `cwd` and inclusion of pid 0 were verified. Do not log
the long table's `environment` column as routine diagnostics.

`open .env`, `.env.local`, and `prod.env` now parse dotenv automatically;
`save` serializes records to those names. Use `open --raw` for literal text.
Unquoted/double-quoted dotenv values expand earlier keys or environment values;
single quotes preserve `$` text. `$(command)` stays literal and is not executed.
Parsing does not authorize loading every variable: select allowed keys before
`load-env`. Serialization quotes values for round-trip preservation.

`load-env`, `with-env`, and `FOO=bar command` now apply `ENV_CONVERSIONS`;
string `PATH` becomes a list automatically. Use `--no-convert` for literal values
and remove redundant conversion-trigger assignments. Nu-managed `PWD` cannot
be set through these commands even with different casing; use `cd`.
`FILE_PWD`, `CURRENT_FILE`, and config also have protection against hiding.

## External interfaces and script execution

- `%$cmd`/`%($cmd)` now interpret flags, including record spreads, and reject
  unknown flags, missing values and extra positional arguments. Quote a literal
  `'--foo'`, or put it after `--`, to pass positional data.
- `run` validates `main` arguments without CLI-style string coercion: pass
  `'23'` to a string parameter. Its own flags precede the script path. Spread
  lists contain positional values; use `...{name: '23'}` for named options.
  Definitions, `main`, and variables now remain inside the run script.
- `hide` is block-local; sourcing a previously ended block's file works again.
  Directory modules containing dots now keep their full names, including in
  overlays; adjust calls/imports that used truncated names.
- `save` checks a custom converter's input contract and isolates ordinary
  converters' env changes. Use `def --env` only when propagation is intended.
  Extensions are matched case-insensitively (`data.JSON` uses JSON).
- `extern --strict` catches undeclared flags at parse time, with `--help`
  permitted and `-h` requiring a declaration. Plain externs remain permissive.
- `@structured [args] { decode }` on an extern adds arguments and decodes when
  collected or piped into an internal consumer. Direct display, `print`, byte
  sinks such as `complete`, external consumers, and file redirection keep raw
  output. `^cmd` bypasses the declaration. Test each boundary a wrapper uses.
- `generate completions` produces executable Nu source. Review and parse it
  before loading; use a module filename different from the tool name. The suite
  generates a module from fixed help text, then tests `--short` through
  `commandline complete`, without relying on external completion providers.

## External streams, cleanup, and secondary changes

The notes' earlier stderr/`finally` limitation is superseded by a later fix on
the successful path. CLI tests confirm that
`try { ^external } finally { ... } | complete` preserves stdout/stderr and an
exit status of zero, with the finalizer receiving stdout as a value.
With default `pipefail=true`, a nonzero exit propagates an error before the outer
`complete` runs; the finalizer then receives an error record with `exit_code`,
not stdout. The original success-only regression did not establish this failure
boundary. To inspect failure as structured data, move `complete` inside `try`:

```nu
let result = try { ^tool ...$args | complete } finally { cleanup }
```

The finalizer now sees the `complete` record, and callers must check its
`exit_code`. Follow-up regressions verify the outer-complete failure, its
finalizer's error input, and this inner-complete capture with stdout/stderr and
exit status 3.
The release's
[try regression tests](https://github.com/nushell/nushell/blob/a4819256a2d875ca42c8600242388da291f3beaa/crates/nu-command/tests/commands/try_.rs)
corroborate the same channel contract.
Independent `^external o> file | complete` preserves stderr/status even for
exit status 3 while writing stdout; that failure path is also tested.
The bounded regression also verifies a 300,002-byte stdout pipeline completes
with default pipefail enabled, plus a failed external's status through bare try.

Bare `try` keeps the external stream lazy and permits `complete` to retrieve
failure status. With `catch`, downstream commands inside try can process output
before the external failure reaches the handler. Put `collect` before dependent
side effects when they must not run for a failed producer.
The paired regression writes an owned file before `catch` without `collect`;
inserting `collect` immediately after the external prevents that write. A later
`collect` after `each` cannot roll back side effects and can change error handling.

Other guidance from the release, with validation scope kept explicit:

| Area                  | Guidance                                                                                                                                                                                                                    |
| --------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Paths                 | `path relative-to --walk-up` permits `..`; never use it as a containment check. Default containment rejection was CLI-tested.                                                                                               |
| Dates                 | `older-than`/`newer-than` use strict comparisons, accept datetimes or relative durations, and propagate null. Relative forms depend on now and cannot be const. Invalid dates now error.                                    |
| Conversion            | `detect type` parses composite durations but preserves padded strings; these and a leading JSON BOM were CLI-tested. NUON BOM support is upstream guidance.                                                                 |
| Binary                | `bytes remove --end` removes the last occurrence anywhere, not merely a suffix; absent patterns preserve the input (tested).                                                                                                |
| Jobs                  | `job spawn --auto-kill` and `job list.auto_kill` distinguish jobs exit may kill without a warning. Script/server shutdown and Ctrl+C rules improved; retain explicit owned-resource cleanup.                                |
| TUI                   | 0.116.1 added streaming builders, titles and borders; use `tui label --titlebar`. 0.117 errors on orphan follower closures. Terminal background and rendering changed; actual REPL/terminal behavior needs separate checks. |
| Math                  | Invalid log bases and NaN error; variance/stddev use more stable floating arithmetic. `first/last` work in const, and last on an unbounded range errors.                                                                    |
| SQLite / spreadsheets | SQLite errors now propagate instead of producing partial results. XLSX import fixes a crafted-file crash; ODS preserves formula errors as text. Not exercised with plugins/files here.                                      |
| Developer tools       | MCP evaluations serialize and keep stable history indices; remote binds require explicit allowed hosts/origins. LSP/IDE completion and DAP fixes need client-specific checks.                                               |
| Performance           | Parser, startup, closures, datetime and table output improved upstream. Benchmark the actual workload before claiming a local gain.                                                                                         |

See [0.116 history](nu-0.116-migration.md), [Data & Types](data-and-types.md),
[Modules & Scripts](modules-and-scripts.md), [Advanced Patterns](advanced-patterns.md),
and [Security](security.md).
