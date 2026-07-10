# Advanced Nushell Patterns Reference

## Contents

- Performance and memory-efficient patterns
- Nu 0.113/0.114 command behavior
- Closures, streams, and iteration pitfalls
- Error handling and stable diagnostics
- Globs, custom data, row conditions, and debugging

## Performance Optimization

### Lazy vs eager evaluation

```nu
# Lazy (streaming) — memory efficient for large data, single-pass
open large.csv | where status == 'active' | first 10

# Eager (load all) — faster for small data with multiple operations
let data = (open large.csv | where status == 'active')
$data | first 10
$data | last 10
$data | length
```

**Use lazy when:** Large files/streams, single-pass operations, memory constrained
**Use eager when:** Small datasets (<10k rows), multiple operations on same data, random access needed

> The lazy/eager split above is about **native** row-oriented streaming. For
> **columnar** large-data work (heavy group-by/join/aggregation over big
> CSV/Parquet), use the Polars plugin's lazy dataframes instead — see
> [Dataframes](dataframes.md).

### Inspect streams without collecting: `peek`

Use `peek` when a command needs to inspect whether input is a stream, or sample
the first few values, without forcing the whole stream into memory. It exposes
the information through pipeline metadata, which you read with `metadata access`.

```nu
.. | peek 1 | metadata access {|md|
    if $md.peek.stream {
        # Keep the stream lazy; do not call `collect` just to inspect it.
        $in
    } else if ($md.peek.value?.0? != null) {
        $in
    }
}
```

This is useful for commands that want different behavior for lists vs streams,
or that need to decide based on a small sample while preserving streaming.

### Avoid repeated computation

```nu
# Bad — computes expensive-func 3 times
if (expensive-func) > 10 {
    print (expensive-func)
    save-to-file (expensive-func)
}

# Good — compute once
let result = expensive-func
if $result > 10 {
    print $result
    save-to-file $result
}
```

### Parallel processing

```nu
# Sequential
$urls | each {|url| http get $url }

# Parallel — faster for I/O operations
$urls | par-each {|url| http get $url }

# With thread pool size
$urls | par-each --threads 4 {|url| http get $url }
```

**Best for:** I/O operations, CPU-intensive transforms, independent operations
**Avoid for:** Small lists (overhead > benefit), side effects, order-dependent processing

### Stream flattening with each --flatten

```nu
# Without --flatten: waits for each stream to complete, returns list<list<string>>
ls *.txt | each {|f| open $f.name | lines }

# With --flatten: streams items as they arrive, returns list<string>
ls *.txt | each --flatten {|f| open $f.name | lines }

# Practical: search across files without waiting for all to load
ls **/*.nu | each --flatten {|f|
    open $f.name | lines | find 'export def'
} | str join (char nl)
```

## Memory-Efficient Patterns

### Processing large files

```nu
# Bad — loads entire file into memory then filters
open large.log | lines | where {$in =~ 'ERROR'}

# Good — streams line by line
open large.log | lines | each --flatten {|line|
    if ($line =~ 'ERROR') { $line }
}
```

### Batched processing

```nu
# Process in chunks of 1000
open large.csv | chunks 1000 | each {|batch|
    $batch | process-batch
} | flatten
```

### `parse` stream behavior in 0.113+

`parse` no longer implicitly splits byte/string streams into lines. It collects
the stream and parses it as one input value. If you intend line-by-line parsing,
insert `lines` explicitly:

```nu
# Whole-input parse: useful for multiline regexes
open file.txt | parse -r r#'(?ms)^(?<id>\d+): (?<body>.*)$'#

# Line-by-line parse
open file.txt | lines | parse -r '^(?<level>\w+) (?<message>.*)$'
```

## Command Behavior Notes (0.113 / 0.114+)

- `mkdir -v`, `mv -v`, and `rm -v` return structured tables. Script against
  columns such as `path`, `created`, `deleted`, `error`, and `message` instead
  of parsing human text.
- `rm` and `mkdir` try the remaining path arguments even when one path errors.
  Review partial-success behavior for destructive or setup scripts.
- `from md` now defaults to concise output. Use `from md --verbose` when code
  needs the full AST-style detail.
- `watch`'s optional closure argument is deprecated. Pipe events into `each` or
  iterate with `for event in (watch ...)`.
- `grid` no longer accepts a single record as input and no longer relies on the
  implicit `name` column. Pass a table and the column explicitly, for example
  `ls | grid name`.
- `metadata set --datasource-ls` was removed. Use
  `metadata set --path-columns [name]` for path metadata on table columns.
- On Unix-like systems, `kill -9 pid` shorthand is no longer accepted. Use
  `kill -s 9 <pid>` (or `kill -s 0 <pid>` for signal 0 checks).
- `finally` runs for cleanup but its return value does not override `try` or
  `catch`. Use the `try`/`catch` result for values and keep `finally` for side
  effects such as cleanup.
- In 0.113.1, `to yaml` emits more idiomatic plain scalars where safe and uses
  block style for multiline strings. Do not assert exact quotes around every
  string in YAML golden tests.
- Nu 0.114 supports POSIX-style `--` for builtins, custom commands, and
  `def --wrapped` commands. Use it for dash-prefixed positional values; known
  externs still receive `--` and parse it themselves.
- Use `run script.nu` for reusable pipeline-stage scripts. It is a parser
  keyword, so the script must exist when the calling block is parsed. It accepts
  pipeline input, runs isolated from the caller, and supports `--full-reparse`
  for watch or repeated execution loops.
- `try/catch` error records now expose structured diagnostics as `$err.details`;
  `$err.json` was removed.
- `str upcase` / `str downcase` are deprecated; use `str uppercase` /
  `str lowercase`.
- `split row` and `split column` support `--right` to count skipped splits from
  the right side, useful for package/version strings.
- `ignore` supports `--stderr`, `--stdout`, and `--show-errors` for precise
  stream handling.
- `append` accepts multiple values; `union`, `intersect`, `difference`,
  `combinations`, and `permutations` cover common immutable list/set work.
- `from kdl` / `to kdl` support KDL v2 data. `to nuon --pretty` is shorthand
  for readable two-space indentation and aligned table columns.
- `lines` replaces invalid UTF-8 by default; use `lines --strict` when invalid
  bytes should fail the pipeline.
- `url encode` accepts binary input and `url decode --binary` can return binary
  for non-UTF-8 data.
- `0.1..0.3` now uses natural fractional steps (`0.1, 0.2, 0.3`) and rounds
  serialized values to the step precision.

## Advanced Closure Patterns

### Closure composition

```nu
let double = {|x| $x * 2 }
let add_ten = {|x| $x + 10 }

# Compose manually
[1 2 3] | each {|x| do $add_ten (do $double $x) }
# Result: [12, 14, 16]

# Or build a composed closure
let transform = {|x| do $double $x | do $add_ten $in }
[1 2 3] | each $transform
```

### Closure currying pattern

```nu
def make-multiplier [factor: int] {
    {|x| $x * $factor }
}

let triple = (make-multiplier 3)
let quadruple = (make-multiplier 4)

[1 2 3] | each $triple      # [3, 6, 9]
[1 2 3] | each $quadruple   # [4, 8, 12]
```

### Closures capture environment (immutable only)

```nu
let multiplier = 10
let compute = {|x| ($x * 2) + $multiplier }
do $compute 5   # 20

# Mutable variables CANNOT be captured in closures
mut sum = 0
[1 2 3] | each {|x| $sum += $x }  # Error!

# Use reduce instead
let sum = [1 2 3] | reduce {|x, acc| $acc + $x }
```

## Stream Patterns

### Generate infinite sequences

```nu
# Fibonacci using generate
generate {|state|
    let a = $state.0
    let b = $state.1
    {out: $a, next: [$b, ($a + $b)]}
} [0, 1] | first 10
```

### Stream control

```nu
$stream | skip while {|x| $x < 100 }   # Skip until condition false
$stream | take while {|x| $x < 1000 }  # Take until condition false
[1 2 3 4 5] | window 3                  # Sliding window: [[1,2,3], [2,3,4], [3,4,5]]
$data | chunks 100                       # Fixed-size batches
```

## Advanced Error Handling

### Graceful degradation

```nu
def robust-fetch [url: string] {
    try {
        http get $url
    } catch {
        try {
            ^curl -s $url | from json
        } catch {
            {error: 'All fetch methods failed'}
        }
    }
}
```

### External command error handling with complete

```nu
let result = (^cargo build o+e>| complete)
if $result.exit_code != 0 {
    print -e $'Build failed:\n($result.stderr)'
} else {
    print 'Build succeeded'
}
```

### Terminal-width-independent diagnostic assertions

Nested Nushell failures captured through `complete` are formatted for humans.
ANSI styling, diagnostic `|` gutters, and PTY-width hard wrapping make raw
`stderr` unsuitable for exact or contiguous substring assertions. Prefer
structured `$err.details` for in-process tests. For a CLI boundary, normalize
both the captured diagnostic and expected phrase before comparing:

```nu
def compact-diagnostic [value: any]: nothing -> string {
    $value
    | into string
    | ansi strip
    | str replace --all --regex r#'[\s|]+'# ''
}

(
    assert str contains
        (compact-diagnostic $result.stderr)
        (compact-diagnostic 'License JSON exceeds 65536 UTF-8 bytes')
)
```

Use a long, domain-specific expected phrase. Verify terminal-sensitive
regressions with a narrow PTY as well as the normal test command.

### Suppress errors with `do -i` / `do -c`

`do -i` (ignore errors) runs a closure and suppresses errors, returning null on failure.
`do -c` (capture errors) catches errors and returns them as values.

```nu
# Fire-and-forget — silently ignore failure
do -i { rm $old_file }

# Concise default value pattern
let config = (do -i { open settings.toml } | default {})

# Capture errors as values (useful to abort downstream pipeline)
let result = (do -c { ^failing-cmd })

# Compare error handling approaches:
# do -i    — suppress error, return null (simplest)
# do -c    — catch error as value, abort downstream pipeline on failure
# try/catch — inspect/log/recover from errors
# complete  — full exit_code + stdout + stderr for externals
```

## Advanced Glob Patterns

```nu
# Multiple extensions
glob **/*.{rs,toml,md}

# Exclusions
glob **/*.rs --exclude [**/target/** **/tests/**]
glob **/tsconfig.json --exclude [**/node_modules/**]

# Character classes
glob '[Cc]*'                          # Files starting with C or c
glob '[!0-9]*'                        # Files NOT starting with digit
glob 'src/[a-m]*.rs'                  # Files starting with a-m

# Depth limit
glob **/*.rs --depth 2                # Max 2 directories deep

# Directory only
glob '[A-Z]*' --no-file --no-symlink  # Only directories starting with uppercase

# Follow symlinks
glob '**/*.txt' --follow-symlinks

# Case-insensitive (wax syntax)
glob '(?i)readme*'
```

## Custom Data Types with Structured Output

```nu
def make-report [title: string, data: table]: nothing -> record {
    {
        title: $title
        generated: (date now)
        row_count: ($data | length)
        columns: ($data | columns)
        data: $data
    }
}
```

## Row Conditions vs Closures (Deep Dive)

### Row conditions — short-hand syntax

```nu
# Left side auto-expands to $it.field
$table | where size > 100              # $it.size > 100
$table | where name =~ 'test'          # $it.name =~ 'test'
ls | where type == file                # Simple and readable

# Limitation: subexpressions need explicit $it
ls | where ($it.name | str lowercase) =~ readme
```

### Closures — full flexibility

```nu
$table | where {|row| $row.size > 100 }
$table | where {$in.size > 100 }

# Can be stored and reused
let big_files = {|row| $row.size > 1mb }
ls | where $big_files

# Works anywhere
$list | each {|x| $x * 2 }
```

**Row conditions:** Simple field comparisons (cleaner syntax), cannot be stored in variables
**Closures:** Complex logic, reusable conditions, nested operations

## Iteration Pitfalls

### each on single records

```nu
# Bad — runs only once, not iterating fields!
let rec = {a: 1, b: 2}
$rec | each {|field| print $field }   # Only runs once

# Good — use items, values, or transpose
$rec | items {|key, val| print $'($key): ($val)' }
$rec | transpose key val | each {|row| ... }
```

### Pipe vs call ambiguity

```nu
# These are different!
$list | my-func arg1 arg2    # $list piped as input, arg1 & arg2 as params
my-func $list arg1 arg2     # All three as positional params (if signature allows)
```

## Debugging Techniques

```nu
# Inspect type
$value | describe

# Print intermediate values without breaking pipeline
$data | each {|x| print $x; $x }

# Measure execution time
timeit { expensive-command }

# Inspect metadata (span info for error reporting)
metadata $value

# View full command signature
help my-command
scope commands | where name == 'my-command'
```
