# Nushell Modules & Scripts Reference

## Contents

- Module organization, exports, `main`, and submodules
- Environment setup, inline modules, and imports
- Scripts, `run`, named flags, shebangs, and attributes
- Parse-time/runtime behavior and testing

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
`run --full-reparse script.nu` when the script file can change between
invocations, such as file-watch loops or tests that regenerate the script.

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

A multiline closure argument is the exception: braces keep the parser inside
the call, so flags on the closing-brace line — for example
`wait-until { ... } --timeout 3sec` — parse as part of the same invocation
without extra parentheses.

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

| Feature            | Parse-time      | Runtime                              |
| ------------------ | --------------- | ------------------------------------ |
| `const` values     | Yes             | No (already resolved)                |
| `let` values       | No              | Yes                                  |
| `source` path      | Must be known   | Executes script body                 |
| `use` path         | Must be known   | Imports module; may run `export-env` |
| `run` script paths | File must exist | Runs isolated                        |
| Type checking      | Yes             | Some                                 |
| `def` names        | Must be literal | N/A                                  |
| Syntax errors      | Caught here     | N/A                                  |

```nu
# Works — const is resolved at parse time
const path = 'scripts/utils.nu'
source $path

# Error — let is runtime only
let path = 'scripts/utils.nu'
source $path    # Error: not a parse-time constant
```

## Testing

### Parse Checks Before Execution

Use `nu-check --debug script.nu` for ordinary script checks, and add
`--as-module` only for module content. From a host shell, run a fixed command
with `nu --no-config-file -c 'nu-check --debug script.nu'`. Within Nu, pass a
runtime path directly as `nu-check --debug $script`; never interpolate an
untrusted path into `nu -c` source.

| Check                        | Failure contract                             | Intended use                                     |
| ---------------------------- | -------------------------------------------- | ------------------------------------------------ |
| `nu-check file.nu`           | `false` for parse errors; I/O failures throw | In-process boolean checks                        |
| `nu-check --debug file.nu`   | Parse errors throw and show a diagnostic     | Default script validation                        |
| `nu --ide-check 100 file.nu` | JSONL errors can accompany exit `0`          | Structured spans/diagnostics; parse every record |
| `source file.nu`             | Executes the top-level code                  | Intentional loading, not validation              |

Prefer file input when relative imports matter. `nu-check` with piped content
parses anonymous input, even if a path argument is supplied; it does not use
that path to recover the source file's import directory. Both parse checkers
can catch static type errors but do not run the target's ordinary top-level
commands, prove expected output, or isolate untrusted code in a sandbox.
Run behavioral tests separately against owned fixtures.

For `--ide-check`, verify the target exists, decode JSON Lines, fail on
`type: diagnostic` / `severity: Error`, and surface other diagnostic severities.
Hints are not failures. Check CLI exit/stderr and malformed JSONL separately;
see the main Skill's validation rules and `tests/validation-and-daemon-smoke.nu`.

Behavior verified with Nu 0.115.1 and the English
[nu-check](https://www.nushell.sh/commands/docs/nu-check.html) /
[source](https://www.nushell.sh/commands/docs/source.html) documentation.

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

### Stable assertions for nested Nushell diagnostics

Rendered diagnostics from `nu script.nu | complete` are presentation text, not
a stable protocol. They may include ANSI sequences and `|` gutters, and can
hard-wrap according to PTY width, sometimes inside words. Direct substring checks can pass
in CI but fail in a narrower interactive terminal.

Prefer direct `try/catch` and `$err.details` for in-process tests. When a CLI
integration test must inspect rendered `stderr`, normalize both values:

```nu
def diagnostic-text [value: any]: nothing -> string {
    $value
    | into string
    | ansi strip
    | str replace --all --regex r#'[\s|]+'# ''
}

def "assert diagnostic contains" [value: any, expected: string] {
    assert str contains (diagnostic-text $value) (diagnostic-text $expected)
}

let result = (^nu failing-script.nu | complete)
assert not equal $result.exit_code 0
assert diagnostic contains $result.stderr 'OpenSSL key generation failed'
```

Use a long, domain-specific phrase to keep the normalized assertion selective.
For a regression involving diagnostics or tables, also run the test under a
narrow PTY such as `stty cols 24 && nu tests/example.nu`.

### Basic test framework (without Nupm)

Keep test registration explicit and execute closures directly. Building Nu
source from discovered command names adds quoting, path and parser-state
problems to the test runner itself. Fail on an empty selection and let failed
assertions stop the run before printing a success count.

```nu
use std/assert

def increment [n: int]: nothing -> int {
    $n + 1
}

def run-tests [cases: table<name: string, run: closure>]: nothing -> nothing {
    if ($cases | is-empty) {
        error make {msg: 'No tests selected'}
    }
    for case in $cases {
        print $'Running test: ($case.name)'
        do $case.run
    }
    print $'Tests passed: ($cases | length)'
}

def main [] {
    let cases = [
        {name: positive, run: {|| assert equal (increment 1) 2 }}
        {name: negative, run: {|| assert equal (increment (-1)) 0 }}
    ]
    run-tests $cases
}
```
