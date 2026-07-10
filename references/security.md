# Nushell Security Reference

## Contents

- Nushell's security model and threat model
- Safe commands, paths, credentials, temp files, removal, globs, and environments
- Windows-specific risks
- Security review checklist

## Nushell's Security Model

### Built-in safety advantages over Bash

- **No `eval`** — Code cannot be dynamically generated and executed at runtime
- **Static parsing** — All code is fully parsed before any evaluation occurs
- **Arguments passed as arrays** — External command arguments go through `std::process::Command`, not through shell interpretation
- **Type system** — Parameter types are checked at parse time, preventing many injection classes
- **Scoped environment** — Environment changes are local to blocks by default

### Remaining attack surfaces

Despite these advantages, Nushell scripts can still be vulnerable to:

- Command injection via `^sh -c`, `^bash -c`, or `nu -c` with untrusted input
- Path traversal via unvalidated user-provided paths
- Credential leaking through environment variables
- Glob injection from user-controlled patterns
- TOCTOU (Time-of-Check-Time-of-Use) race conditions
- Unsafe temp file creation
- Unhandled external command failures

---

## Threat Model

### Critical risk

| Threat           | Vector                       | Mitigation                                            |
| ---------------- | ---------------------------- | ----------------------------------------------------- |
| Code injection   | `nu -c $user_input`          | Never pass untrusted input to `nu -c` or `source`     |
| Shell injection  | `^sh -c $untrusted`          | Never use `sh -c`/`bash -c` with interpolated strings |
| Plugin injection | `plugin add $untrusted_path` | Only install plugins from trusted sources             |

### High risk

| Threat            | Vector                    | Mitigation                                                      |
| ----------------- | ------------------------- | --------------------------------------------------------------- |
| Path traversal    | `open $user_path`         | Validate and canonicalize paths, check against base directory   |
| Credential leak   | `$env.API_KEY = 'secret'` | Use `with-env` for scoped credentials                           |
| PATH hijacking    | `$env.PATH` poisoning     | Use absolute paths for critical commands                        |
| Glob injection    | `^rm $user_pattern`       | Validate input doesn't contain glob chars, or use `--no-expand` |
| Env var injection | `$env.LD_PRELOAD`         | Clear dangerous env vars before running untrusted commands      |

### Medium risk

| Threat           | Vector                          | Mitigation                                  |
| ---------------- | ------------------------------- | ------------------------------------------- |
| TOCTOU           | Check then use file             | Use atomic operations where possible        |
| Temp file race   | Predictable `/tmp/myfile`       | Use built-in `mktemp` for unique temp files |
| Unhandled errors | External command silently fails | Use `complete` and check `exit_code`        |
| Glob DoS         | `glob **/*` on huge trees       | Use `--depth` limits                        |
| Config tampering | Modified `config.nu`            | Protect config file permissions             |

---

## Safe Patterns

### 1. External command execution

```nu
# DANGEROUS — shell interprets the entire string
^bash -c $'echo ($user_input)'
^sh -c $user_input

# SAFE — arguments passed directly, no shell interpretation
^echo $user_input
run-external 'ls' '-la' $user_dir

# SAFE — separated command and arguments
let args = [$user_file '--format' 'json']
^cat ...$args
```

**Why Nushell is safer:** When you run `^cmd $arg`, Nushell passes `$arg` as a single argument to the OS process API. It does NOT go through a shell, so `; rm -rf /` in `$arg` is treated as literal text, not a command separator.

**The exception:** `^sh -c`, `^bash -c`, `^cmd.exe /C`, and `nu -c` explicitly invoke a shell interpreter, which WILL interpret the string. Never use these with untrusted input.

**Allowlisting a command _string_ before `nu -c` is fragile — pass argv instead.**
Validating with a regex that "only allows `git show`/`git diff`" still feeds a
single string to an interpreter, so any gap in the pattern becomes command
injection. A common, real mistake: using `\s` as an argument separator —
because `\s` matches **newlines** (a literal space does not), a payload like
`"git diff abc\nrm -rf /"` slips through an allowlist such as
`^git (diff|show)\s.*\s.*$` (the second `\s` swallows the injected newline), and
`nu -c` then runs the second line as its own command. Validate structured argv/list data
(or a deliberately simple token grammar), then run the external with
**separated arguments** instead of re-interpreting the string:

```nu
# Fragile — the validated string still goes through an interpreter
if (is-allowed $cmd) { ^nu -c $cmd }   # a newline in $cmd starts a second command

# Robust — validate argv data and exec the binary directly
let argv = $request.argv   # e.g. [git diff abc], not "git diff abc\n..."
if (is-allowed-argv $argv) {
    ^($argv | first) ...($argv | skip 1)   # no shell, no re-parsing of the string
}
```

If a string allowlist is unavoidable, also reject control characters explicitly —
anchored regexes (`^...$`) do not guarantee a single line, `\s` is broader than
a literal space, and word-boundary/word-class shortcuts like `\b`/`\w` are not
command-token rules. Do not use space-splitting as a shell parser; only split
strings whose grammar has already rejected quotes, metacharacters, control
characters, and arguments containing spaces:

```nu
if ($cmd =~ r#'[\r\n]'#) { return false }   # inside a validator: no embedded newlines
```

### 2. Path validation

```nu
# Validate user paths against a base directory
def safe-open [name: string, --base-dir: path = '.'] {
    let base = ($base_dir | path expand --strict)
    let full = ($base | path join $name | path expand --strict)

    # Prove containment by path components, not a string prefix.
    try {
        $full | path relative-to $base | ignore
    } catch {
        error make {
            msg: 'Path traversal detected'
            label: {
                text: $'Path ($name) escapes base directory ($base)'
                span: (metadata $name).span
            }
        }
    }

    # Verify file exists
    if not ($full | path exists) {
        error make {
            msg: $'File not found: ($full)'
            label: {text: 'this file', span: (metadata $name).span}
        }
    }

    open $full
}
```

### 3. Home-relative paths

For paths that intentionally live under the user's home directory, compute the
prefix from `$nu.home-dir` instead of hardcoding a machine-specific absolute
path. This is especially important for constants used by `source`/`use`, where
`const` is required for parse-time resolution.

```nu
# Good — portable across users and machines
const work_dir = $'($nu.home-dir)/work/dir'

# Bad — tied to one local account
const work_dir = '/user/name/work/dir'
```

### 4. Credential handling

```nu
# Bad — credential persists in environment, visible to all child processes
$env.DB_PASSWORD = 'hunter2'
^psql -U admin $db_name
# Password is now in env of psql AND any commands after

# Good — scoped credential, only visible within the block
with-env {PGPASSWORD: (open ~/.secrets/db_pass | str trim)} {
    ^psql -U admin $db_name
}
# PGPASSWORD no longer exists here

# Good — read from file, use directly
let token = (open ~/.config/api-token | str trim)
http get $url -H {Authorization: $'Bearer ($token)'}

# Bad — credential in command line (visible in process listing)
^curl -u $'admin:($password)' $url

# Better — use stdin or config file for credentials
$password | ^tool --password-stdin
```

### 5. Safe file operations

```nu
# Bad — predictable temp file path (race condition)
let tmp = '/tmp/my-script-output'
'data' | save $tmp
# Another process could create/symlink this path first!

# Good — Nu 0.114 built-in, portable, and already returns a path string
let tmp = mktemp --suffix .tmp
try {
    'data' | save $tmp
    # ... process the file ...
} catch {|err|
    rm -f $tmp
    error make {msg: $err.msg}
}
rm -f $tmp

# Good — unique temp directory
let tmpdir = mktemp --directory
```

### 6. Safe rm and destructive operations

```nu
# Bad — glob from user input, could match anything
^rm -rf $user_provided_path

# Good — validate first
def safe-remove [target: path] {
    let resolved = ($target | path expand)

    # Never allow removing root or home
    if $resolved == '/' or $resolved == $nu.home-dir {
        error make {msg: $'Refusing to remove ($resolved)'}
    }

    # Verify it exists and is expected type
    if not ($resolved | path exists) {
        error make {msg: $'Path does not exist: ($resolved)'}
    }

    rm -r $resolved
}
```

### 7. Glob safety

```nu
# Bad — user input could contain glob characters
let pattern = $user_input
glob $pattern  # Could expand to unintended files

# Good — escape or validate
def safe-glob [pattern: string, --base-dir: path = '.'] {
    # Ensure pattern doesn't escape base directory
    if ($pattern | str contains '..') {
        error make {msg: 'Pattern must not contain ..'}
    }

    cd $base_dir
    glob $pattern --depth 3  # Limit recursion depth
}
```

### 8. External command error handling

```nu
# Bad — silently ignores failures
^git push origin main

# Good — check exit code
let result = (^git push origin main o+e>| complete)
if $result.exit_code != 0 {
    error make {msg: $'git push failed: ($result.stderr)'}
}

# Good — try/catch for simple cases
try {
    ^cargo test
} catch {
    print -e 'Tests failed'
    exit 1
}
```

### 9. Environment variable safety

```nu
# Sanitize PATH to prevent command hijacking
def with-safe-path [block: closure] {
    with-env {PATH: [/usr/local/bin /usr/bin /bin]} {
        do $block
    }
}

# Clear dangerous env vars before running untrusted commands
def safe-exec [cmd: string, ...args: string] {
    with-env {
        LD_PRELOAD: null
        LD_LIBRARY_PATH: null
        DYLD_INSERT_LIBRARIES: null
    } {
        run-external $cmd ...$args
    }
}
```

---

## Windows-Specific Risks

### CMD.EXE argument injection

When Nushell calls CMD internal commands on Windows, arguments pass through `cmd.exe /D /C`:

```nu
# These characters are dangerous in CMD context:
# & | < > ^ %
# % expands environment variables: %USERNAME%
# & chains commands: echo hello & whoami

# Nushell blocks \r, \n, and % in CMD arguments (built-in protection)
# But other special characters may still be risky
```

### Mitigation

- Avoid CMD internal commands when possible
- Use PowerShell or Nushell native commands instead
- Validate input doesn't contain `&`, `|`, `<`, `>`, `^`

---

## Security Review Checklist

When auditing a Nushell script for security:

1. **Code injection** — Search for `nu -c`, `source`, `^sh`, `^bash`, `^cmd.exe`, `run-external` with user-controlled arguments; a regex-validated command string re-fed to `nu -c` is still vulnerable (pass validated argv/list data as separated args instead)
2. **Path traversal** — Search for `open`, `save`, `rm`, `cp`, `mv`, `glob` with user-provided paths; check for `..` validation
3. **Home paths** — Search for hardcoded home-directory prefixes like `/Users/name`, `/home/name`, or `C:\Users\name`; compute them from `$nu.home-dir` instead
4. **Credentials** — Search for `$env.*KEY`, `$env.*SECRET`, `$env.*PASSWORD`, `$env.*TOKEN`; check if scoped with `with-env`
5. **External commands** — Verify `complete` or `try/catch` is used for error handling; check for `^` prefix
6. **File operations** — Check temp file creation uses `mktemp`; verify `rm` operations are guarded
7. **Glob patterns** — Check if user input flows into `glob` or `ls` patterns; verify `--depth` limits
8. **Environment** — Check if `$env.PATH` or `$env.LD_PRELOAD` could be poisoned
9. **Error masking** — Verify errors are not silently swallowed; check `try` blocks have meaningful `catch`
