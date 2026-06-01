# Nushell Data & Type System Reference

## Type Hierarchy

```
any
├── nothing (null/void)
├── bool
├── int
├── float
├── number (int | float)
├── string
├── datetime
├── duration
├── filesize
├── binary
├── range
├── glob
├── list<T>
├── record<K: V, ...>
├── table<T> (list<record<T>>)
├── closure
├── cell-path
└── error
```

## Type Annotations

### Function signatures

```nu
# No types (accepts any)
def func [x] { ... }

# Typed parameters
def func [x: int, y: string] { ... }

# Pipeline types
def func []: string -> int { ... }

# Both pipeline and parameters
def func [multiplier: int]: list<int> -> list<int> {
    $in | each {|x| $x * $multiplier }
}

# Optional parameters with defaults
def func [
    x: int
    y: int = 10             # Default value
    --flag                  # Named flag (boolean switch)
    --option: string        # Named param (null if not passed)
    --foo: string = 'bar'   # Named param with default value
] { ... }
```

### Complex types

```nu
def func [items: list<string>] { ... }
def func [matrix: list<list<int>>] { ... }
def func [config: record<host: string, port: int>] { ... }
def func [data: table] { ... }
def func [transform: closure] { ... }
```

### Type annotations for custom commands

```nu
# Shapes valid for parameter annotations
any, binary, bool, cell-path, closure, datetime, duration, filesize,
float, glob, int, list, nothing, number, range, record, string, table

# Special shapes
path       # String with ~ and . expansion
directory  # Subset of path, only directories for tab-completion
```

## Built-in Scalar Types

### Numbers

```nu
42                    # int
0xFF                  # hexadecimal
0o77                  # octal
0b1010                # binary
10_000                # underscore separator

3.14                  # float
1.5e-3                # scientific notation
inf                   # infinity
-inf                  # negative infinity
NaN                   # not a number
```

### Dates and durations

```nu
date now                              # Current datetime
'2024-01-15' | into datetime
'2024-01-15T10:30:00Z' | into datetime

1sec, 5min, 2hr, 3day, 1wk           # Duration literals
500ms + 2sec                          # 2sec 500ms
(date now) + 5day                     # 5 days from now
(date now) - 1wk                      # 1 week ago
```

### Filesizes

```nu
1kb, 500mb, 2gb, 1tb                 # Filesize literals
1024 | into filesize                  # 1.0 KiB
100mb + 50mb                          # 150mb
1gb / 4                               # 250mb
```

### Binary data

```nu
0x[01 FF 3A 00]                      # Binary literal
'hello' | into binary                # String to binary
0x[68656c6c6f] | decode utf-8        # Binary to string
open --raw file.bin                   # Read raw binary
```

### Glob patterns

```nu
glob *.rs                             # Current dir
glob **/*.rs                          # Recursive
glob **/*.{rs,toml}                   # Multiple extensions
glob **/*.rs --exclude [**/target/**] # With exclusions
glob **/*.rs --depth 2                # Max depth
glob '[A-Z]*' --no-file --no-symlink  # Only directories
glob '(?i)readme*'                    # Case-insensitive (wax syntax)
```

## Collection Types

### Lists

```nu
[1 2 3]                               # list<int>
['Alice' 'Bob']                       # list<string>
[[1 2] [3 4]]                         # list<list<int>>
[]                                    # Empty list
```

### Records

```nu
{name: 'Alice', age: 30}              # Create
{}                                     # Empty record
{user: {name: 'Alice', contact: {email: 'a@b.com'}}}  # Nested
```

### Tables (list of records)

```nu
let users = [
    {name: 'Alice', age: 30}
    {name: 'Bob', age: 25}
]
```

### Ranges

```nu
1..5                  # Inclusive: [1, 2, 3, 4, 5]
1..<5                 # Exclusive end: [1, 2, 3, 4]
1..2..10              # With step: [1, 3, 5, 7, 9]
5..1                  # Reverse: [5, 4, 3, 2, 1]
seq char a e          # Character sequence: [a, b, c, d, e]
```

## Type Conversions

```nu
42 | into string               # '42'
'42' | into int                # 42
3.7 | into int                 # 3 (truncates)
'3.14' | into float            # 3.14
42 | into float                # 42.0
'true' | into bool             # true
1 | into bool                  # true
0 | into bool                  # false
'hello' | into binary          # binary representation
'2024-01-15' | into datetime   # datetime
1024 | into filesize           # 1.0 KiB
60 | into duration --unit sec  # 1min
'*.rs' | into glob             # glob type
```

## Type Checking and Guards

```nu
42 | describe                  # 'int'
[1 2 3] | describe             # 'list<int>'
{a: 1} | describe              # 'record<a: int>'

# Type guard pattern
def safe-process [value: any] {
    match ($value | describe) {
        'int' => ($value * 2)
        'string' => ($value | str upcase)
        _ => null
    }
}

# Type predicates
def is-list [] { ($in | describe) starts-with 'list' }
```

## Type Coercion Rules

Nushell does **NOT** auto-coerce types except in string interpolation:

```nu
'5' + 3                 # TYPE ERROR
$'Value: (42)'          # 'Value: 42' (interpolation auto-converts)
42 == '42'              # false (different types, no coercion)
42 == ('42' | into int) # true (explicit conversion)
```

## Record Operations

```nu
$rec1 | merge $rec2                # Merge (right-biased)
[$r1 $r2 $r3] | into record       # Merge many records
$rec | update name {|r| $'Dr. ($r.name)' }  # Update field
$rec | insert active true          # Insert new field
$rec | insert z {|r| $r.x + $r.y }  # Computed field
$rec | upsert count {|r| ($r.count? | default 0) + 1 }  # Update or insert
$rec | reject password secret_key  # Remove fields
$rec | select name age email       # Keep only these fields
$rec | items {|k, v| ... }         # Iterate key-value pairs
$rec | transpose key val           # Convert to table
```

### Dynamic field access

```nu
let field_name = 'age'
$record | get $field_name          # Access by variable
$record | update $field_name 42    # Update by variable

# Dynamic field selection
let fields = if $detailed { [id name email] } else { [id name] }
$table | select ...$fields
```

## Table Operations

```nu
$table | where age > 25                        # Filter rows
$table | insert retired {|row| $row.age > 65 } # Add column
$table | rename -c {age: years}                 # Rename column
$table | group-by status --to-table             # Group by
$table | transpose name data                    # Transpose

# Joins
$users | join $orders user_id                   # Inner join
$users | join --left $orders user_id            # Left join
$users | join --outer $orders user_id           # Outer join

# Group-by aggregations
$sales | group-by category --to-table | insert stats {|g| {
    count: ($g.items | length)
    total: ($g.items | get price | math sum)
    avg: ($g.items | get price | math avg)
}}
```

## List Operations

```nu
$list | enumerate | where {|e| $e.index > 5 }  # Filter with index
$list | reduce --fold 0 {|it, acc| $acc + $it } # Accumulate with initial
[1 2 3 4] | reduce {|it, acc| $acc - $it }      # Without fold: ((1-2)-3)-4
$list | window 3                                 # Sliding window
$list | chunks 100                               # Batched processing
$list | flatten                                  # Flatten nested lists
$list | skip while {|x| $x < 100 }              # Skip while condition true
$list | take while {|x| $x < 1000 }             # Take while condition true
$list | uniq                                     # Remove duplicates
$list | sort-by field                            # Sort
$list | reverse                                  # Reverse order
```

## Null Safety Patterns

```nu
$record.field?                       # null if field missing (no error)
$record.field? | default 'N/A'       # Provide fallback
if ($record.field? != null) { ... }  # Check existence
$list | default -e $fallback         # Default for empty collections
$input | default 'anonymous'         # Default for null values
```

## Discriminated Unions Pattern

```nu
let result = {type: 'success', value: 42}
let error = {type: 'error', message: 'Failed'}

match $result.type {
    'success' => $result.value
    'error' => { print -e $result.message; null }
}
```

## Dataframes (Polars)

Everything above describes Nushell's **native**, row-oriented `record` / `table` /
`list`. For large datasets and heavy columnar analytics (multi-million row
group-by, joins, aggregations, big CSV/Parquet), Nushell also offers **Polars
dataframes** through the `polars` plugin — a separate, column-oriented data
structure (`polars_dataframe` / `polars_lazyframe`), not a native `table`.

Rule of thumb: native `table` for small/interactive data and tight integration
with the Nushell command set; Polars dataframes for large-scale or columnar work.
Convert with `polars into-df` / `polars into-lazy` (in) and `polars into-nu`
(back out). See [Dataframes](dataframes.md) for the full guide.
