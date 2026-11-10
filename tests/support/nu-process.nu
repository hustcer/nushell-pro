const launcher = path self nu-process-child.nu

def timeout-error [timeout: duration] {
    error make {msg: $'Nu test process timed out after ($timeout)'}
}

def process-group-id [leader: int]: nothing -> int {
    let leader_row = (ps --long | where pid == $leader | first)
    let native_group = $leader_row.process_group_id?
    if $native_group != null { return $native_group }
    # Older macOS Nu (including 0.116) has no native process-group column.
    # Resolve this before opening the gate, so a missing tool cannot leak a fixture.
    if (which --all ps | where type == external | is-empty) {
        error make {msg: 'Nu process-group inspection requires external ps on PATH'}
    }
    let result = (^ps -p $leader -o pgid= | complete)
    if $result.exit_code != 0 {
        error make {msg: $'Cannot inspect Nu launcher process group: ($result.stderr | str trim)'}
    }
    $result.stdout | str trim | into int
}

# Windows has no POSIX process-group signalling; taskkill /T uses the owned tree.
def descendants [roots: list<int>, processes: table] {
    mut owned = $roots
    loop {
        let known = $owned
        let children = ($processes | where {|p| $p.ppid in $known and $p.pid not-in $known } | get pid)
        if ($children | is-empty) { break }
        $owned = ($owned | append $children)
    }
    $owned
}

def stop-owned-processes [worker: int, gate: path] {
    # A gate is written only after checking the leader against the job table
    # and (on Unix) its dedicated group. Without it the launcher cannot fork.
    let roots = if ($gate | path exists) {
        [(open --raw $gate | into int)]
    } else {
        job list | where id == $worker | get pids | flatten
    }
    let windows = $nu.os-info.name == windows
    let owned_pids = if $windows { descendants $roots (ps) } else { $roots }
    try {
        if $windows {
            for pid in $roots { ^taskkill /F /T /PID $pid | complete | ignore }
        } else if ($gate | path exists) {
            # job kill alone kills only the leader. Signal its whole group,
            # including children that remain after the leader has exited.
            # Arithmetic also works before 0.117, where -$group is a string.
            for group in $roots { ^kill -9 -- (0 - $group | into string) | complete | ignore }
        }
    } finally {
        # A completed worker can already be absent. Still cancel a live Nu thread.
        try { job kill $worker }
    }
    let deadline = ((date now) + 2sec)
    loop {
        let alive = if $windows or not ($gate | path exists) {
            ps | where {|p| $p.pid in $owned_pids } | is-not-empty
        } else {
            # Check the group itself even after its leader has exited. This
            # works with old ps schemas and includes surviving group members.
            $roots | any {|group| (^kill -0 -- (0 - $group | into string) | complete).exit_code == 0 }
        }
        if $worker not-in (job list | get id) and not $alive { break }
        if (date now) >= $deadline { error make {msg: 'Nu test process cleanup timed out'} }
        sleep 20ms
    }
}

# Run fixed, trusted Nu source with a deadline; preserve the selected binary.
# Fixtures must not detach into a new session/group. Unix cleanup covers the
# inherited process group; Windows uses taskkill /T. Call from the main thread.
export def run-nu-bounded [
    program: string
    --args: list<string> = []
    --timeout: duration = 5sec
]: nothing -> record {
    if $timeout <= 0ns { error make {msg: 'Nu test timeout must be positive'} }
    let kill_tool = if $nu.os-info.name == windows { 'taskkill' } else { 'kill' }
    if (which --all $kill_tool | where type == external | is-empty) {
        error make {msg: $'Nu process cleanup requires external ($kill_tool) on PATH'}
    }
    let root = (mktemp --directory)
    try {
        let ready = ($root | path join ready)
        let gate = ($root | path join gate)
        let exe = $nu.current-exe
        let deadline = ((date now) + $timeout)
        let worker = (job spawn {
            let result = (^$exe --no-config-file $launcher -- $ready $gate $program ...$args | complete)
            $result | job send 0 --tag (job id)
        })
        try {
            loop {
                if ($ready | path exists) { break }
                if (date now) >= $deadline { timeout-error $timeout }
                sleep 5ms
            }
            let leader = (open --raw $ready | into int)
            let job_pids = (job list | where id == $worker | get pids | flatten)
            if $leader <= 1 or $leader not-in $job_pids {
                error make {msg: 'Nu launcher is not owned by the test job'}
            }
            if $nu.os-info.name != windows {
                if (process-group-id $leader) != $leader {
                    error make {msg: 'Nu launcher has no dedicated process group'}
                }
                let probe = (^kill -0 -- (0 - $leader | into string) | complete)
                if $probe.exit_code != 0 {
                    error make {msg: 'Cannot signal the owned Nu process group'}
                }
            }
            # Only now can the launcher start the fixture. The file retains the
            # validated group ID even if a successful leader exits before cleanup.
            $leader | into string | save $gate
            let remaining = ($deadline - (date now))
            if $remaining <= 0ns { timeout-error $timeout }
            try {
                job recv --tag $worker --timeout $remaining
            } catch {|err|
                if $err.details.code? == 'nu::shell::job::recv_timeout' {
                    timeout-error $timeout
                } else { error make $err }
            }
        } finally { stop-owned-processes $worker $gate }
    } finally { rm --recursive --force $root }
}
