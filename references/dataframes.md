# Nushell Dataframes (Polars) Reference

Nushell's native `list`/`record`/`table` are row-oriented and great for small,
interactive data. For **large datasets** and **heavy analytics** (multi-million
row group-by, joins, aggregations, columnar math, big CSV/Parquet files), use
the **Polars dataframes** provided by the `polars` plugin. Dataframes store data
column-wise (Apache Arrow) and run on the Polars engine, which is dramatically
faster and more memory-efficient than native loops for this class of work.

> Command shapes below are maintained for Nu 0.114 / Polars 0.54 behavior.
> Polars evolves quickly; when in doubt, confirm a command's signature with
> `scope commands | where name == 'polars <cmd>'` or
> `help polars <cmd>` rather than trusting older docs. The plugin currently
> ships ~150 `polars *` subcommands — `help polars` lists them all.

## Contents

- Choosing Polars, setup, lazy/eager execution, and object storage
- Loading, inspecting, expressions, selectors, and column operations
- Aggregation, windows, joins, concatenation, and reshaping
- Nested data, binning, math, strings, dates, and null handling
- Sampling, replacement, custom batches, SQL, casting, and saving
- Migration and performance notes

## When to Use Dataframes

| Use native `table`/`list` when…                  | Use Polars dataframes when…                            |
| ------------------------------------------------ | ------------------------------------------------------ |
| Data is small (≲ 100k rows)                      | Data is large (100k–billions of rows)                  |
| You need random access or row-by-row logic       | You do columnar ops: group-by, join, aggregate, window |
| You compose with the broader Nushell command set | You read/write big CSV/Parquet/Arrow/JSON files        |
| You stream line-by-line (logs)                   | You want a query optimizer to plan the whole pipeline  |

**Eager vs lazy:**

- **Lazy** (`polars into-lazy`, `polars open`) builds a logical plan that is only
  executed on `polars collect`. The optimizer can prune columns, push down
  filters, and fuse steps. Prefer lazy for large files and multi-step pipelines.
- **Eager** (`polars into-df`, `polars open --eager`) materializes immediately.
  Prefer eager for small data you inspect or reuse many times.

Some commands only work on one shape (e.g. `polars unique --subset`,
`polars shift --fill` are documented as **lazy-only**; bare reductions like
`polars sum` work eager). When a command errors with a shape complaint, switch
the frame with `polars into-lazy` / `polars collect`.

## Plugin Setup

The `polars` plugin ships as `nu_plugin_polars` (install via `cargo install
nu_plugin_polars` or your package manager, matching your Nushell version).

```nu
plugin add ~/.cargo/bin/nu_plugin_polars   # Register once (path to the binary)
plugin use polars                           # Load into the current scope/config
help polars                                 # Verify: lists all polars subcommands
plugin stop polars                          # Reset the plugin + clear its object store
```

`plugin use polars` must run at parse time (top of a script or in your config),
just like `use` — it cannot be created from a runtime `let`.

## Eager, Lazy, `collect`, and `cache`

```nu
[[a b]; [1 2] [3 4]] | polars into-df | describe     # => polars_dataframe (eager)
[[a b]; [1 2] [3 4]] | polars into-lazy | describe   # => polars_lazyframe
polars open data.csv | describe                       # => polars_lazyframe (LAZY by default!)
polars open --eager data.csv | describe               # => polars_dataframe

# A lazy frame is just a plan until you collect it
polars open data.csv
| polars filter ((polars col status) == 'active')
| polars select name status
| polars collect                                      # executes the optimized plan

# polars cache materializes the plan up to that point into a new lazy frame,
# so a shared sub-plan is computed once instead of re-run by each branch.
polars open data.csv | polars filter ((polars col ok) == true) | polars cache
```

> **Gotcha:** `polars open` is **lazy by default** (since 0.97). Pass `--eager`
> only when you truly need an in-memory dataframe up front. Note also that
> `describe` returns `polars_dataframe` / `polars_lazyframe` — not the bare
> `DataFrame` string used in older docs.

## The Object Store

Dataframes live in the plugin's object store, not as plain Nushell values. A
Nushell variable holds a _reference_; the store **persists across commands** for
the plugin's lifetime.

```nu
polars store-ls | select key type columns rows estimated_size  # List stored objects
polars store-ls | get key | first | polars store-get $in       # Re-fetch an object by key
polars store-ls | get key | first | polars store-rm $in        # Drop one object by key
plugin stop polars                                             # Drop everything (full reset)
```

`polars store-get <key>` returns any stored object (dataframe, lazyframe,
expression, group-by, schema, selector…) — useful for reconnecting to a frame
by key, e.g. across `do`/closure boundaries.

> **Gotcha:** A lazy frame from `polars open` references the _source file_. If
> you delete or move that file before `collect` (or before `polars store-ls`,
> which inspects every stored frame), execution fails with
> `Error collecting lazy frame: No such file or directory`. Collect to an eager
> frame first if the source may disappear.

## Loading, Creating, and Bridging Back

```nu
# Create from native Nushell data
[[a b]; [1 2] [3 4] [5 6]] | polars into-df       # table  -> eager dataframe
[1 2 3 4] | polars into-df                         # list   -> single-column dataframe
[[a b]; [1 a] [2 b]] | polars into-lazy            # table  -> lazy frame

# Pin a schema explicitly with -s (dtypes, including nested struct/list types)
[[id person]; [1 {name: Bob, age: 36}]]
| polars into-df -s {id: i64, person: {name: str, age: u8}}

# Open files: csv, tsv, parquet, json, jsonl/ndjson, arrow, avro
polars open sales.parquet                          # lazy
polars open --eager sales.csv
polars open data.csv --infer-schema 1000 --skip-rows 2 --delimiter ';' --no-header
polars open data.csv --schema {a: i64, b: str}     # force column dtypes

# Bridge back to native Nushell for further piping or display
$df | polars into-nu                               # dataframe/expression -> native value
```

`polars open` flags include `--eager`, `--type`, `--delimiter`, `--no-header`,
`--infer-schema <n>`, `--skip-rows <n>`, `--columns`, `--schema`,
`--truncate-ragged-lines`, plus Hive-partition flags (`--hive-enabled`,
`--hive-schema`, …). Use `polars into-nu` whenever you want to hand results back
to ordinary Nushell commands (`to json`, `save`, `table`, etc.).

## Inspecting

```nu
$df | polars schema       # column -> dtype map, e.g. {a: i64, b: str}
$df | polars shape        # => {rows: 3, columns: 2}
$df | polars columns      # list of column names
$df | polars first 5      # first n rows (also: polars last)
$df | polars summary      # descriptive stats (count/mean/std/min/quantiles/max) for numeric cols
$df | polars into-repr     # the native Polars text table (with shape + dtypes), as a string
```

`polars into-repr` is handy in messages/logs — it renders the familiar Polars
box table (including the `shape: (rows, cols)` header and per-column dtypes).

## Expressions

Expressions describe column operations. Build them with `polars col` and combine
with arithmetic, comparisons, and `polars as` (alias). They are consumed by
`select`, `with-column`, `filter`, `agg`, etc.

```nu
polars col price                                  # reference a column
polars col '*'                                    # all columns
(polars col price) * 1.1                          # arithmetic on a column
polars lit 100                                    # a literal value
(polars col qty | polars sum | polars as total)   # aggregate + alias

# Conditional (if/else) expression: when ... otherwise ...
$df | polars with-column (
    polars when ((polars col score) >= 60) 'pass'
    | polars otherwise 'fail'
    | polars as grade
)
```

`polars when` can be chained for multi-branch logic
(`when A a | when B b | otherwise c`). Negate a boolean expression with
`polars expr-not`; invert a boolean mask/series with `polars not`.

## Column Selectors

Selectors pick columns by property instead of by exact name — handy for wide
frames. They produce a `polars_selector` usable anywhere a column set is
expected (`select`, `with-column`, `is-in`, etc.). In Nu 0.114+, commands that
accept Polars expressions can accept selectors as input too.

```nu
$df | polars select (polars selector numeric)           # all int/float columns
$df | polars select (polars selector float)             # all float columns
$df | polars select (polars selector by-name a c)       # explicit names
$df | polars select (polars selector starts-with user)  # user_id, user_name, ...
$df | polars select (polars selector ends-with _id)     # account_id, user_id, ...
$df | polars select (polars selector contains name)     # columns containing substring
$df | polars select (polars selector matches '_name$')  # regex on column names
$df | polars select (polars selector by-index 0 -1)     # first and last columns
$df | polars select (polars selector alpha)             # names made of letters
$df | polars select (polars selector alphanumeric)      # names made of letters/digits
$df | polars select (polars selector by-dtype str)      # by dtype
$df | polars select (polars selector numeric | polars selector exclude id)  # compose/exclude
```

The full selector family: `all`, `alpha`, `alphanumeric`, `array`, `binary`,
`boolean`, `by-dtype`, `by-index`, `by-name`, `categorical`, `contains`, `date`,
`datetime`, `decimal`, `digit`, `duration`, `empty`, `ends-with`, `enum`,
`exclude`, `first`, `float`, `integer`, `last`, `list`, `matches`, `nested`,
`not`, `numeric`, `object`, `signed-integer`, `starts-with`, `string`, `struct`,
`temporal`, `unsigned-integer`.

## Select, Filter, With-Column, Rename, Drop

```nu
# select: keep/compute columns (string names or expressions)
$df | polars select a b
$df | polars select (polars col a) ((polars col b) * 2 | polars as b2)
$df | polars get a b                       # like select but returns those columns directly

# filter: keep rows matching an expression
$df | polars filter ((polars col age) > 25)
$df | polars filter ((polars col status) == 'active')
$df | polars filter-with (polars col flag)  # filter by a boolean mask/expression

# with-column: add/replace a derived column
$df | polars with-column ((polars col a) + (polars col b) | polars as ab)
$df | polars with-column {ab: ((polars col a) + (polars col b))}  # record form: name -> expr

# rename / drop columns
$df | polars rename a alpha                 # rename one column (also takes lists)
$df | polars drop b c                       # drop columns by name
```

> Columns are immutable and shared between frames for efficiency — you cannot
> mutate a value in place. Derive a **new** column with `with-column` instead.

## Group-by and Aggregation

The core analytics pattern: `group-by` → `agg [...]` → `collect`. Use a lazy
frame so the optimizer only touches the columns you aggregate.

```nu
[[name value]; [one 1] [two 2] [one 1] [two 3]]
| polars into-lazy
| polars group-by name
| polars agg [
    (polars col value | polars sum | polars as total)
    (polars col value | polars mean | polars as mean)
    (polars col value | polars len | polars as n)
    (polars col value | polars quantile 0.5 | polars as median)
]
| polars sort-by name
| polars collect
# => name=one total=2 mean=1.0 n=2 median=1.0 ; name=two total=5 mean=2.5 n=2 median=2.5
```

Aggregation expressions usable inside `agg` (and as standalone reductions):
`sum`, `mean`, `min`, `max`, `median`, `quantile`, `std`, `var`, `len` (row
count), `count` (non-null count), `n-unique`, `implode` (collect into a list),
`first`, `last`, `entropy`. On an **eager** frame, a bare `polars sum` (and
friends `mean`/`min`/`max`/`median`/`std`/`var`/`quantile`) reduces every numeric
column at once:

```nu
$df | polars sum            # one-row frame: sum of each numeric column (text -> null)
$col | polars value-counts  # frequency table: distinct values + count
```

`polars value-counts` also accepts `--sort` (order by count) and `--normalize`
(return proportions instead of raw counts).

## Window and Sequence Functions

`polars over` computes an aggregation **per partition** and broadcasts the result
back to every row — no collapsing, unlike group-by.

```nu
[[g v]; [a 1] [a 2] [b 3]]
| polars into-df
| polars with-column ((polars col v | polars sum | polars over g) | polars as g_sum)
# => g=a v=1 g_sum=3 ; g=a v=2 g_sum=3 ; g=b v=3 g_sum=3
```

`polars shift` lags/leads a column by a period; `polars cumulative` runs a
running min/max/sum; `polars rolling` runs a fixed-window reduction.

```nu
# shift (lag by 2; --fill replaces the leading nulls, lazy frame)
[[a]; [1] [2] [2] [3] [3]]
| polars into-lazy
| polars with-column {b: (polars col a | polars shift 2 --fill 0)}
| polars collect
# => b column = 0 0 1 2 2

# cumulative sum (also: min / max ; --reverse to run end-to-start)
[[a]; [1] [2] [3]]
| polars into-df
| polars select (polars col a | polars cumulative sum | polars as cum)
| polars collect
# => cum = 1 3 6

# rolling window over a series (type = sum / min / max / mean)
[1 2 3 4 5] | polars into-df | polars rolling sum 2 | polars drop-nulls
# => 0_rolling_sum = 3 5 7 9
```

## Joins

```nu
$left | polars join $right id id              # inner join (default), key on both sides
$left | polars join --left $right id id        # left join (unmatched right -> null)
$left | polars join --full $right id id         # full outer join
$left | polars join --cross $right              # cross join
$left | polars join $right [id region] [id region]  # multi-column key

# Useful flags
--coalesce-columns     # merge key columns (esp. with --full)
--suffix '_r'          # rename overlapping non-key columns from the right
--nulls-equal          # treat nulls as matching

# Non-equi / conditional join: match on arbitrary predicates, not just equality
$left | polars join-where $right ((polars col amount) > (polars col threshold))
```

> Join types are `--inner` (default) / `--left` / `--full` / `--cross`. The old
> `--outer` flag was renamed to `--full`. `polars join` operates on lazy frames.

## Combining Frames: Concat and Append

```nu
# concat: stack two or more frames (vertically by default). Clear and explicit —
# prefer this for "union all" style row stacking.
[[a b]; [1 2]] | polars into-df
| polars concat ([[a b]; [3 4]] | polars into-df) ([[a b]; [5 6]] | polars into-df)
| polars collect
# => 3 rows. Flags: --diagonal (union mismatched columns), --to-supertypes
#    (reconcile dtypes), --rechunk, --no-maintain-order.

# append: note the counter-intuitive flag semantics (verified on 0.114) —
let a = ([[a b]; [1 2] [3 4]] | polars into-df)
$a | polars append $a          # DEFAULT: adds the other frame as NEW COLUMNS -> a b a_x b_x
$a | polars append $a --col    # --col: stacks ROWS -> 4 rows of (a b)
```

> **Gotcha:** `polars append`'s default appends _columns_ (with `_x` suffixes on
> name clashes); `--col` appends _rows_. This is the opposite of what the flag
> name suggests. For row stacking, **prefer `polars concat`** — it reads clearly.

## Reshaping: Unpivot and Pivot

```nu
# unpivot: wide -> long (formerly "melt")
[[id m1 m2]; [a 1 2] [b 3 4]]
| polars into-df
| polars unpivot --index [id] --on [m1 m2] --variable-name metric --value-name val
# => id=a metric=m1 val=1 ; id=a metric=m2 val=2 ; id=b ...

# pivot: long -> wide
[[g k v]; [a x 1] [a y 2] [b x 3] [b y 4]]
| polars into-df
| polars pivot --on [k] --index [g] --values [v]
# => g=a x=1 y=2 ; g=b x=3 y=4
```

`polars pivot` also takes `--aggregate (-a)` (first/sum/min/max/mean/median/count/
last or a custom expression) when multiple rows collapse into one cell, plus
`--separator`, `--maintain-order`, `--always-combine-names`, `--stable`, and
`--streamable`.

## Nested Data: Lists and Structs

Polars columns can hold `list<…>` and `struct<…>` values. These commands move
between nested and flat layouts.

```nu
# explode / flatten: one list element per row (flatten is an alias for explode)
[[id hobbies]; [1 [Cycling Knitting]] [2 [Skiing]]]
| polars into-df
| polars explode hobbies
| polars collect
# => (1, Cycling) (1, Knitting) (2, Skiing)

# implode: the inverse — aggregate a column's values into a single list (in agg/select)
$df | polars select (polars col v | polars implode)
# Nu 0.114+: `polars implode` supports --maintain-order

# unnest: split a struct column into one column per field (inserted in place)
[[id person]; [1 {name: Bob, age: 36}] [2 {name: Betty, age: 63}]]
| polars into-df -s {id: i64, person: {name: str, age: u8}}
| polars unnest person                  # -> columns id, name, age  (-s '_' to prefix names)

# struct-json-encode: serialize a struct column to a JSON string column
$df | polars select id (polars col person | polars struct-json-encode | polars as json)

# membership tests
$df | polars with-column (polars col a | polars is-in [one two] | polars as a_in)   # scalar in set
# Nu 0.114+: `polars is-in` supports --maintain-order
$df | polars with-column (polars col tags | polars list-contains (polars lit urgent) | polars as has)  # element in list column
```

## Binning and Encoding

```nu
# cut: bin a numeric series by explicit break points (n breaks -> n+1 categories)
[-2 -1 0 1 2] | polars into-df | polars cut [-1 1] --labels [low mid high]
# => category column: low low mid high high  (--left_closed, --include_breaks)

# qcut: bin by quantile probabilities instead of fixed breaks
[-2 -1 0 1 2] | polars into-df | polars qcut [0.25 0.75] --labels [a b c] --allow_duplicates

# dummies: one-hot encode (--drop-first to avoid the dummy-variable trap)
[[a b]; [1 2] [3 4]] | polars into-df | polars dummies
# => columns a_1 a_3 b_2 b_4 (0/1)
```

## Math Functions

```nu
# polars math: scalar math over column expressions
#   abs, sign, sqrt, exp, log <base; default e>, log1p, sin, cos, dot <expr>
#   bitwise-and, bitwise-or, bitwise-xor, bitwise-count-ones, bitwise-count-zeros,
#   bitwise-leading-ones, bitwise-leading-zeros, bitwise-trailing-ones,
#   bitwise-trailing-zeros
[[a]; [-1] [4]]
| polars into-df
| polars select (polars col a | polars math abs | polars as a_abs)
| polars collect

# polars horizontal: reduce ACROSS columns per row (all/any/min/max/sum/mean).
# Nulls are skipped by default; pass --nulls to make any null produce null.
[[a b]; [1 2] [3 4]]
| polars into-df
| polars select (polars horizontal sum a b | polars as row_sum)
| polars collect
# => row_sum = 3 7
```

## String Columns

String ops live under `polars str-*` (regrouped since older versions; old
substring replacement examples that used generic names should now use the
string-specific commands):

```nu
$df | polars select (polars col w | polars str-replace -p '[0-9]+' -r 'N')      # regex replace (leftmost)
$df | polars select (polars col w | polars str-replace-all -p '[0-9]+' -r 'N')  # regex replace all
$df | polars with-column (polars concat-str '-' [(polars col a) (polars col b)] | polars as ab)
$df | polars select (polars col s | polars str-split ',')        # -> list<str> column
$df | polars select (polars col s | polars str-strip-chars 'x')  # trim chars from both ends
# also: str-slice, str-lengths, str-join, lowercase, uppercase, contains
```

## Date, Time, and Time Zones

```nu
$df
| polars with-column (polars col d | polars as-datetime '%Y-%m-%d' --naive | polars as ts)
| polars with-column (polars col ts | polars get-year | polars as year)
| polars with-column (polars col ts | polars datepart month | polars as month)
| polars with-column (polars col ts | polars strftime '%B' | polars as month_name)
```

- **Parsing:** `polars as-date` / `polars as-datetime '<fmt>'`. Pass `--naive`
  for timezone-naive timestamps; `--time-zone`, `--time-unit`, `--ambiguous`
  refine the parse.
- **Extracting parts:** the `polars get-*` family (`get-year`, `get-month`,
  `get-day`, `get-hour`, `get-minute`, `get-second`, `get-nanosecond`,
  `get-week`, `get-weekday`, `get-ordinal`) — or the unified
  `polars datepart <part>` (`year`/`quarter`/`month`/`week`/`weekday`/`day`/
  `hour`/`minute`/`second`/`millisecond`/`microsecond`/`nanosecond`).
- **Formatting:** `polars strftime '<fmt>'`.
- **Time zones:** `polars convert-time-zone 'America/New_York'` shifts the
  instant to another zone; `polars replace-time-zone 'America/New_York'` relabels
  the wall-clock time without shifting it (`--ambiguous`/`--nonexistent` handle
  DST edge cases; pass `null` to unset the zone).
- **Bucketing:** `polars truncate 1h` (or `5d`, `1mo`, `1wk`…) floors each
  timestamp to the start of its bucket — the basis for time-series grouping.

## Null Handling

```nu
$df | polars count-null                              # per-column null counts
$df | polars fill-null 0                             # replace nulls with a value/expression
$df | polars fill-nan 0                              # replace float NaN (distinct from null)
$df | polars drop-nulls                              # drop rows with any null
$df | polars filter (polars col x | polars is-null)  # keep only rows where x is null
# also: is-not-null
```

## Sampling, Slicing, and Dedup

```nu
$df | polars sample --n-rows 100              # random subset (--fraction, --replace, --shuffle, --seed)
$df | polars slice 10 20                       # 20 rows starting at offset 10
$df | polars take [0 2 4]                      # rows at the given indices
$df | polars first 5                           # head (also: polars last 5)
$df | polars reverse                           # reverse row order
$df | polars into-lazy | polars unique --subset [a] | polars collect   # dedup by column subset (lazy)
$df | polars drop-duplicates                   # drop fully-duplicate rows
```

## Replace and Conditional Values

```nu
# polars replace: value mapping (old -> new) via two positional args.
# `old` is a list/record of values to match; `new` is the list of replacements.
$df | polars with-column (polars col grade | polars replace [A B] [4 3] | polars as gpa)
# Flags: --strict (every value must match), --default <expr> (value for unmatched).
# Nu 0.114 / Polars 0.54: with `--strict` and `--return-dtype`, pass
# `--default <value>` when any input values may be unmapped.

# polars set / set-with-idx / filter-with: mask- or index-based value assignment (eager series)
```

`polars replace` does **value mapping** (different from `polars str-replace`,
which does regex substring replacement on string columns).

## Custom Logic Escape Hatch: `map-batches`

When an operation has no native Polars expression, `polars map-batches` runs a
**Nushell closure** over one or more columns. The closure receives a list of
single-column dataframes and returns a series-like value (list, scalar, or
single-column dataframe).

```nu
[[a b]; [1 4] [2 5] [3 6]]
| polars into-df
| polars map-batches --name out { |cols| $cols | first | polars get a | each { |v| $v * 2 } } a
# => out = 2 4 6
```

> Use sparingly: dropping into a Nushell closure forfeits Polars' vectorized
> speed. Reach for it only when no native expression (`math`, `str-*`,
> `when/otherwise`, arithmetic) can express the transform.

## SQL Queries

```nu
$df | polars query 'select category, sum(amount) as total from df group by category order by total desc'
```

The source frame is always referenced as `df` in the `from` clause.

## Type Casting

Use Polars dtype names (`i64`, `f64`, `str`, `bool`, `date`, `datetime`, …), not
Nushell type names:

```nu
$df | polars cast f64 price        # cast one column (column arg required on a dataframe)
$df | polars cast i64 a | polars cast str b
$df | polars schema                # => {a: i64, b: str}

# Build dtype / schema objects when a command needs them
'i64' | polars into-dtype                           # dtype-name string -> dtype object
{a: i64, b: str} | polars into-schema              # record -> schema object
```

Dedicated string→number converters also exist: `polars integer` and
`polars decimal` parse a string column into integer/decimal columns.

## Saving

`polars save` writes a dataframe to disk by extension. For a **lazy** frame it
performs a streaming **sink** when the format supports it (parquet, ipc/arrow,
csv, ndjson) — efficient for results too large to fit in memory.

```nu
$df | polars save out.parquet
polars open big.csv | polars filter ((polars col ok) == true) | polars save filtered.parquet
$df | polars save out.csv --csv-delimiter ';' --csv-no-header
```

Flags include `--type` (force format), `--csv-delimiter`, `--csv-no-header`, and
`--avro-compression`.

## Migration Notes (older docs → 0.113/0.114)

| Old                                                                | Now                                                                                        |
| ------------------------------------------------------------------ | ------------------------------------------------------------------------------------------ |
| `polars melt`                                                      | `polars unpivot` (and `polars pivot` for the reverse)                                      |
| `polars join --outer`                                              | `polars join --full`                                                                       |
| old substring replacement examples using `replace` / `replace-all` | `polars str-replace` / `polars str-replace-all` (`polars replace` is value mapping)        |
| `polars concatenate`                                               | `polars str-join` / `polars concat-str` (string concat), or `polars concat` (stack frames) |
| `polars fetch`                                                     | removed (use `polars collect` / `polars first`)                                            |
| `describe` → `DataFrame`                                           | `describe` → `polars_dataframe` / `polars_lazyframe`                                       |
| `polars open` (eager)                                              | `polars open` is **lazy**; use `--eager` for eager                                         |
| `polars count` for row count                                       | `polars len` (`polars count` = non-null count, SQL `COUNT(col)`)                           |

New since older docs: `polars over` (window), `polars shift`/`cumulative`/
`rolling` (sequence ops), `polars selector *` (column-select DSL),
`polars when`/`otherwise`, `polars join-where` (non-equi join), `polars concat`,
`polars cut`/`qcut`/`dummies` (binning + one-hot), `polars math`/`horizontal`
(numeric and bitwise ops), `polars explode`/`implode`/`unnest`/`struct-json-encode` (nested
data), `polars convert-time-zone`/`replace-time-zone`/`truncate`/`datepart`
(time zones + buckets), `polars map-batches` (Nushell-closure escape hatch),
`polars profile`, `polars cache`, `polars store-get`, `polars into-repr`,
`polars query` (SQL).

## Performance Notes

- Polars uses a **columnar layout (Apache Arrow)** plus a **query optimizer**, so
  heavy `group-by`/`join`/aggregation on large data can run substantially
  faster than native Nushell pipelines, and often faster than pandas as well.
  (See the official
  [Dataframes chapter](https://www.nushell.sh/book/dataframes.html) for
  benchmarks.)
- Stay **lazy** end-to-end and `collect` once at the end — that lets the
  optimizer prune unused columns and push filters down to the file reader.
- Reuse a stored frame for multiple aggregations instead of re-reading the file;
  use `polars cache` to compute a shared sub-plan once when several branches
  build on it.
- Prefer native Polars expressions over `polars map-batches`; the closure path
  gives up vectorization.
- For results that don't fit in memory, `polars save` from a lazy frame to
  Parquet/Arrow streams to disk.
- Bridge to native (`polars into-nu`) only at the boundaries; keep the heavy work
  inside Polars.

## See Also

- [Data & Type System](data-and-types.md) — native `record`/`table`/`list` ops
- [Advanced Patterns](advanced-patterns.md) — native lazy/eager streaming, `par-each`
- [Nushell Dataframes book chapter](https://www.nushell.sh/book/dataframes.html)
