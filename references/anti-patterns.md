# Nushell Anti-Patterns Reference

Common mistakes and their idiomatic fixes when writing Nushell scripts.

## 1. Using `echo` Instead of Implicit Return

Nushell implicitly returns the last expression's value. `echo` is almost never needed.

```nu
# Bad
def greet [name: string]: nothing -> string {
    echo $'Hello, ($name)!'
}

# Good
def greet [name: string]: nothing -> string {
    $'Hello, ($name)!'
}
```

Use `print` when you want to display a message as a side effect (not as return value):

```nu
def process [] {
    print 'Processing...'    # Side effect: displayed to user
    do-work                  # Return value: result of do-work
}
```

## 2. Using `for` as Final Expression

`for` is a statement that returns `null`. Use `each` for transformations.

```nu
# Bad — returns nothing
def squares []: nothing -> list<int> {
    for x in [1 2 3 4] { $x ** 2 }
}

# Good — returns the list
def squares []: nothing -> list<int> {
    [1 2 3 4] | each {|x| $x ** 2 }
}
```

## 3. Mutable Variables for Accumulation

```nu
# Bad — imperative accumulation
mut total = 0
for item in $items { $total += $item.price }

# Good — math sum
$items | get price | math sum

# Bad — building a list with mutation
mut result = []
for f in (ls) {
    if ($f.size > 1mb) { $result = ($result | append $f.name) }
}

# Good — filter pipeline
ls | where size > 1mb | get name
```

## 4. Dynamic `source`/`use` Paths

Nushell parses all code before evaluation. `source`/`use` require parse-time constant paths.

```nu
# Bad — let is evaluated at runtime
let my_path = '~/scripts'
source $'($my_path)/utils.nu'    # Error!

# Good — use const for parse-time resolution
const my_path = '~/scripts'
source $'($my_path)/utils.nu'
```

## 5. Bash-Style Redirection

```nu
# Bad — > is the comparison operator in Nushell
'hello' > file.txt       # This is a boolean comparison, not redirection!

# Good — use save command
'hello' | save file.txt
'hello' | save --append file.txt
```

## 6. String Parsing External Commands

```nu
# Bad — parsing ls output as strings
^ls -la | lines | each {|l| $l | split column ' ' }

# Good — use Nushell's structured ls
ls -la

# Bad — parsing JSON from curl
^curl -s https://api.example.com | from json

# Good — use http get (returns structured data directly)
http get https://api.example.com
```

## 7. Ignoring Type Annotations

```nu
# Bad — untyped, hard to catch errors
def process [data] { $data | get name }

# Good — typed, catches misuse at parse time
def process [data: record<name: string, age: int>]: nothing -> string {
    $data.name
}

# Good — I/O signature
def double []: int -> int { $in * 2 }
```

## 8. Space Before Closure Parameters

```nu
# Bad — space before |params|
ls | each { |f| $f.name }

# Good — no space before |params|
ls | each {|f| $f.name }
```

## 9. Environment Changes in Regular `def`

```nu
# Bad — cd change is lost after command returns
def go-project [] { cd ~/projects/my-app }
go-project
pwd   # Still in original directory!

# Good — use def --env to propagate environment changes
def --env go-project [] { cd ~/projects/my-app }
go-project
pwd   # Now in ~/projects/my-app
```

## 10. Unnecessary String Interpolation

```nu
# Bad — interpolation with no variables
let msg = $"hello world"

# Good — simple string
let msg = 'hello world'

# Bad — double-quoted interpolation without escapes
let greeting = $"Hello, ($name)!"

# Good — single-quoted interpolation (no escapes needed)
let greeting = $'Hello, ($name)!'
```

## 11. Using `each` When `par-each` Works

```nu
# Suboptimal — sequential file processing
ls **/*.json | each {|f| open $f.name | get version }

# Better — parallel processing for I/O bound work
ls **/*.json | par-each {|f| open $f.name | get version }
```

Use `each` only when: order must be preserved, side effects must be sequential, or list is very small.

## 12. Missing Command Documentation

```nu
# Bad — no documentation
def deploy [env, --force] { ... }

# Good — documented command
# Deploy the application to the specified environment
#
# Handles building, testing, and deployment in one step.
@example 'Deploy to staging' { deploy staging }
def deploy [
    env: string     # Target environment (staging, production)
    --force (-f)    # Skip confirmation prompts
] { ... }
```

## 13. Not Using `default` for Optional Values

```nu
# Bad — verbose null check
let name = if $input == null { 'anonymous' } else { $input }

# Good — use default command
let name = $input | default 'anonymous'
```

## 14. Manual JSON/YAML/TOML Parsing

```nu
# Bad — manual string manipulation
let version = (open Cargo.toml | lines | where $it =~ '^version' | first | split column '=' | get column2.0 | str trim)

# Good — native structured data support
let version = (open Cargo.toml | get package.version)
```

## 15. Not Using `match` for Multi-Branch Logic

```nu
# Bad — chain of if/else
if $status == 'ok' { handle-ok }
else if $status == 'error' { handle-error }
else if $status == 'pending' { handle-pending }
else { handle-unknown }

# Good — pattern matching
match $status {
    ok => { handle-ok }
    error => { handle-error }
    pending => { handle-pending }
    _ => { handle-unknown }
}
```

## 16. Incorrect Shebang for stdin Scripts

```nu
# Bad — script won't receive stdin
#!/usr/bin/env nu

# Good — add --stdin flag
#!/usr/bin/env -S nu --stdin
def main [] { $in | process }
```

## 17. Forgetting `export` in Modules

```nu
# Bad — command is private, can't be imported
# my-module.nu
def helper [] { 'hello' }

# Good — export makes it public
export def helper [] { 'hello' }

# Also good — keep internal helpers private intentionally
def internal-helper [] { 'private' }
export def public-cmd [] { internal-helper }
```

## 18. Confusing Pipeline Input with Parameters

```nu
# Bad — treats pipeline data as positional parameter
def my-func [items: list, value: any] {
    $items | append $value
}

# Good — declares pipeline input signature
def my-func [value: any]: list -> list {
    $in | append $value
}

# Usage: [1 2 3] | my-func 4
```

**Why:** Pipeline input is lazily evaluated (streaming); parameters are eagerly loaded. Different calling conventions entirely.

## 19. Using `each` on Single Records

```nu
# Bad — runs only once, not iterating fields!
let rec = {a: 1, b: 2}
$rec | each {|field| print $field }

# Good — iterate key-value pairs
$rec | items {|key, val| print $'($key): ($val)' }
$rec | transpose key val | each {|row| ... }
```

## 20. Accessing Missing Fields Without `?`

```nu
# Bad — error if field doesn't exist
$record.missing_field   # Error!

# Good — use ? for optional access
$record.missing_field?                # Returns null
$record.missing_field? | default 0    # Provide fallback
```

## 21. Not Prefixing External Commands with `^`

```nu
# Ambiguous — could be Nushell builtin or external
find pattern           # This is Nushell's find, NOT Unix find!
sort                   # This is Nushell's sort, NOT Unix sort!

# Clear — explicitly calls external
^find . -name '*.rs'   # Unix find
^sort file.txt         # Unix sort
^grep pattern file     # External grep
```

**Rule:** Nushell builtins always take precedence. Use `^` to unambiguously call external commands.

## 22. Ignoring `complete` for External Command Errors

```nu
# Bad — no error handling for external commands
let output = (^cargo build)

# Good — use complete for full error info
let result = (^cargo build o+e>| complete)
if $result.exit_code != 0 {
    print -e $'Build failed:\n($result.stderr)'
}
```

## 23. Empty Collection Checks

```nu
# Bad — comparing length
if ($list | length) == 0 { ... }

# Good — use is-empty / is-not-empty
if ($list | is-empty) { ... }
if ($list | is-not-empty) { ... }
```

## 24. Native Loops or `group-by` on Huge Datasets

Native `each`/`reduce`/`group-by` process data row by row. For very large
datasets this is slow and memory-hungry. Push the work into the `polars`
plugin's columnar dataframes instead.

```nu
# Bad — native group-by + manual aggregation over millions of rows
open huge.csv
| group-by category --to-table
| update items {|g| $g.items.amount | math sum }

# Good — Polars: lazy by default, optimized columnar aggregation
polars open huge.csv
| polars group-by category
| polars agg (polars col amount | polars sum | polars as total)
| polars collect
```

Also remember to **`collect`** a lazy frame — without it you hold a plan, not
results. See [Dataframes](dataframes.md).

## 25. Assuming `parse` Splits Streams into Lines

Since Nushell 0.113, `parse` no longer implicitly splits byte/string streams
from files or external commands into lines. It collects the stream and parses it
as one input value. Add `lines` when you want the old line-by-line behavior.

```nu
# Bad — expects one match per line, but parses the stream as one input value
open app.log | parse -r '^(?<level>\w+) (?<message>.*)$'

# Good — explicit line-by-line parsing
open app.log | lines | parse -r '^(?<level>\w+) (?<message>.*)$'

# Also good — intentionally parse the whole file with a multiline regex
open changelog.txt | parse -r r#'(?ms)^## (?<version>.*?)\n(?<body>.*)'#
```
