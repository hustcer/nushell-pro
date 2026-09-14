# nushell-pro

Nushell best practices, security hardening, and code review skill for Agents.

Write idiomatic, performant, secure, and maintainable [Nushell](https://www.nushell.sh/) scripts — with built-in code review, anti-pattern detection, and Bash-to-Nushell conversion.

## Features

- **Best Practices** — Naming conventions, type annotations, I/O signatures, functional pipeline style, string format priority, and formatting rules
- **Security Hardening** — Injection prevention, path traversal protection, credential scoping, safe file/temp operations, environment sanitization
- **Stable CLI Tests** — PTY-width-independent assertions for nested Nushell diagnostics
- **Parse-First Validation** — `nu-check --debug` for scripts/modules, with behavioral checks for interpolation and generated payloads
- **IDE Diagnostics** — JSONL-aware `nu --ide-check` validation that catches errors even when the process exits successfully
- **Daemon & E2E Smoke Tests** — Deadline-based readiness checks, isolated state, tracked jobs/PIDs, and guaranteed cleanup
- **Evidence-Driven Code Review** — Version-aware findings with concrete triggers, impact, reproduction evidence, precise locations, and severity
- **Anti-Pattern Detection** — 35 common mistakes with idiomatic fixes
- **Type System** — Type hierarchy, complex types, type guards, null safety patterns
- **Nu 0.114 Support** — Stricter type checking, explicit submodule imports, `run`, POSIX `--`, SemVer, spreadsheet import changes, and updated diagnostics
- **Nu 0.115 Support** — YAML 1.2 contracts, `external_arg`, row conditions, binary filesize slicing, SemVer comparisons, null grouping, test migrations, and reproduction-verified workarounds for known 0.115.0 defects
- **Bash Conversion** — Side-by-side Bash-to-Nushell translation guide
- **Performance** — Parallel processing with `par-each`, streaming patterns, memory-efficient techniques
- **Data Processing** — Polars dataframes (lazy/eager), group-by, joins, window/sequence ops, nested list/struct data, reshaping, binning, time zones, SQL, column selectors, and large-data / columnar analytics

## Install

```bash
# Install by npx skills
npx skills add hustcer/nushell-pro
# OR Install for Claude by claude cli
claude skill add --name nushell-pro hustcer/nushell-pro
```

Or clone manually into a skills-compatible runtime directory:

```bash
git clone https://github.com/hustcer/nushell-pro.git /path/to/skills/nushell-pro
```

## Structure

```
nushell-pro/
├── SKILL.md                             # Main skill (core rules, always loaded)
├── tests/
│   ├── validation-and-daemon-smoke.nu   # Executable IDE/job lifecycle regression test
│   ├── nu-0.115-smoke.nu                # Executable 0.115 command/migration regression test
│   └── strings-and-validation-smoke.nu # Parse checks, JS data boundary and documented runner
└── references/
    ├── nu-0.114-migration.md            # Version migration and compatibility checklist
    ├── nu-0.115-migration.md            # YAML, CLI, command, and review changes
    ├── security.md                      # Threat model, safe patterns, Windows risks
    ├── script-review.md                 # Review method + 5-category checklist
    ├── anti-patterns.md                 # 35 anti-patterns with fixes
    ├── data-and-types.md                # Type system, collections, conversions
    ├── dataframes.md                    # Polars dataframes: lazy/eager, group-by, joins, large data
    ├── advanced-patterns.md             # Streaming, closures, parallel, debugging
    ├── modules-and-scripts.md           # Modules, exports, testing, attributes
    ├── daemon-and-e2e-smoke-tests.md    # Background jobs, readiness, isolation, cleanup
    ├── string-formats.md                # String type priority and rules
    └── bash-to-nushell.md               # Bash/POSIX conversion guide
```

`SKILL.md` is always loaded into context. Reference files are loaded on demand when the task requires deeper knowledge on a specific topic.

## What It Covers

### Core Principles

1. Think in pipelines — data flows through functional transformations
2. Immutability first — `let` by default, `mut` only when necessary
3. Structured data — tables, records, and lists over string parsing
4. Static parsing — `source`/`use` require parse-time constants
5. Implicit return — last expression is the return value
6. Scoped environment — `def --env` when caller-side changes are needed
7. Type safety — annotate parameters and I/O signatures
8. Prefer `match` for branching — avoid long `if`/`else if` chains when dispatching on one value
9. Parallel ready — immutable code enables easy `par-each`

### Security Model

Nushell is safer than Bash by design (no `eval`, arguments passed as arrays), but risks remain:

| Risk Level | Threats                                                           |
| ---------- | ----------------------------------------------------------------- |
| Critical   | Code injection via `nu -c`, `^sh -c`, plugin injection            |
| High       | Path traversal, credential leaks, PATH hijacking, glob injection  |
| Medium     | TOCTOU races, temp file races, unhandled errors, config tampering |

### Script Review

The skill includes a version-aware review method plus a 5-category checklist:

1. **Security** (critical) — injection, paths, credentials, destructive ops
2. **Correctness** — types, errors, null safety, logic
3. **Style** — naming, strings, formatting, documentation
4. **Performance** — parallelism, streaming, caching
5. **Robustness** — input validation, file safety, process management

## Validation

```bash
nu --no-config-file -c 'nu-check --debug tests/validation-and-daemon-smoke.nu'
nu --no-config-file tests/validation-and-daemon-smoke.nu
nu --no-config-file -c 'nu-check --debug tests/nu-0.115-smoke.nu'
nu --no-config-file tests/nu-0.115-smoke.nu
nu --no-config-file -c 'nu-check --debug tests/strings-and-validation-smoke.nu'
nu --no-config-file tests/strings-and-validation-smoke.nu
```

Prefer `nu-check --debug` for ordinary parse checks and add `--as-module` for
module content. Plain `nu-check` can print `false` while exiting `0`. Use
`--ide-check` when diagnostic JSONL/spans are needed, checking its records as
described in `SKILL.md`. Neither checker proves runtime behavior; `source`
executes code and is not a parse-only alternative.

The strings/validation suite requires Node for a controlled JavaScript
round-trip; it uses no npm dependencies or browser service. It also extracts
and executes the documented test runner, checking success, assertion failure,
and empty selection. The validation findings and source references are recorded
in [scripting validation evidence](docs/scripting-validation-evidence.md).

The executable smoke tests cover JSONL IDE diagnostics, controlled job/process
cleanup, YAML 1.2 boundaries, high-frequency 0.115 commands, null grouping,
SemVer edge cases, and raw script CLI arguments. They also lock two Nu 0.115.0
defects — `to yaml --non-roundtrip 'lossy'` being rejected, and a nested
`finally` being skipped — so the guidance is retracted as soon as a patched Nu
makes those assertions fail.

## License

MIT
