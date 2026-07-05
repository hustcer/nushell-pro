# Nushell Modules & Scripts Reference

## Module Organization

### File-form (simple modules)

```
my-command.nu          # Single-file module, module name = filename
```

### Directory-form (larger modules)

```
my-module/
├── mod.nu             # Module entry point (required)
├── utils.nu           # Submodule
├── config.nu          # Submodule
└── tests/
    ├── mod.nu         # Test module entry point
    └── utils_test.nu  # Test file
```

Both forms behave identically once imported; only the path changes.

## Export Types

| Export       | Keyword            | Example                             |
| ------------ | ------------------ | ----------------------------------- |
| Commands     | `export def`       | `export def my-cmd [] { ... }`      |
| Env commands | `export def --env` | `export def --env setup [] { ... }` |
| Aliases      | `export alias`     | `export alias ll = ls -l`           |
| Constants    | `export const`     | `export const version = '1.0.0'`    |
| Externals    | `export extern`    | `export extern "git push" [...]`    |
| Submodules   | `export module`    | `export module utils.nu`            |
| Re-exports   | `export use`       | `export use utils.nu *`             |
| Env setup    | `export-env`       | `export-env { $env.FOO = 'bar' }`   |

Only `export`-ed definitions are public. Non-exported definitions are private (local to the module).

## The `main` Convention

When a command name matches the module name, use `export def main`:

```nu
# increment.nu
export def main []: int -> int {
    $in + 1
}

export def by [amount: int]: int -> int {
    $in + $amount
}
```

```nu
use increment
5 | increment       # => 6
5 | increment by 3  # => 8
```

## Submodule Patterns

### `export module` — Preserves submodule namespace

```nu
# mod.nu
export module utils.nu      # Commands accessed as: my-module utils <cmd>
```

Nu 0.114+ no longer imports exported submodules implicitly when the parent
module is imported. If callers should reach a submodule through the parent
namespace, re-export it explicitly from the parent:

```nu
export module utils {
    export def clean [] { 'clean' }
}

export use utils             # Enables: my-module utils clean
```

Without the explicit `export use utils`, `use my-module` imports the parent
exports but not `my-module utils clean`.

### `export use` — Flattens into parent namespace

```nu
# mod.nu
export use utils.nu *       # Commands accessed as: my-module <cmd>
```

Use `export use utils.nu *` only when flattening the commands into the parent is
the intended public API. Use `export use utils.nu` when preserving the submodule
namespace is clearer. A `use` inside another module does not run the imported
module's `export-env` block, matching the previous implicit behavior.

## Environment Setup

```nu
# mod.nu
export-env {
    $env.MY_MODULE_PATH = ($env.CURRENT_FILE | path dirname)
    $env.MY_MODULE_VERSION = '2.0.0'
}
```

## Inline Module Definition

```nu
module my_module {
    export def public-func [] { 'hello' }
    def private-func [] { 'private' }
    export const MY_CONST = 42
}

use my_module *
use my_module [public-func MY_CONST]
```

## Import Patterns

```nu
use my-module                    # Import module namespace
use my-module *                  # Import all exports into current scope
use my-module [func-a func-b]   # Import specific exports
use lib/helpers.nu *             # Import from file path
```

## Scripts

### Basic script

```nu
# myscript.nu
def greet [name] {
    $'Hello, ($name)!'
}

greet 'World'
```

Definitions run first (regardless of position in file), then the script body runs top-to-bottom.

### Pipeline scripts with `run` (Nu 0.114+)

`run` lets a `.nu` script act as a pipeline stage. Prefer it when the script
should transform pipeline input and keep its definitions isolated from the
caller.

```nu
# shout.nu
str uppercase
```

```nu
'Hello Nushell!' | run shout.nu | str camel-case
```

If a top-level `def main` exists, `run` invokes it and passes pipeline input
through the declared signature:

```nu
# length-plus.nu
def main []: string -> int {
    str length
}

'Hello' | run length-plus.nu
```

`run` is a parser keyword, so the target script file must already exist when the
calling block is parsed; do not create the script earlier in the same parsed
block and expect `run` to see it. Resolution uses the current directory,
`NU_LIB_DIRS`, or explicit paths; it does not search `PATH`. Use
`run --full-reparse script.nu` in file-watch loops or repeated test runs when
the script file changes between invocations.

### Parameterized scripts with main

```nu
#!/usr/bin/env nu

# Build the project
def "main build" [
    --release (-r)    # Build in release mode
] {
    print 'Building...'
}

# Run tests
def "main test" [
    --verbose (-v)    # Show test details
] {
    print 'Testing...'
}

def main [] {
    print 'Usage: script.nu <build|test>'
}
```

```nu
nu myscript.nu           # => Usage: script.nu <build|test>
nu myscript.nu build     # => Building...
nu myscript.nu test      # => Testing...
```

**Important:** You must define a `main` command for subcommands to be accessible. An empty `def main [] {}` suffices.

### Multiline calls with named flags

When calling custom commands with named flags, keep short invocations on one
line. If a call must span lines, wrap the whole invocation in parentheses. A
bare newline can end the command before the flags are parsed.

```nu
# Good
deploy staging --target api --dry-run

# Good
let plan = (
    deploy staging
        --target api
        --dry-run
)

# Bad
deploy staging
--target api
--dry-run
```

### Shebang

```nu
#!/usr/bin/env nu
'Hello World!'
```

For stdin access: `#!/usr/bin/env -S nu --stdin`

## Attribute System (v0.103+)

```nu
@example 'Greet a user' { greet 'Alice' } --result 'Hello, Alice!'
@deprecated 'Use new-command instead.'
@category 'network'
@search-terms ['http' 'web' 'api']
```

## Parse-Time vs Runtime

| Feature                | Parse-time      | Runtime               |
| ---------------------- | --------------- | --------------------- |
| `const` values         | Yes             | No (already resolved) |
| `let` values           | No              | Yes                   |
| `source` / `use` paths | Must be known   | N/A                   |
| `run` script paths     | File must exist  | Runs isolated         |
| Type checking          | Yes             | Some                  |
| `def` names            | Must be literal | N/A                   |
| Syntax errors          | Caught here     | N/A                   |

```nu
# Works — const is resolved at parse time
const path = 'scripts/utils.nu'
source $path

# Error — let is runtime only
let path = 'scripts/utils.nu'
source $path    # Error: not a parse-time constant
```

## Testing

### Nupm package tests

```
my-package/
├── nupm.nuon
├── mod.nu
└── tests/
    ├── mod.nu          # Test entry point
    └── utils_test.nu   # Test file
```

Only fully exported commands from `tests` module are run by `nupm test`.

### Standalone tests with std assert

```nu
use std/assert

for t in [
    [input expected];
    [0 0]
    [1 1]
    [2 1]
    [3 2]
] {
    assert equal (fib $t.input) $t.expected
}
```

### Available assert commands

```nu
use std/assert

assert (condition)                    # Basic assertion
assert equal $actual $expected        # Equality check
assert not equal $a $b               # Inequality check
assert str contains $haystack $needle # String containment
assert length $list $expected_len     # List length
assert error { failing-command }      # Expect an error
```

### Custom assertions

```nu
def "assert positive" [n: int] {
    assert ($n > 0) --error-label {
        text: $'Expected positive number, got ($n)'
        span: (metadata $n).span
    }
}
```

### Basic test framework (without Nupm)

```nu
use std/assert
source fib.nu

def main [] {
    print 'Running tests...'
    let test_commands = (
        scope commands
            | where ($it.type == 'custom')
                and ($it.name | str starts-with 'test ')
                and not ($it.description | str starts-with 'ignore')
            | get name
            | each {|test| [$'print \'Running test: ($test)\'' $test] } | flatten
            | str join '; '
    )
    nu --commands $'source ($env.CURRENT_FILE); ($test_commands)'
    print 'Tests completed successfully'
}

def "test fib" [] {
    for t in [[input expected]; [0 0] [1 1] [2 1] [5 5]] {
        assert equal (fib $t.input) $t.expected
    }
}

# ignore
def "test skipped" [] {
    print 'This test will not be executed'
}
```
