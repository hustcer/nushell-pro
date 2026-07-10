# Bash to Nushell Conversion Reference

Quick reference for converting common Bash patterns to idiomatic Nushell.

## Contents

- Redirections, variables, strings, and conditionals
- Loops, files, command substitution, and functions
- Lists, records, processes, and JSON
- Error handling and common migration patterns

## Redirections & Pipes

| Bash                          | Nushell                                | Notes                    |
| ----------------------------- | -------------------------------------- | ------------------------ |
| `echo "text" > file`          | `'text' \| save file`                  |                          |
| `echo "text" >> file`         | `'text' \| save --append file`         |                          |
| `cmd 2>/dev/null`             | `cmd e>\| ignore`                      | Discard stderr           |
| `cmd > /dev/null 2>&1`        | `cmd o+e>\| ignore`                    | Discard all output       |
| `cmd 2>&1`                    | `cmd o+e>\| ...`                       | Merge stderr into stdout |
| `cmd1 \| tee log.txt \| cmd2` | `cmd1 \| tee { save log.txt } \| cmd2` |                          |
| `cmd \| head -5`              | `cmd \| first 5`                       |                          |
| `cmd \| tail -3`              | `cmd \| last 3`                        |                          |

## Variables

| Bash                   | Nushell                          | Notes                |
| ---------------------- | -------------------------------- | -------------------- |
| `FOO="bar"`            | `let foo = 'bar'`                | Immutable by default |
| `FOO="bar"`            | `mut foo = 'bar'`                | When mutation needed |
| `readonly FOO="bar"`   | `const foo = 'bar'`              | Parse-time constant  |
| `export FOO="bar"`     | `$env.FOO = 'bar'`               | Environment variable |
| `echo $FOO`            | `$env.FOO`                       | Access env var       |
| `echo ${FOO:-default}` | `$env.FOO? \| default 'default'` | With fallback        |
| `echo $?`              | `$env.LAST_EXIT_CODE`            | Last exit code       |
| `echo $RANDOM`         | `random int`                     | Random number        |

## String Operations

| Bash              | Nushell                             |
| ----------------- | ----------------------------------- |
| `${var^^}`        | `$var \| str uppercase`             |
| `${var,,}`        | `$var \| str lowercase`             |
| `${var:0:5}`      | `$var \| str substring 0..5`        |
| `${#var}`         | `$var \| str length`                |
| `${var/old/new}`  | `$var \| str replace old new`       |
| `${var//old/new}` | `$var \| str replace --all old new` |
| `${var%.ext}`     | `$var \| path parse \| get stem`    |

Nu 0.114 also adds stream-specific `ignore` flags. Use them when they make a
Bash redirection clearer: `ignore --stderr` consumes stderr, `ignore --stdout`
consumes stdout, and `ignore --show-errors` keeps errors visible while updating
`$env.LAST_EXIT_CODE`.

## Conditionals

Use `if` for single boolean predicates and short threshold checks. When several
branches dispatch on the same value, prefer `match` over an `if`/`else if`
chain.

```bash
# Bash
if [ "$x" -gt 10 ]; then
    echo "big"
elif [ "$x" -gt 5 ]; then
    echo "medium"
else
    echo "small"
fi
```

```nu
# Nushell
if $x > 10 {
    'big'
} else if $x > 5 {
    'medium'
} else {
    'small'
}
```

```bash
# Bash case dispatch
case "$status" in
    ok) handle_ok ;;
    error) handle_error ;;
    pending) handle_pending ;;
    *) handle_unknown ;;
esac
```

```nu
# Nushell — prefer match for enum-like or multi-branch dispatch
match $status {
    ok => { handle-ok }
    error => { handle-error }
    pending => { handle-pending }
    _ => { handle-unknown }
}
```

## Loops

```bash
# Bash — iterate files
for f in *.txt; do
    echo "$f"
done
```

```nu
# Nushell — functional
ls *.txt | get name | each {|f| print $f }

# Or simply
ls *.txt | get name
```

```bash
# Bash — C-style loop
for ((i=0; i<10; i++)); do
    echo $i
done
```

```nu
# Nushell
0..9 | each {|i| print $i }
# Or
for i in 0..9 { print $i }
```

```bash
# Bash — while loop
while read -r line; do
    echo "$line"
done < file.txt
```

```nu
# Nushell
open file.txt | lines | each {|line| $line }
```

## File Operations

| Bash                  | Nushell                          |
| --------------------- | -------------------------------- |
| `cat file`            | `open file` or `open --raw file` |
| `wc -l file`          | `open file \| lines \| length`   |
| `touch file`          | `touch file`                     |
| `mkdir -p dir`        | `mkdir dir`                      |
| `rm -rf dir`          | `rm -r dir`                      |
| `cp src dst`          | `cp src dst`                     |
| `mv src dst`          | `mv src dst`                     |
| `find . -name "*.rs"` | `glob **/*.rs`                   |
| `test -f file`        | `('file' \| path exists)`        |
| `test -d dir`         | `('dir' \| path type) == dir`    |
| `basename path`       | `'path' \| path basename`        |
| `dirname path`        | `'path' \| path dirname`         |

## Command Substitution

```bash
# Bash
FILES=$(ls *.txt)
COUNT=$(wc -l < file.txt)
```

```nu
# Nushell — no special syntax needed
let files = (ls *.txt)
let count = (open file.txt | lines | length)
```

## Functions → Custom Commands

```bash
# Bash
greet() {
    local name="$1"
    local greeting="${2:-Hello}"
    echo "${greeting}, ${name}!"
}
```

```nu
# Nushell
def greet [
    name: string
    --greeting (-g): string = 'Hello'
]: nothing -> string {
    $'($greeting), ($name)!'
}
```

## Arrays → Lists

```bash
# Bash
arr=(one two three)
echo ${arr[0]}
echo ${#arr[@]}
arr+=("four")
```

```nu
# Nushell
let arr = [one two three]
$arr | get 0           # or $arr.0
$arr | length
$arr | append four     # Returns new list (immutable)
```

## Associative Arrays → Records

```bash
# Bash
declare -A config
config[host]="localhost"
config[port]="8080"
echo "${config[host]}"
```

```nu
# Nushell
let config = {host: localhost, port: 8080}
$config.host
```

## Process Management

| Bash                     | Nushell                               |
| ------------------------ | ------------------------------------- |
| `command &`              | `job spawn { command }`               |
| `jobs`                   | `job list`                            |
| `kill $PID`              | `kill $pid` or `job kill $id`         |
| `ps aux`                 | `ps`                                  |
| `command1 && command2`   | `command1; command2`                  |
| `command1 \|\| command2` | `try { command1 } catch { command2 }` |

## JSON Processing (jq → Nushell)

```bash
# Bash + jq
curl -s api | jq '.users[] | {name, email}'
curl -s api | jq '.items | length'
curl -s api | jq '.data | sort_by(.date)'
```

```nu
# Nushell — native structured data
http get api | get users | select name email
http get api | get items | length
http get api | get data | sort-by date
```

## Error Handling

```bash
# Bash
set -e    # Exit on error
trap cleanup EXIT

if ! command; then
    echo "Failed" >&2
    exit 1
fi
```

```nu
# Nushell
try {
    some-command
} catch {|err|
    print -e $'Failed: ($err.msg)'
    exit 1
}
```

## Common Patterns

### Check if command exists

```bash
# Bash
if command -v git &> /dev/null; then echo "found"; fi
```

```nu
# Nushell
if (which git | is-not-empty) { print 'found' }
```

### Read environment with default

```bash
# Bash
PORT="${PORT:-8080}"
```

```nu
# Nushell
let port = ($env.PORT? | default 8080)
```

### Multiline strings

```bash
# Bash heredoc
cat << 'EOF'
line 1
line 2
EOF
```

```nu
# Nushell raw string
r#'line 1
line 2'#
```

### Semantic versions

```bash
# Bash — fragile lexical/manual version handling
printf '%s\n' "$@" | sort -V
IFS=. read -r major minor patch <<< "$version"
```

```nu
# Nushell 0.114+ — SemVer values sort and bump correctly
$versions | each { into semver } | sort
$version | into semver | semver bump patch
$version | into semver | $in in ('>=1.0.0' | into semver-range)
```
