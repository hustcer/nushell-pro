# Nushell Dataframes (Polars) Reference

Nushell's native `list`/`record`/`table` are row-oriented and great for small,
interactive data. For **large datasets** and **heavy analytics** (multi-million
row group-by, joins, aggregations, columnar math, big CSV/Parquet files), use
the **Polars dataframes** provided by the `polars` plugin. Dataframes store data
column-wise (Apache Arrow) and run on the Polars engine, which is dramatically
faster and more memory-efficient than native loops for this class of work.

> All commands and outputs below were verified against Nushell `0.113` with
> `nu_plugin_polars 0.113`. Polars evolves quickly; when in doubt, confirm a
> command's signature with `scope commands | where name == 'polars <cmd>'` or
> `help polars <cmd>` rather than trusting older docs.

## When to Use Dataframes

| Use native `table`/`list` when… | Use Polars dataframes when… |
| --- | --- |
| Data is small (≲ 100k rows) | Data is large (100k–billions of rows) |
| You need random access or row-by-row logic | You do columnar ops: group-by, join, aggregate, window |
| You compose with the broader Nushell command set | You read/write big CSV/Parquet/Arrow/JSON files |
| You stream line-by-line (logs) | You want a query optimizer to plan the whole pipeline |

**Eager vs lazy:**

- **Lazy** (`polars into-lazy`, `polars open`) builds a logical plan that is only
  executed on `polars collect`. The optimizer can prune columns, push down
  filters, and fuse steps. Prefer lazy for large files and multi-step pipelines.
- **Eager** (`polars into-df`, `polars open --eager`) materializes immediately.
  Prefer eager for small data you inspect or reuse many times.

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

## Eager, Lazy, and `collect`

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
```

> **Gotcha:** `polars open` is **lazy by default** (since 0.97). Pass `--eager`
> only when you truly need an in-memory dataframe up front. Note also that
> `describe` returns `polars_dataframe` / `polars_lazyframe` — not the bare
> `DataFrame` string used in older docs.

## The Object Store

Dataframes live in the plugin's object store, not as plain Nushell values. A
Nushell variable holds a *reference*; the store **persists across commands** for
the plugin's lifetime.

```nu
polars store-ls | select key type columns rows estimated_size  # List stored objects
polars store-rm $df                                            # Drop one object
plugin stop polars                                             # Drop everything (full reset)
```

> **Gotcha:** A lazy frame from `polars open` references the *source file*. If
> you delete or move that file before `collect` (or before `polars store-ls`,
> which inspects every stored frame), execution fails with
> `Error collecting lazy frame: No such file or directory`. Collect to an eager
> frame first if the source may disappear.

## Loading, Creating, and Bridging Back

```nu
# Create from native Nushell data
[[a b]; [1 2] [3 4] [5 6]] | polars into-df       # table  -> eager dataframe
[1 2 3 4] | polars into-df                         # list   -> single-column df (a Series)
[[a b]; [1 a] [2 b]] | polars into-lazy            # table  -> lazy frame

# Open files: csv, tsv, parquet, json, jsonl/ndjson, arrow, avro
polars open sales.parquet                          # lazy
polars open --eager sales.csv

# Bridge back to native Nushell for further piping or display
$df | polars into-nu                               # dataframe/expression -> native value
```

Use `polars into-nu` whenever you want to hand results back to ordinary Nushell
commands (`to json`, `save`, `table`, etc.).

## Inspecting

```nu
$df | polars schema       # column -> dtype map, e.g. {a: i64, b: str}
$df | polars shape        # => {rows: 3, columns: 2}
$df | polars columns      # list of column names
$df | polars first 5      # first n rows (also: polars last)
$df | polars summary      # descriptive stats (count/mean/std/min/quantiles/max) for numeric cols
```

## Expressions

Expressions describe column operations. Build them with `polars col` and combine
with arithmetic, comparisons, and `polars as` (alias). They are consumed by
`select`, `with-column`, `filter`, `agg`, etc.

```nu
polars col price                                  # reference a column
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

## Column Selectors

Selectors pick columns by property instead of by exact name — handy for wide
frames.

```nu
$df | polars select (polars selector numeric)           # all int/float columns
$df | polars select (polars selector float)             # all float columns
$df | polars select (polars selector by-name a c)       # explicit names
$df | polars select (polars selector starts-with user)  # user_id, user_name, ...
$df | polars select (polars selector matches '_name$')  # regex on column names
$df | polars select (polars selector by-dtype str)      # by dtype
```

## Select, Filter, With-Column

```nu
# select: keep/compute columns (string names or expressions)
$df | polars select a b
$df | polars select (polars col a) ((polars col b) * 2 | polars as b2)

# filter: keep rows matching an expression
$df | polars filter ((polars col age) > 25)
$df | polars filter ((polars col status) == 'active')

# with-column: add/replace a derived column
$df | polars with-column ((polars col a) + (polars col b) | polars as ab)
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
]
| polars sort-by name
| polars collect
# => name=one total=2 mean=1.0 n=2 ; name=two total=5 mean=2.5 n=2
```

Common aggregations: `sum`, `mean`, `min`, `max`, `len` (row count), `n-unique`,
`std`, `var`, `median`, `quantile`. On an eager frame, a bare `polars sum` (and
friends) reduces every numeric column at once:

```nu
$df | polars sum            # one-row frame: sum of each numeric column (text -> null)
$col | polars value-counts  # frequency table: distinct values + count
```

## Window Functions

`polars over` computes an aggregation **per partition** and broadcasts the result
back to every row — no collapsing, unlike group-by.

```nu
[[g v]; [a 1] [a 2] [b 3]]
| polars into-df
| polars with-column ((polars col v | polars sum | polars over g) | polars as g_sum)
# => g=a v=1 g_sum=3 ; g=a v=2 g_sum=3 ; g=b v=3 g_sum=3
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
```

> Join types are `--inner` (default) / `--left` / `--full` / `--cross`. The old
> `--outer` flag was renamed to `--full`.

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
last or a custom expression) when multiple rows collapse into one cell.

## String and Date Columns

String ops live under `polars str-*` (regrouped since older versions; the old
`replace`/`concatenate` names are gone):

```nu
$df | polars select (polars col w | polars str-replace-all -p '[0-9]+' -r 'N')  # regex replace
$df | polars with-column (polars concat-str '-' [(polars col a) (polars col b)] | polars as ab)
$df | polars select (polars col s | polars str-split ',')      # -> list<str> column
$df | polars select (polars col s | polars str-strip-chars 'x') # trim chars from both ends
# also: str-slice, str-lengths, str-join, lowercase, uppercase, contains
```

Date parsing and formatting:

```nu
$df
| polars with-column (polars col d | polars as-datetime '%Y-%m-%d' --naive | polars as ts)
| polars with-column (polars col ts | polars get-year | polars as year)
| polars with-column (polars col ts | polars strftime '%B' | polars as month_name)
# get-day / get-hour / get-month / get-weekday / datepart are also available
```

## Null Handling

```nu
$df | polars count-null                              # per-column null counts
$df | polars fill-null 0                             # replace nulls with a value/expression
$df | polars drop-nulls                              # drop rows with any null
$df | polars filter (polars col x | polars is-null)  # keep only rows where x is null
# also: is-not-null, fill-nan
```

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
```

## Saving

`polars save` writes a dataframe to disk by extension. For a **lazy** frame it
performs a streaming **sink** when the format supports it (parquet, ipc/arrow,
csv, ndjson) — efficient for results too large to fit in memory.

```nu
$df | polars save out.parquet
polars open big.csv | polars filter ((polars col ok) == true) | polars save filtered.parquet
```

## Migration Notes (older docs → 0.113)

| Old | Now |
| --- | --- |
| `polars melt` | `polars unpivot` (and new `polars pivot` for the reverse) |
| `polars join --outer` | `polars join --full` |
| `polars replace` / `replace-all` (string) | `polars str-replace` / `polars str-replace-all` |
| `polars concatenate` | `polars str-join` / `polars concat-str` |
| `polars fetch` | removed (use `polars collect` / `polars first`) |
| `describe` → `DataFrame` | `describe` → `polars_dataframe` / `polars_lazyframe` |
| `polars open` (eager) | `polars open` is **lazy**; use `--eager` for eager |
| `polars count` for row count | `polars len` |

New since older docs: `polars over` (window), `polars selector *` (column-select
DSL), `polars when`/`otherwise`, `polars join-where`, `polars profile`,
`polars pivot`, `polars query` (SQL).

## Performance Notes

- Polars uses a **columnar layout (Apache Arrow)** plus a **query optimizer**, so
  heavy `group-by`/`join`/aggregation on large data runs roughly an order of
  magnitude faster than native Nushell pipelines, and typically faster than
  pandas as well. (See the official
  [Dataframes chapter](https://www.nushell.sh/book/dataframes.html) for
  benchmarks.)
- Stay **lazy** end-to-end and `collect` once at the end — that lets the
  optimizer prune unused columns and push filters down to the file reader.
- Reuse a stored frame for multiple aggregations instead of re-reading the file.
- For results that don't fit in memory, `polars save` from a lazy frame to
  Parquet/Arrow streams to disk.
- Bridge to native (`polars into-nu`) only at the boundaries; keep the heavy work
  inside Polars.

## See Also

- [Data & Type System](data-and-types.md) — native `record`/`table`/`list` ops
- [Advanced Patterns](advanced-patterns.md) — native lazy/eager streaming, `par-each`
- [Nushell Dataframes book chapter](https://www.nushell.sh/book/dataframes.html)
