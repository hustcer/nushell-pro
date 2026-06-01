# nushell-pro

Nushell best practices, security hardening, and code review skill for Agents.

Write idiomatic, performant, secure, and maintainable [Nushell](https://www.nushell.sh/) scripts — with built-in code review, anti-pattern detection, and Bash-to-Nushell conversion.

## Features

- **Best Practices** — Naming conventions, type annotations, I/O signatures, functional pipeline style, string format priority, and formatting rules
- **Security Hardening** — Injection prevention, path traversal protection, credential scoping, safe file/temp operations, environment sanitization
- **Code Review** — Comprehensive checklist covering security, correctness, style, performance, and robustness
- **Anti-Pattern Detection** — 25 common mistakes with idiomatic fixes
- **Type System** — Type hierarchy, complex types, type guards, null safety patterns
- **Bash Conversion** — Side-by-side Bash-to-Nushell translation guide
- **Performance** — Parallel processing with `par-each`, streaming patterns, memory-efficient techniques
- **Data Processing** — Polars dataframes (lazy/eager), group-by, joins, expressions, column selectors, and large-data / columnar analytics

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
└── references/
    ├── security.md                      # Threat model, safe patterns, Windows risks
    ├── script-review.md                 # Full review checklist (5 categories)
    ├── anti-patterns.md                 # 25 anti-patterns with fixes
    ├── data-and-types.md                # Type system, collections, conversions
    ├── dataframes.md                    # Polars dataframes: lazy/eager, group-by, joins, large data
    ├── advanced-patterns.md             # Streaming, closures, parallel, debugging
    ├── modules-and-scripts.md           # Modules, exports, testing, attributes
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
8. Parallel ready — immutable code enables easy `par-each`

### Security Model

Nushell is safer than Bash by design (no `eval`, arguments passed as arrays), but risks remain:

| Risk Level | Threats                                                           |
| ---------- | ----------------------------------------------------------------- |
| Critical   | Code injection via `nu -c`, `^sh -c`, plugin injection            |
| High       | Path traversal, credential leaks, PATH hijacking, glob injection  |
| Medium     | TOCTOU races, temp file races, unhandled errors, config tampering |

### Script Review

The skill includes a 5-category review checklist:

1. **Security** (critical) — injection, paths, credentials, destructive ops
2. **Correctness** — types, errors, null safety, logic
3. **Style** — naming, strings, formatting, documentation
4. **Performance** — parallelism, streaming, caching
5. **Robustness** — input validation, file safety, process management

## License

MIT
