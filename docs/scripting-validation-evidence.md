# Scripting validation and interpreter-boundary evidence

Verified on 2026-09-14 with Nu **0.115.1**. The pre-change skill baseline was
`759a7d2`. Existing validation/daemon and 0.115 smoke suites passed before edits.
This is runtime/example validation, not an agent-performance A/B benchmark.
The new suite has not been rerun on Nu 0.114.

## Authoritative inputs

- English docs checkout: `nu-docs` at `5ae31c05`, including
  `commands/docs/nu-check.md`, `commands/docs/source.md`, and
  `book/working_with_strings.md`. Both command pages declare version 0.115.1.
- Nushell source checkout: `b6e6562a9`, specifically
  `crates/nu-command/src/system/nu_check.rs`,
  `crates/nu-command/tests/commands/nu_check.rs`, and
  `crates/nu-command/src/misc/source.rs`.
- Public English references:
  [nu-check](https://www.nushell.sh/commands/docs/nu-check.html),
  [source](https://www.nushell.sh/commands/docs/source.html), and
  [strings](https://www.nushell.sh/book/working_with_strings.html).

The local source implementation checks newly added `parse_errors` and returns
`false`, or prints a diagnostic and throws with `--debug`. It creates a fresh
working set without merging it or evaluating the parsed script body. File
input sets a file stack; piped text is parsed without a filename, even if a path
argument is supplied. `source` explicitly evaluates its parsed block.

## Reproductions and corrections

| Input or operation                               | Observed result                                                                                   | Guidance                                                           |
| ------------------------------------------------ | ------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------ |
| Unclosed parenthesis / `let value: int = "text"` | Plain `nu-check`: false with CLI exit 0; `--debug`: nonzero uncaught error                        | Prefer `--debug` for a CLI gate, consume plain booleans explicitly |
| Same invalid scripts with `--ide-check`          | Exit 0 with Error diagnostic JSONL                                                                | Retain record-based checks for structured diagnostics              |
| Missing input                                    | `nu-check` throws; IDE check's missing-file trap remains covered by the existing suite            | Do not infer file existence from IDE success                       |
| Top-level write to an owned sentinel             | Neither checker writes it; `source` writes it                                                     | Remove source-as-validation advice                                 |
| `error make` at runtime                          | Parse check passes, execution fails                                                               | Parsing does not prove behavior                                    |
| `$'(1 + 1) items'`                               | Parse check passes, execution produces `2 items`                                                  | Assert intended string output                                      |
| Saved script with sibling import                 | Direct file check passes; anonymous piped text with the same path fails in the controlled fixture | Pass saved file paths directly                                     |
| Original basic test-runner example               | Parser rejects the escaped single quote in its interpolated print string                          | Replace generated command source with explicit test closures       |

## Executable coverage

Run `nu --no-config-file tests/strings-and-validation-smoke.nu` (Node required,
no npm packages). Its six groups cover the parse-check contracts, top-level
side effects versus intentional sourcing, relative imports, string meaning,
real JavaScript argument round-trip, and the actual Markdown test-runner example.
JavaScript values include quotes, parentheses, backslashes, a newline, Unicode,
an empty string, a leading-zero string, an integer, a boolean and a harmless
injection-looking string. The fixed evaluator records that the string did not
change its sentinel. The documented runner must pass two tests, reject a forced
assertion failure and reject zero selected tests without printing success.

Only the suite's own temporary fixture is removed, in `finally`, and cleanup
is asserted. The suite captures an explicit pass/failure outcome before cleanup
and rethrows failure afterward; a negative run against the old documentation
exits nonzero and does not print its success message. Ordinary Nu parse checks
are not a sandbox for untrusted source.
