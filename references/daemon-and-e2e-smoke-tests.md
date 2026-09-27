# Daemon and E2E Smoke Tests

Use this reference for tests that start a server, watcher, worker, database,
language service, or any other long-running process. A useful smoke test proves
both the happy path and the lifecycle contract: isolated startup, bounded
readiness, a real probe, and complete cleanup.

## Lifecycle checklist

1. Create a unique root with `mktemp --directory`.
2. Put state, logs, sockets, caches, and temporary files under that root.
3. Scope environment changes with `with-env`; do not alter the developer's
   normal config or state directories.
4. Start the daemon and immediately retain its Nushell job ID. Observe child
   PIDs from `job list` when the job launches external processes.
5. Poll an explicit readiness condition until a deadline.
6. Run the smallest real client request and inspect its structured result.
7. Stop the job/process in `finally`, even when startup or assertions fail.
8. Verify that the job, child processes, and owned state are gone.

The job ID returned by `job spawn` is a Nushell job-table ID, not an operating
system PID. `job list` currently exposes `id`, `type`, `pids`, and
`description`; `pids` can be empty briefly before an external child starts.
Track the job ID first, then retain any observed PIDs needed for post-cleanup
checks.

Current Nushell provides `job spawn`, `job list`, `job kill`, `job describe`,
`job id`, `job send`, `job recv`, `job flush`, and `job unfreeze`. There is no
`job wait` command; do not invent or depend on one. Use readiness/deadline
polling and explicit cleanup instead. When the spawned fixture is itself
Nushell code, its mailbox is a marker-free readiness channel: the job runs
`'ready' | job send 0` (the main thread is job `0`) and the test blocks on
`job recv --timeout 5sec`.

## Deadline-based readiness

A fixed `sleep 2sec` is both slow on fast machines and flaky on slow ones. Poll
the condition that makes the daemon usable: a successful health request, an
open socket, a ready marker, or a parseable status record.

```nu
def wait-until [
    predicate: closure
    --timeout: duration = 5sec
    --interval: duration = 50ms
] {
    let deadline = ((date now) + $timeout)

    loop {
        if (do $predicate) {
            return
        }

        if (date now) >= $deadline {
            error make {msg: $'Readiness deadline exceeded after ($timeout)'}
        }

        sleep $interval
    }
}
```

Keep the interval short but non-zero. The timeout is the maximum wait, not an
expected startup duration. If the tracked job disappears before readiness,
fail immediately with its logs rather than waiting until the deadline.

## Isolated background fixture

This small fixture uses a marker for readiness and a nested Nushell process as
the controlled long-running child. A real test should replace the marker-only
probe with the product's health command or client request.

```nu
use std/assert

let fixture_root = (mktemp --directory)
let state_dir = ($fixture_root | path join 'state')
let temp_dir = ($fixture_root | path join 'tmp')
let ready_file = ($state_dir | path join 'ready.json')
mkdir $temp_dir

try {
    let job_id = (with-env {
        APP_STATE_DIR: $state_dir
        TMPDIR: $temp_dir
    } {
        job spawn --description 'daemon smoke fixture' {
            mkdir $env.APP_STATE_DIR
            {status: 'ready', state_dir: $env.APP_STATE_DIR}
            | to json
            | save --force ($env.APP_STATE_DIR | path join 'ready.json')

            ^nu --no-config-file -c 'loop { sleep 1sec }'
        }
    })

    try {
        wait-until {
            if (job list | where id == $job_id | is-empty) {
                error make {msg: 'Background job stopped before readiness'}
            }

            $ready_file | path exists
        } --timeout 3sec

        let ready = (open $ready_file)
        assert equal $ready.status 'ready'

        # Replace this marker assertion with one real client/health probe.
        assert equal $ready.state_dir $state_dir
    } finally {
        try { job kill $job_id }
    }

    wait-until {
        $job_id not-in (job list | get id)
    } --timeout 2sec
} finally {
    rm -r -f $fixture_root
}
```

The nested `try/finally` matters. The inner block owns the background job; the
outer block owns the temporary directory. This preserves cleanup if a probe or
assertion raises an error. `job kill` errors when the job has already exited,
so the `try` wrapper keeps cleanup idempotent without a check-then-kill race
that could mask the original failure; the later poll on `job list` still
proves the job terminated.

A runnable variant of this fixture is maintained at
`tests/validation-and-daemon-smoke.nu` in this skill's repository, with
repo-specific environment names. When editing either copy, mirror structural
changes in the other.

## External probes and expected failures

Every status-sensitive external invocation should use `complete` and inspect
`exit_code`, `stdout`, and `stderr` separately:

```nu
let probe = (^curl --silent --show-error --fail $health_url | complete)
if $probe.exit_code != 0 {
    error make {msg: $'Health probe failed: ($probe.stderr | str trim)'}
}

let status = ($probe.stdout | from json)
```

During readiness polling, connection-refused stderr is often expected. Use the
exit code to return `false` and retry; retain only the last probe or a bounded
log excerpt for the timeout error. After readiness, the same non-zero result is
a real smoke-test failure. Do not merge stdout and stderr before `complete` if
the test needs to distinguish them.

Pass every external argument as a separate value. Never interpolate a daemon
or probe command into a string for `nu -c`, `source`, `run`, or a shell.

## Portability and cleanup evidence

- Discover optional clients and OS tools with `which` before using them. Skip
  with an explicit reason or select a supported alternative; do not silently
  weaken the probe. `which name` returns only the highest-precedence match, so
  a Nushell built-in shadows an external tool of the same name — `which ps`
  reports the built-in, and a `which ps | where type == 'external'` guard is
  always empty. Use `which --all name | where type == 'external'` when only
  the external tool will do.
- Prefer a product-native status command over `ps`, port inspection, or log
  text. OS-level checks are useful additional cleanup evidence, not the primary
  readiness protocol.
- After `job kill`, poll until the job ID disappears. Verify observed child
  PIDs are gone with the built-in `ps` — `ps | where pid == $pid | is-empty` —
  which works on every platform Nushell supports, with no external `ps` probe
  or `which` gate.
- Nu 0.116's `job kill` uses external `kill` on Unix or `taskkill` on Windows
  (`nu-system/src/util.rs`). If a test strips PATH, retain that executable or
  reject the fixture before spawning. An empty PATH can make cancellation fail
  while the job entry is removed; polling only the job table will miss the
  surviving child. This does not add an external `ps` dependency.
- Assert that sockets, PID files, or state files owned by the fixture are gone
  before removing the fixture root. Remove only the directory returned by this
  test's own `mktemp --directory` call.
- Keep logs inside the fixture while the test runs. On failure, print a bounded
  diagnostic excerpt before cleanup or copy it to an explicitly requested
  artifact directory.
