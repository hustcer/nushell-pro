---
name: nushell-pro
description: |
  Comprehensive Nushell scripting best practices, idioms, security, and code review. Use when writing, reviewing, auditing, or refactoring Nushell (.nu) scripts to ensure they follow idiomatic patterns, naming conventions, proper type annotations, functional style, security best practices, and Nushell's unique design principles. Triggers on tasks involving Nushell scripts, modules, custom commands, pipelines, Nu 0.114+ migration, or any .nu file editing. Also helps convert Bash/POSIX scripts to idiomatic Nushell. Covers the type system, data manipulation, performance optimization, security hardening, script review, common gotchas, and current Nu 0.114 behavior such as stricter type checking, `run`, POSIX `--`, SemVer, and explicit submodule imports.
---

# Nushell Pro — Best Practices & Security Skill

Write idiomatic, performant, secure, and maintainable Nushell scripts. This skill enforces Nushell conventions, catches security issues, and helps avoid common pitfalls.

## Operating Workflow

Use this sequence whenever writing, reviewing, refactoring, or converting Nushell code:

1. Identify the task type: new script, code review, refactor, Bash conversion, module design, security audit, or debugging.
2. Read the existing `.nu` files and nearby project conventions before changing code.
3. Load only the reference files needed for the task:
   - String quoting, interpolation, escaping, regex, or globs -> [String Formats](references/string-formats.md)
   - Security, untrusted input, external commands, paths, credentials, or destructive operations -> [Security](references/security.md)
   - Review-only requests -> [Script Review](references/script-review.md)
   - Bash/POSIX conversion -> [Bash to Nushell](references/bash-to-nushell.md)
   - Modules, exports, scripts, or tests -> [Modules & Scripts](references/modules-and-scripts.md)
   - Types, records, tables, lists, or conversions -> [Data & Type System](references/data-and-types.md)
   - Streaming, `peek`, `parse`, `par-each`, performance, closures, or version-sensitive command behavior -> [Advanced Patterns](references/advanced-patterns.md)
   - Large datasets, Polars dataframes, columnar analytics, heavy group-by/join -> [Dataframes](references/dataframes.md)
   - Common mistakes and fixes -> [Anti-Patterns](references/anti-patterns.md)
4. Apply the critical checks in this file first, then use references for details.
5. For version-sensitive behavior, confirm the active Nu version with `nu -c 'version | get version'` and use Nushell MCP evaluation tools if they are exposed in the session.
6. Validate parseability with `nu -c 'source path/to/file.nu'` for modules or `nu path/to/script.nu` for scripts when the command is safe to run.
7. Summarize security findings first, then correctness/style/performance changes.

If validation fails -> read the Nushell diagnostic, fix the syntax or type signature, and rerun the smallest safe validation command.
If a command has side effects -> validate only parseability or use a fixture/temp directory.
If a reference conflicts with local project style -> keep project style unless it violates safety, parseability, or Nushell semantics.

STOP CHECKPOINT: Before approving code that runs external commands, deletes files, reads credentials, mutates `$env`, or executes user-provided paths/patterns, explicitly confirm the safe argument boundaries and failure behavior.

## Core Principles

1. **Think in pipelines** — Data flows through pipelines; prefer functional transformations over imperative loops
2. **Immutability first** — Use `let` by default; only use `mut` when functional alternatives don't apply
3. **Structured data** — Nushell works with tables, records, and lists natively; leverage structured data over string parsing
4. **Static parsing** — All code is parsed before execution; `source`/`use` require parse-time constants
5. **Implicit return** — The last expression's value is the return value; no need for `echo` or `return`
6. **Scoped environment** — Environment changes are local to their block; use `def --env` when caller-side changes are needed
7. **Type safety** — Annotate parameter types and input/output signatures; Nu 0.114+ checks more at parse time and enforces assignment annotations at runtime by default
8. **Prefer `match` for branching** — Use `match` instead of long `if`/`else if` chains when dispatching on one value or handling many branches
9. **Parallel ready** — Immutable code enables easy `par-each` parallelization

## Nu 0.114+ Version Notes

Nu 0.114 tightened type checking and added several commands that should change
how scripts are written and reviewed:

- `$in`, pipeline `let` bindings, `def` blocks, `if`, and `match` are typed more
  precisely. Treat new parse-time errors as useful signal; do not work around
  them with `any` unless the code is genuinely polymorphic.
- Optional positional parameters and named flags without defaults are
  `oneof<T, nothing>`. Add a default or handle `null` before assigning to `T`,
  doing arithmetic, or promising a non-null return type.
- `if` without `else` and `match` without `_` can output `nothing`. Add an
  explicit fallback when the surrounding pipeline or signature requires a value.
- `enforce-runtime-annotations` is enabled by default. Runtime `let` assignment
  annotations are checked, so stale type annotations now fail earlier.
- Importing a module no longer implicitly imports its exported submodules.
  Re-export submodules explicitly with `export use submodule` or
  `export use submodule *` when callers need the old surface.
- Builtins, custom commands, and `def --wrapped` understand POSIX-style `--` as
  an end-of-options delimiter. Use it when dash-prefixed values are positional
  data; decide deliberately whether wrappers should skip or forward the token.
- Use `run script.nu` when a script should act as a pipeline stage. It accepts
  pipeline input, invokes `def main` when present, runs isolated from the parent
  scope, and supports `run --full-reparse` for watch/repeated execution loops.
- Use `into semver`, `into semver-range`, and `semver bump` for release/version
  logic instead of string splitting or lexical sort.
- Prefer `str uppercase` / `str lowercase`; `str upcase` / `str downcase` are
  deprecated.
- `from xlsx` and `from ods` return records of sheet tables. Use `--noheaders`,
  `--first-row`, and `--prefer-integers` instead of old `--header-row` patterns.
- In `try/catch`, use `$err.details` for structured diagnostics; `$err.json` is
  gone. Labels may include file-relative `location` in addition to `span`.

## Critical: Pipeline Input vs Parameters

**Pipeline input (`$in`) is NOT interchangeable with function parameters!**

```nu
# WRONG — treats pipeline data as first parameter
def my-func [items: list, value: any] {
    $items | append $value
}

# CORRECT — declares pipeline signature
def my-func [value: any]: list -> list {
    $in | append $value
}

# Usage
[1 2 3] | my-func 4  # Works correctly
```

**Why this matters:**

- Pipeline input can be **lazily evaluated** (streaming)
- Parameters are **eagerly evaluated** (loaded into memory)
- Different calling conventions entirely — `$list | func arg` vs `func $list arg`

### Type signature forms

```nu
def func [x: int] { ... }                    # params only
def func []: string -> int { ... }           # pipeline only
def func [x: int]: string -> int { ... }     # both pipeline and params
def func []: [list -> list, string -> list] { ... }  # multiple I/O types
```

## Naming Conventions

| Entity           | Convention             | Example                              |
| ---------------- | ---------------------- | ------------------------------------ |
| Commands         | `kebab-case`           | `fetch-user`, `build-all`            |
| Subcommands      | `kebab-case`           | `"str my-cmd"`, `date list-timezone` |
| Flags            | `kebab-case`           | `--all-caps`, `--output-dir`         |
| Variables/Params | `snake_case`           | `$user_id`, `$file_path`             |
| Environment vars | `SCREAMING_SNAKE_CASE` | `$env.APP_VERSION`                   |
| Constants        | `snake_case`           | `const max_retries = 3`              |

- Prefer full words over abbreviations unless widely known (`url` ok, `usr` not ok)
- Flag variable access replaces dashes with underscores: `--all-caps` -> `$all_caps`

## Formatting Rules

### One-line format (default for short expressions)

```nu
[1 2 3] | each {|x| $x * 2 }
{name: 'Alice', age: 30}
```

### Multi-line format (scripts, >80 chars, nested structures)

```nu
[1 2 3 4] | each {|x|
    $x * 2
}

[
    {name: 'Alice', age: 30}
    {name: 'Bob', age: 25}
]
```

### Spacing rules

- One space before and after `|`
- No space before `|params|` in closures: `{|x| ...}` not `{ |x| ...}`
- One space after `:` in records: `{x: 1}` not `{x:1}`
- Omit commas in lists: `[1 2 3]` not `[1, 2, 3]`
- No trailing spaces
- One space after `,` when used (closure params, etc.)

## Custom Commands Best Practices

### Type annotations and I/O signatures

```nu
# Fully typed with I/O signature
def add-prefix [text: string, --prefix (-p): string = 'INFO']: nothing -> string {
    $'($prefix): ($text)'
}

# Multiple I/O signatures
def to-list []: [
    list -> list
    string -> list
] {
    # implementation
}
```

### Documentation with comments and attributes

```nu
# Fetch user data from the API
#
# Retrieves user information by ID and returns
# a structured record with all available fields.
@example 'Fetch user by ID' { fetch-user 42 }
@category 'network'
def fetch-user [
    id: int           # The user's unique identifier
    --verbose (-v)    # Show detailed request info
]: nothing -> record {
    # implementation
}
```

### Parameter guidelines

- Maximum 2 positional parameters; use flags for the rest
- Provide both long and short flag names: `--output (-o): string`
- Use default values: `def greet [name: string = 'World']`
- Use `?` for optional positional params: `def greet [name?: string]`
- Use rest params for variadic input: `def multi-greet [...names: string]`
- Use `def --wrapped` to wrap external commands and forward unknown flags

### Calling commands with named flags

Keep short custom command calls with named flags on one line. If the invocation
must span lines, wrap the whole command in parentheses so the continuation is
explicit. A bare newline can terminate the command, leaving following `--flags`
as separate statements that produce plain output or parse errors.

```nu
# Prefer for short calls
build-report $target --format json --strict

# Good — explicit multiline invocation
let report = (
    build-report $target
        --format json
        --strict
)

# Bad — flags start new statements
build-report $target
--format json
--strict
```

### Environment-modifying commands

```nu
def --env setup-project [] {
    cd project-dir
    $env.PROJECT_ROOT = (pwd)
}
```

## Data Manipulation Patterns

### Working with records

```nu
{name: 'Alice', age: 30}          # Create record
$rec1 | merge $rec2                # Merge (right-biased)
[$r1 $r2 $r3] | into record       # Merge many records
$rec | update name {|r| $'Dr. ($r.name)' }  # Update field
$rec | insert active true          # Insert field
$rec | upsert count {|r| ($r.count? | default 0) + 1 }  # Update or insert
$rec | reject password secret_key  # Remove fields
$rec | select name age email       # Keep only these fields
$rec | items {|k, v| $'($k): ($v)' }  # Iterate key-value pairs
$rec | transpose key val           # Convert to table
```

### Working with tables

```nu
$table | where age > 25                          # Filter rows
$table | insert retired {|row| $row.age > 65 }   # Add column
$table | rename -c {age: years}                   # Rename column
$table | group-by status --to-table               # Group by field
$table | transpose name data                      # Transpose rows/columns
$table | join $other_table user_id                 # Inner join
$table | join --left $other user_id                # Left join
```

### Working with lists

```nu
$list | enumerate | where {|e| $e.index > 5 }     # Filter with index
$list | reduce --fold 0 {|it, acc| $acc + $it }   # Accumulate
$list | window 3                                   # Sliding window
$list | chunks 100                                 # Process in batches
$list | flatten                                    # Flatten nested lists
$list | append 4 5 6                               # Append multiple values
$list | union $other                               # Deduplicated union
$list | intersect $other                           # Deduplicated intersection
$list | difference $other                          # Values only in left list
$list | combinations 2                             # Lazy k-combinations
$list | permutations                               # Lazy permutations
```

### Null safety

```nu
$record.field?                    # Returns null if missing (no error)
$record.field? | default 'N/A'   # Provide fallback
if ($record.field? != null) { }   # Check existence
$list | default -e $fallback      # Default for empty collections
```

`default`'s argument is **eager**: `$x | default $rec.maybe_missing` evaluates (and can error on) the fallback even when `$x` is non-null. Make the fallback null-safe (`default ($rec.maybe? | default 0)`) or branch with `if`. See [Anti-Patterns](references/anti-patterns.md).

### Large data: Polars dataframes

Native `list`/`table` ops are row-oriented — ideal for small, interactive data.
For **large datasets** and **heavy analytics** (multi-million row group-by,
joins, aggregations, big CSV/Parquet), push the work into the `polars` plugin's
columnar dataframes instead of `each`/`reduce`. They are lazy by default.

```nu
# For large data, let Polars plan and execute the whole pipeline:
polars open big.csv                       # lazy by default (a plan, not yet run)
| polars group-by category
| polars agg (polars col amount | polars sum | polars as total)
| polars sort-by total -r [true]
| polars collect                          # execute the optimized plan once
```

Beyond group-by/join, Polars covers window/sequence ops (`over`, `shift`,
`cumulative`, `rolling`), nested list/struct data (`explode`, `unnest`),
reshaping (`pivot`/`unpivot`), time zones, SQL (`polars query`), and a
Nushell-closure escape hatch (`map-batches`). Choose native vs Polars (and eager
vs lazy), and see the full command set, in [Dataframes](references/dataframes.md).

## Pipeline & Functional Patterns

### Prefer functional over imperative

```nu
# Bad — imperative with mutable variable
mut total = 0
for item in $items { $total += $item.price }

# Good — functional pipeline
$items | get price | math sum

# Bad — mutable counter
mut i = 0
for file in (ls) { print $'($i): ($file.name)'; $i += 1 }

# Good — enumerate
ls | enumerate | each {|it| $'($it.index): ($it.item.name)' }
```

### Iteration patterns

```nu
# each: transform each element
$list | each {|item| $item * 2 }

# each --flatten: stream outputs (turns list<list<T>> into list<T>)
ls *.txt | each --flatten {|f| open $f.name | lines } | find 'TODO'

# each --keep-empty: preserve null results
[1 2 3] | each --keep-empty {|e| if $e == 2 { 'found' } }

# par-each: parallel processing (I/O or CPU-bound)
$urls | par-each {|url| http get $url }
$urls | par-each --threads 4 {|url| http get $url }

# reduce: accumulate (first element is initial acc if no --fold)
[1 2 3 4] | reduce {|it, acc| $acc + $it }

# generate: create values from arbitrary sources without mut
generate {|state| { out: ($state * 2), next: ($state + 1) } } 1 | first 5
```

### Row conditions vs closures

```nu
# Row conditions — short-hand syntax, auto-expands $it
ls | where type == file              # Simple and readable
$table | where size > 100            # Expands to: $it.size > 100

# Closures — full flexibility, can be stored and reused
let big_files = {|row| $row.size > 1mb }
ls | where $big_files
$list | where {$in > 10}             # Use $in or parameter
```

**Use row conditions** for simple field comparisons; **use closures** for complex logic or reusable conditions.

### Branching with `match`

Nushell's `match` is a parser keyword: `match <value> <match_block>`.
Prefer it over `if`/`else if` chains when multiple branches depend on the same
value, such as status dispatch, command routing, type guards, or enum-like
options. Use `if` for a single boolean condition or when each branch has a
different predicate.

```nu
# Less clear — repeated checks against the same value
if $status == 'ok' {
    handle-ok
} else if $status == 'error' {
    handle-error
} else if $status == 'pending' {
    handle-pending
} else {
    handle-unknown
}

# Preferred — one dispatch expression with an explicit fallback
match $status {
    ok => { handle-ok }
    error => { handle-error }
    pending => { handle-pending }
    _ => { handle-unknown }
}
```

### Pipeline input with $in

```nu
def double-all []: list<int> -> list<int> {
    $in | each {|x| $x * 2 }
}

# Capture $in early when needed later (it's consumed on first use)
def process []: table -> table {
    let input = $in
    let count = $input | length
    $input | first ($count // 2)
}
```

## Variable Best Practices

### Prefer immutability

```nu
let config = (open config.toml)
let names = $config.users | get name

# Acceptable — mut when no functional alternative
mut retries = 0
loop {
    if (try-connect) { break }
    $retries += 1
    if $retries >= 3 { error make {msg: 'Connection failed'} }
    sleep 1sec
}
```

### Constants for parse-time values

```nu
const lib_path = 'src/lib.nu'
source $lib_path                  # Works: const is resolved at parse time

let lib_path = 'src/lib.nu'
source $lib_path                  # Error: let is runtime only
```

When a parse-time path needs to point inside the user's home directory, compute
it from `$nu.home-dir` instead of hardcoding a machine-specific absolute path.

```nu
# Good — portable across users and machines
const work_dir = $'($nu.home-dir)/work/dir'

# Bad — hardcoded user home path
const work_dir = '/user/name/work/dir'
```

### Closures cannot capture mut

```nu
mut count = 0
ls | each {|f| $count += 1 }     # Error! Closures can't capture mut

# Solutions:
ls | length                       # Use built-in commands
[1 2 3] | reduce {|x, acc| $acc + $x }  # Use reduce
for f in (ls) { $count += 1 }    # Use a loop if mutation truly needed
```

## String Conventions

Refer to [String Formats Reference](references/string-formats.md) for the full priority and rules.

String form mistakes are common and high impact. Decide with this table before writing or reviewing any string:

| Need | Use | Do not use |
| --- | --- | --- |
| Simple literal text | `'hello world'` | `"hello world"` or `$"hello world"` |
| Simple values inside arrays or match arms | `[foo bar baz]`, `match $x { ok => ... }` | `["foo" "bar" "baz"]` when quotes add no meaning |
| Interpolation without escape sequences | `$'User: ($name)'` | `$"User: ($name)"` |
| Literal escape sequence such as newline or tab | `"line1\nline2"` | `'line1\nline2'` |
| Interpolation plus real escape sequences | `$"($name)\n"` | `$'($name)\n'` |
| Regex pattern or text with many quotes/backslashes | `r#'name="[^"]+"'#` | `"name=\"[^\"]+\""` |
| Path or glob argument with spaces | `` `./My Dir/*.nu` `` | Escaped Bash-style strings |

**Decision order:**

1. Bare words in arrays: `[foo bar baz]`
2. Raw strings for regex: `r#'(?:pattern)'#`
3. Single quotes: `'simple string'`
4. Single-quoted interpolation: `$'Hello, ($name)!'`
5. Backticks for path/glob arguments containing spaces: `` `./My Dir/*.nu` ``
6. Double quotes only for real escapes: `"line1\nline2"`
7. Double-quoted interpolation only when both interpolation and escapes are required: `$"tab:\t($value)\n"`

**Non-negotiable string rules:**

- `$'...'` and `'...'` do not process escapes. `\n`, `\t`, and `\'` remain literal characters.
- A string containing `(...)` only evaluates it when prefixed with `$`: `$'(ansi g)OK(ansi rst)'`, not `'(ansi g)OK(ansi rst)'`.
- Use `char nl` inside `$'...'` when interpolation is needed but the only escape-like value is a newline: `$'(char nl)Done'`.
- Use `$"..."` only when the final string truly needs escape processing and interpolation in the same literal.
- Do not build shell command strings for execution. Pass arguments separately: `^git commit -m $msg`, not `^sh -c $'git commit -m "($msg)"'`.
- For external command format strings, prefer double-quoted strings with a single escape backslash for simple escapes (`^git log --format="%H\t%an"`). Do not double the backslash (`"%H\\t%an"`), because that produces a literal `\t`. Use `(char tab)` / `(char nl)` when interpolation is needed or explicit separators are clearer.
- For regex literals, prefer raw strings and add `#` delimiters when the pattern contains quotes: `r#'name="[^"]+"'#`.

**Common corrections:**

```nu
# Wrong: interpolation is missing because there is no $ prefix
print 'User: ($name)'
# Right
print $'User: ($name)'

# Wrong: $'...' does not turn \n into a newline
print $'Done\n'
# Right: command interpolation, no escape processing needed
print $'Done(char nl)'
# Right: escape processing is required
print $"Done\n"

# Wrong: double-quoted interpolation without escapes
let label = $"($pkg.name)@($pkg.version)"
# Right
let label = $'($pkg.name)@($pkg.version)'

# Wrong: regex backslashes are hard to audit
let pattern = "(?:src|lib)/.*\\.nu"
# Right
let pattern = r#'(?:src|lib)/.*\.nu'#

# Wrong: single quotes pass literal \t to the external formatter
^git log --format='%H\t%an'
# Wrong: double backslash preserves literal \t
^git log --format="%H\\t%an"
# Preferred: Nushell turns \t into an actual tab before calling git
^git log --format="%H\t%an"
# Also right: explicit separator, useful with interpolation
let tab = (char tab)
^git log --format=$'%H($tab)%an'
```

## Modules & Scripts

### Module structure

```
my-module/
├── mod.nu              # Module entry point
├── utils.nu            # Submodule
└── tests/
    └── mod.nu          # Test module
```

### Export rules

- Only `export` definitions are public; non-exported are private
- Use `export def main` when command name matches module name
- Use `export use submodule.nu *` to re-export submodule commands
- Use `export-env` for environment setup blocks
- In Nu 0.114+, exported submodules are not imported implicitly. If callers
  need `my-module sub cmd`, re-export `sub` explicitly from `mod.nu`.

```nu
export module sub {
    export def cmd [] { 'ok' }
}
export use sub          # Keep `my-module sub cmd` available after `use my-module`
```

### Script with main command and subcommands

```nu
#!/usr/bin/env nu

# Build the project
def "main build" [--release (-r)] {
    print 'Building...'
}

# Run tests
def "main test" [--verbose (-v)] {
    print 'Testing...'
}

def main [] {
    print 'Usage: script.nu <build|test>'
}
```

For stdin access in shebang scripts: `#!/usr/bin/env -S nu --stdin`

### Pipeline scripts with `run`

Use `run` when a `.nu` script is meant to participate in a pipeline rather than
be invoked as a process with `nu script.nu`. A bare script body acts as a
pipeline transform; if the script defines top-level `def main`, `run` calls it.

```nu
# shout.nu
str uppercase

'Hello Nushell!' | run shout.nu | str camel-case
```

`run` is a parser keyword: the script file must already exist when the calling
block is parsed. It resolves scripts from the current directory, `NU_LIB_DIRS`,
or an explicit path, but not from `PATH`. It runs isolated from the parent scope,
so definitions and local changes do not leak back. Use
`run --full-reparse script.nu` in watch loops or repeated test runs when the
script file is changing.

## Error Handling

### Custom errors with span info

```nu
def validate-age [age: int] {
    if $age < 0 or $age > 150 {
        error make {
            msg: 'Invalid age value'
            label: {
                text: $'Age must be between 0 and 150, got ($age)'
                span: (metadata $age).span
            }
        }
    }
    $age
}
```

### try/catch and graceful degradation

```nu
let result = try {
    http get $url
} catch {|err|
    print -e $'Request failed: ($err.msg)'
    null
}

# Nu 0.114+: structured diagnostic details live at $err.details, not $err.json
let details = try {
    risky-command
} catch {|err|
    $err.details
}

# Use complete for detailed external command error info
let result = (^some-external-cmd | complete)
if $result.exit_code != 0 {
    print -e $'Error: ($result.stderr)'
}
```

### Suppress errors with `do -i`

`do -i` (ignore errors) runs a closure and suppresses any errors, returning null on failure. `do -c` (capture errors) catches errors and returns them as values.

```nu
# Ignore errors — returns null if the closure fails
do -i { rm non_existent_file }

# Use as a concise fallback
let val = (do -i { open config.toml | get setting } | default 'fallback')

# Capture errors as values (instead of aborting the pipeline)
let result = (do -c { ^some-cmd })
```

**When to use each approach:**

- `do -i` — Fire-and-forget, or when you only need a default on failure
- `do -c` — Catch errors as values to abort downstream pipeline on failure
- `try/catch` — When you need to inspect or log the error
- `complete` — When you need exit code + stdout + stderr from external commands

### Ignore stream output precisely

Nu 0.114 added flags to `ignore` for stream/error control:

- `ignore --stderr` / `-e` consumes stderr while stdout continues
- `ignore --stdout` / `-o` consumes stdout while stderr continues
- `ignore --show-errors` / `-x` shows errors and updates `$env.LAST_EXIT_CODE`

Use these when a conversion from Bash redirects only one stream to `/dev/null`.

## Testing

### Using std assert

```nu
use std/assert

for t in [[input expected]; [0 0] [1 1] [2 1] [5 5]] {
    assert equal (fib $t.input) $t.expected
}
```

### Custom assertions

```nu
def "assert even" [number: int] {
    assert ($number mod 2 == 0) --error-label {
        text: $'($number) is not an even number'
        span: (metadata $number).span
    }
}
```

## Debugging Techniques

```nu
$value | describe                 # Inspect type
$data | each {|x| print $x; $x } # Print intermediate values (pass-through)
timeit { expensive-command }      # Measure execution time
metadata $value                   # Inspect span and other metadata
```

## Security Best Practices

Refer to [Security Reference](references/security.md) for the full guide.

Nushell is safer than Bash by design (no `eval`, arguments passed as arrays not through shell), but security risks remain.

### Never execute untrusted input as code

```nu
# DANGEROUS — arbitrary code execution
^nu -c $user_input
source $user_provided_file

# DANGEROUS — shell interprets the string
^sh -c $'echo ($user_input)'
^bash -c $user_input
```

Validating a command _string_ (e.g. an allowlist regex) before `nu -c` is **not** sufficient: `\s` matches newlines, regex shortcuts like `\b`/`\w` are not command-token rules, and the string is still re-interpreted. Prefer validated argv/list data and run the binary with separated args instead. See [Security](references/security.md).

### Separate commands from arguments (prevent injection)

```nu
# Bad — constructing command strings
let cmd = $'ls ($user_path)'
^sh -c $cmd

# Good — pass arguments directly (no shell interpretation)
^ls $user_path
run-external 'ls' $user_path
```

### Validate and sanitize paths

```nu
# Bad — path traversal possible
def read-file [name: string] { open $name }

# Good — validate against traversal
def read-file [name: string, --base-dir: string = '.'] {
    let full = ($base_dir | path join $name | path expand)
    let base = ($base_dir | path expand)
    if not ($full | str starts-with $base) {
        error make {msg: $'Path traversal detected: ($name)'}
    }
    open $full
}
```

### Protect credentials

```nu
# Bad — credential visible to all child processes and in env
$env.API_KEY = 'secret-key-123'
^curl -H $'Authorization: Bearer ($env.API_KEY)' $url

# Good — scope credentials, use with-env
with-env {API_KEY: (open ~/.secrets/api_key | str trim)} {
    ^curl -H $'Authorization: Bearer ($env.API_KEY)' $url
}
```

### Safe file operations

```nu
# Bad — predictable temp file, race condition
let tmp = '/tmp/my-script-tmp'
'data' | save $tmp

# Good — use mktemp for unique temp files
let tmp = (^mktemp | str trim)
'data' | save $tmp
# ... use $tmp ...
rm $tmp
```

### Handle external command errors

```nu
let result = (^cargo build o+e>| complete)
if $result.exit_code != 0 {
    error make {msg: $'Build failed: ($result.stderr)'}
}
```

### Safe rm operations

```nu
# Bad — glob from variable, could match unintended files
^rm $'($user_dir)/*'

# Good — validate then use trash or explicit paths
if ($user_dir | path type) == 'dir' {
    rm -r $user_dir
}
```

## Script Review Checklist

Refer to [Script Review Reference](references/script-review.md) for the full checklist.

When reviewing a Nushell script, check these categories in order:

### 1. Security review (highest priority)

- [ ] No `nu -c` / `source` / `^sh -c` with untrusted input
- [ ] No credential hardcoding or env leaking
- [ ] Paths from user input are validated (no traversal)
- [ ] Home-directory paths are computed from `$nu.home-dir`, not hardcoded user paths
- [ ] External commands use argument separation (not string concatenation)
- [ ] Temp files use `mktemp`, not predictable paths
- [ ] `rm` operations are guarded and intentional

### 2. Correctness review

- [ ] Type annotations on all exported commands
- [ ] I/O pipeline signatures match actual behavior
- [ ] Error handling with `try/catch` for fallible operations
- [ ] External commands checked with `complete` when error handling matters
- [ ] Optional fields accessed with `?` operator
- [ ] Optional params/flags without defaults are treated as `oneof<T, nothing>`
- [ ] `if`/`match` expressions have fallbacks when a non-null output is required
- [ ] No `for` as final expression (use `each` instead)
- [ ] Long `if`/`else if` chains on one value prefer `match` unless `if` is clearer
- [ ] `mut` not captured in closures
- [ ] `parse` gets `lines` first when line-by-line parsing of stream input is intended
- [ ] Multiline custom command calls with named flags are one-line or wrapped in parentheses
- [ ] Submodules are explicitly re-exported when callers depend on them
- [ ] `try/catch` diagnostics use `$err.details`, not removed `$err.json`
- [ ] Version/release logic uses `semver` values instead of lexical strings

### 3. Style review

- [ ] Naming: kebab-case commands, snake_case variables
- [ ] String format priority followed: simple literal -> `'...'`; interpolation without escapes -> `$'...'`; escapes -> `"..."`; interpolation plus escapes -> `$"..."`; regex -> `r#'...'#`
- [ ] Strings containing `(...)` that should run Nushell expressions have `$` prefix
- [ ] `$'...'` is not used for `\n`, `\t`, `\'`, or other escape processing
- [ ] External command format strings use double quotes for simple escapes, or `char tab` / `char nl` when interpolation is needed
- [ ] Formatting: spacing, line length, multi-line rules
- [ ] Documentation comments on exported commands
- [ ] `^` prefix on external commands
- [ ] Functional style preferred over imperative

### 4. Performance review

- [ ] `par-each` for I/O or CPU-bound parallel work
- [ ] `each --flatten` for streaming when appropriate
- [ ] `peek` used when inspecting stream metadata/sample values without collecting
- [ ] Expensive computations cached in `let` bindings
- [ ] Large files streamed (lazy), not loaded entirely
- [ ] Large/columnar datasets and heavy group-by/join use Polars dataframes (lazy), not native loops

## Common Pitfalls

Refer to [Anti-Patterns Reference](references/anti-patterns.md) for detailed explanations.

| Anti-Pattern                                         | Fix                                                                              |
| ---------------------------------------------------- | -------------------------------------------------------------------------------- |
| `echo $value`                                        | Just `$value` (implicit return)                                                  |
| `echo 'msg'` to print output                         | `print 'msg'` (`echo` returns a value; non-final value is dropped)               |
| `$"simple text"`                                     | `'simple text'` (no interpolation needed)                                        |
| `'User: ($name)'`                                    | `$'User: ($name)'`                                                               |
| `$'line\n'`                                          | `$"line\n"` or `$'line(char nl)'`                                                |
| `"[a-z]+\\.nu"`                                      | `r#'[a-z]+\.nu'#`                                                                |
| `for` as final expression                            | Use `each` (for doesn't return a value)                                          |
| `mut` for accumulation                               | Use `reduce` or `math sum`                                                       |
| Long `if`/`else if` chains on one value              | Prefer `match` with `_` fallback                                                 |
| `let path = ...; source $path`                       | `const path = ...; source $path`                                                 |
| `const work_dir = '/user/name/work/dir'`             | `const work_dir = $'($nu.home-dir)/work/dir'`                                    |
| `"hello" > file.txt`                                 | `'hello' \| save file.txt`                                                       |
| `grep pattern`                                       | `where $it =~ pattern` or built-in `find`                                        |
| Parsing string output                                | Use structured commands (`ls`, `ps`, `http get`)                                 |
| `$env.FOO = bar` inside `def`                        | Use `def --env`                                                                  |
| `{ \| x \| ... }` (space before pipe)                | `{\|x\| ...}` (no space before params)                                           |
| `$record.missing` (error)                            | `$record.missing?` (returns null)                                                |
| `val \| default $rec.missing` (arg is eager)         | `default ($rec.missing? \| default ...)` (fallback evaluated even when non-null) |
| `each` on single record                              | Use `items` or `transpose` instead                                               |
| External cmd without `^`                             | Use `^grep` to be explicit about externals                                       |
| Native loop/`group-by` on huge data                  | Use `polars` dataframes (lazy `open` + `group-by` + `collect`)                   |
| `parse` on stream expecting old line splitting       | Insert `lines` before `parse` for line-by-line parsing                           |
| Custom command flags on new lines                    | Keep one line or wrap the invocation in `(...)`                                  |
| Single-quoted or double-escaped external format `\t` | Use `"%H\t%an"` or `(char tab)` / `(char nl)`                                    |
| `use foo` expecting `foo sub cmd` automatically       | Re-export submodules explicitly with `export use sub` in Nu 0.114+               |
| Optional arg used as plain `int`/`string`             | Add a default or handle `null` before use                                        |
| `catch {|err| $err.json \| from json }`               | Use `$err.details` directly                                                     |
| `str upcase` / `str downcase`                         | Use `str uppercase` / `str lowercase`                                           |
| SemVer sorted or bumped as plain strings              | Use `into semver`, `into semver-range`, and `semver bump`                        |
| `from xlsx --header-row ...`                          | Use `--noheaders`, `--first-row`, and `--prefer-integers` as needed              |

## Best Practices Summary

1. **Use type signatures** — Catch errors early, improve documentation
2. **Prefer pipelines** — More idiomatic, composable, and streamable
3. **Document with comments** — `#` above `def` for help integration
4. **Export selectively** — Don't pollute namespace
5. **Use `default`** — Handle null/missing gracefully
6. **Validate inputs** — Check types/ranges at function start
7. **Return consistent types** — Don't mix null and values unexpectedly
8. **Use modules** — Organize related functions
9. **Prefix external commands with `^`** — `^grep` not `grep`; Nushell builtins take precedence (e.g., `find` is Nushell's, not Unix `find`)
10. **Use external tools when faster** — `^rg` for large file search, `^jq` for giant JSON
11. **Group multiline command calls** — Keep named-flag invocations one-line or wrap them in `(...)`
12. **Use clear separators in external formats** — Prefer double-quoted escapes when no interpolation is needed; use `(char tab)` / `(char nl)` when interpolation or explicit separators are needed
13. **Use Nu 0.114 builtins for common domains** — `run` for pipeline scripts, SemVer commands for versions, set-operation commands for lists

## Do Not Do These Things

- Do not replace every quoted value with double quotes. Double quotes are for escape processing.
- Do not use `$"..."` just because a string contains interpolation; use `$'...'` unless escapes are required.
- Do not assume `\'`, `\n`, or `\t` work inside single-quoted or single-interpolated strings.
- Do not expect single-quoted or double-escaped external format strings to process `\t` or `\n`; use one backslash in double quotes, `(char tab)`, or `(char nl)`.
- Do not remove `$` from strings containing command interpolation such as `(ansi g)`, `(char nl)`, or `($value)`.
- Do not use `echo` to print user-facing messages — `echo` has no print side effect; its returned value is shown only when it becomes final output. Use `print` for side-effect output (`echo 'msg'; exit 1` prints nothing).
- Do not split named flags for a custom command onto new statement lines; keep one line or wrap the invocation in parentheses.
- Do not convert user input into `nu -c`, `source`, `^sh -c`, `^bash -c`, or `^cmd.exe /C` strings.
- Do not execute user-controlled `.nu` paths with `run` or `source` unless the path and trust boundary are explicit.
- Do not depend on implicit submodule imports in Nu 0.114+; re-export the intended submodule surface.
- Do not parse structured Nushell output as plain strings when a record/table/list operation exists.
- Do not run destructive examples during validation; parse-check them or use a temp fixture.

## Workflow

When writing or reviewing Nushell code:

1. **Read existing code** to understand the context
2. **Security audit** — Check for injection, path traversal, credential leaks (see [Security](references/security.md))
3. **Check naming** — kebab-case commands, snake_case variables
4. **Check types** — Add/verify type annotations and I/O signatures
5. **Check Nu 0.114 semantics** — Optional `nothing`, typed `$in`, explicit submodule imports, `$err.details`, deprecated commands
6. **Check strings** — Follow the string format priority
7. **Check branching** — Prefer `match` over long `if`/`else if` chains on one value
8. **Check patterns** — Prefer functional pipelines over imperative loops
9. **Check formatting** — Spacing, line length, multi-line rules
10. **Check documentation** — Comments for exported commands, parameter descriptions
11. **Check error handling** — try/catch, complete for externals, validate inputs
12. **Run validation** if possible — `nu -c 'source file.nu'` or `nu file.nu`
13. **Summarize changes** made with security findings highlighted

## References

- [Security](references/security.md) — Security hardening, threat model, safe patterns
- [Script Review](references/script-review.md) — Comprehensive review checklist
- [String Formats](references/string-formats.md) — String type priority and conversion rules
- [Anti-Patterns](references/anti-patterns.md) — Common mistakes with detailed fixes
- [Data & Type System](references/data-and-types.md) — Type hierarchy, collections, conversions, type guards
- [Dataframes](references/dataframes.md) — Polars dataframes: lazy/eager, group-by, joins, window/sequence ops, nested list/struct data, reshaping, time zones, SQL, large-data processing
- [Advanced Patterns](references/advanced-patterns.md) — Performance, streaming, closures, memory efficiency
- [Modules & Scripts](references/modules-and-scripts.md) — Module system, testing, attributes
- [Bash to Nushell](references/bash-to-nushell.md) — Conversion guide from Bash/POSIX

## Getting Help

- Use `nu -c 'help <command>'` to check command signatures and examples
- Use Nushell MCP tools for evaluating and testing Nushell code when they are exposed; otherwise use local `nu -c` probes
- Consult the [Nushell Book](https://www.nushell.sh/book/) for in-depth documentation
