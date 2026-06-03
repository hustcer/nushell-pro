# Nushell String Formats Reference

## String Format Priority (High to Low)

1. **Bare word** — Simple word-character-only strings in data contexts
2. **Raw string** `r#'...'#` — Regex patterns, paths with quotes, multi-line content
3. **Single-quoted** `'...'` — Simple strings without embedded single quotes
4. **Single-quoted interpolation** `$'...'` — Interpolation without escape sequences
5. **Backtick** `` `...` `` — Paths/globs with spaces
6. **Double-quoted** `"..."` — Only when escape sequences are needed (`\n`, `\t`, `\"`, etc.)
7. **Double-quoted interpolation** `$"..."` — Only when both interpolation AND escapes are needed

## Conversion Rules

### Use bare words when:

- Inside arrays: `[foo bar baz]` not `["foo" "bar" "baz"]`
- Path join arrays: `[$dir patches]` not `[$dir "patches"]`
- Match patterns: `match $x { absolute => ... }` not `match $x { "absolute" => ... }`

### Use raw strings when:

- Regex patterns with special chars: `r#'(?:a/|b/)?'#` not `"(?:a/|b/)?"`
- Strings containing both single and double quotes
- Multi-line content without interpolation

### Use single quotes when:

- Simple strings: `'hello world'` not `"hello world"`
- No escape sequences or interpolation needed

### Use single-quoted interpolation when:

- Variables/expressions present but NO escape sequences:
  - `$'Package: ($pkg.name)'` not `$"Package: ($pkg.name)"`
  - `$'Error: ($msg)'` not `$"Error: ($msg)"`

### Keep double quotes ONLY when:

- Escape sequences present: `"\n"`, `"\t"`, `"\r"`, `"\""`
- Need both interpolation and escapes: `$"Line: ($n)\n"`

### YAML output in 0.113.1+

`to yaml` no longer quotes every string. It emits plain scalars when they are
safe to round-trip as strings, keeps quotes for values that YAML could
reinterpret (for example `'off'`), and emits multiline strings as block scalars.

```nu
{value: 'off', path: '/dev/stdout', name: 'kong'} | to yaml
# value: 'off'
# path: /dev/stdout
# name: kong
```

When testing YAML output, assert parsed structure where possible instead of exact
quote style.

### Important: Single quotes don't escape

In Nushell, `\'` inside `$'...'` is NOT an escape — it's a literal backslash + quote.

```nu
# Correct — use double quotes when literal single quotes needed
let marker = $"'($pkg)@($ver)':"

# Wrong — backslash doesn't escape in single quotes
let marker = $'\'($pkg)@($ver)\':'  # Produces literal backslashes!
```

### Important: Command expressions require `$` prefix

Strings containing Nushell command expressions wrapped in `()` MUST keep the `$` prefix:

```nu
# Correct — $ prefix required for command expressions
print $'(char nl)Done:'
print $'(ansi g)Success!(ansi rst)'

# Wrong — without $ these are literal text
print '(char nl)Done:'      # Prints literal "(char nl)"
print '(ansi g)Success!'    # Prints literal "(ansi g)"
```

**Rule**: If a string contains `(...)` that should be evaluated as a command, always use `$'...'` or `$"..."`.

### External command format strings

For external command format strings, prefer double quotes with a single escape
backslash for simple escape sequences so Nushell materializes the separator
before calling the external tool. `"%H\t%an"` passes an actual tab; `"%H\\t%an"`
passes a literal `\t`. Use `char tab` / `char nl` when the format string also
needs Nushell interpolation or when explicit separators make parsing clearer.

```nu
# Wrong — single quotes pass literal "\t" to git
^git log --format='%H\t%an'

# Wrong — double backslash also passes literal "\t"
^git log --format="%H\\t%an"

# Preferred — simple and Nushell passes an actual tab
^git log --format="%H\t%an"

# Also good — explicit separator, useful with interpolation
let tab = (char tab)
^git log --format=$'%H($tab)%an'

# Also good — use a real newline delimiter, then parse with lines/parse
let nl = (char nl)
^some-tool --format=$'field1=%a($nl)field2=%b'
| lines
| parse '{key}={value}'
```

## String Type Overview

| Format              | Syntax      | Escapes            | Interpolation | Use case                               |
| ------------------- | ----------- | ------------------ | ------------- | -------------------------------------- |
| Single-quoted       | `'...'`     | None               | No            | Simple strings, Windows paths          |
| Double-quoted       | `"..."`     | `\n \t \" \\` etc. | No            | Strings needing escape sequences       |
| Raw string          | `r#'...'#`  | None               | No            | Regex, strings with quotes, multi-line |
| Bare word           | `hello`     | None               | No            | Command arguments, list items          |
| Backtick            | `` `...` `` | None               | No            | Paths/args with spaces, globs          |
| Single-interpolated | `$'...'`    | None               | Yes           | Embedding variables (preferred)        |
| Double-interpolated | `$"..."`    | Yes                | Yes           | Variables + escape sequences           |

## Examples

### Array optimization

```nu
# Before
let dirs = [$root, "node_modules", ".pnpm"]
let tools = ["git", "patch"]

# After
let dirs = [$root node_modules .pnpm]
let tools = [git patch]
```

### Interpolation optimization

```nu
# Before
print $"Package: ($pkg.name)"
print $"Error: ($tool) not found"

# After
print $'Package: ($pkg.name)'
print $'Error: ($tool) not found'
```

### Keep double quotes for escapes

```nu
# Keep — has \n escape
print $"\nNext steps:"
let content = "line1\nline2"

# Keep — contains literal single quote and interpolation
let marker = $"'($name)@($ver)':"
```

### Regex with raw strings

```nu
# Before
let pattern = "(?:a/|b/)?"

# After
let pattern = r#'(?:a/|b/)?'#
```
