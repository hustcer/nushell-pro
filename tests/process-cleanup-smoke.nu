use std/assert
use support/nu-process.nu run-nu-bounded

const support_dir = path self support

def test-result-and-argv [] {
    let selected_version = (run-nu-bounded 'version | get version')
    assert equal $selected_version.exit_code 0
    assert equal $selected_version.stderr ''
    assert equal ($selected_version.stdout | str trim) (version | get version)
    let argument = 'spaces; $literal (not-code)'
    let result = (run-nu-bounded 'def main [value: string] { $value | to json --raw }' --args [$argument])
    assert equal $result.exit_code 0
    assert equal ($result.stdout | from json) $argument
    assert equal $result.stderr ''
    let failed = (run-nu-bounded 'print out; print --stderr err; exit 7')
    assert equal $failed {stdout: "out\n", stderr: "err\n", exit_code: 7}
}

def test-nested-timeout [root: path] {
    let pid_file = ($root | path join nested.json)
    let baseline = (job list | get id)
    try {
        let outcome = try {
            run-nu-bounded r#'def main [target: path] {
    ^$nu.current-exe --no-config-file -c '
def main [target: path, parent: int] {
    {parent: $parent, nested: $nu.pid} | to json | save $target
    sleep 30sec
}' -- $target $nu.pid
}'# --args [$pid_file] --timeout 1sec
            null
        } catch {|err| $err.msg }
        assert equal $outcome 'Nu test process timed out after 1sec'
        # Readiness proves the nested producer actually ran before cancellation.
        assert ($pid_file | path exists)
        let owned_pids = (open $pid_file | values)
        assert equal ($owned_pids | length) 2
        assert (ps | where {|p| $p.pid in $owned_pids } | is-empty)
        assert equal (job list | get id) $baseline
    } finally {
        # A broken helper must not leave the reproducer running after an assertion.
        if ($pid_file | path exists) {
            for pid in (open $pid_file | values) { try { kill --force --quiet $pid } }
        }
    }
}

def test-startup-and-preflight [root: path] {
    let marker = ($root | path join must-not-start.txt)
    let baseline = (job list | get id)
    let startup = try {
        run-nu-bounded 'def main [target: path] { "started" | save $target }' --args [$marker] --timeout 1ns
        null
    } catch {|err| $err.msg }
    assert equal $startup 'Nu test process timed out after 1ns'
    assert (not ($marker | path exists))
    assert equal (job list | get id) $baseline
    assert error { run-nu-bounded 'print unused' --timeout 0ns }
    let missing_tool = (with-env {PATH: []} {
        try { run-nu-bounded 'print unused'; null } catch {|err| $err.msg }
    })
    let tool = if $nu.os-info.name == windows { 'taskkill' } else { 'kill' }
    assert equal $missing_tool $'Nu process cleanup requires external ($tool) on PATH'
    assert equal (job list | get id) $baseline
}

def test-legacy-process-schema [root: path] {
    if $nu.os-info.name == windows { return }
    # On 0.117, hide the group column to simulate older macOS Nu; on 0.116
    # it is already absent. %ps still selects the native builtin in either case.
    let program = r#'def ps [--long(-l)] {
    if $long { %ps --long | reject --optional process_group_id } else { %ps }
}
use nu-process.nu run-nu-bounded
def main [target: path] {
    let outcome = try {
        run-nu-bounded 'def main [target: path] { "started" | save $target }' --args [$target] | ignore
        'released'
    } catch {|err| $err.msg }
    $outcome | to json
}'#
    let marker = ($root | path join legacy-started.txt)
    let success = (do {
        cd $support_dir
        ^$nu.current-exe --no-config-file -c $program -- $marker
    } | complete)
    assert equal $success.exit_code 0
    assert equal $success.stderr ''
    assert equal ($success.stdout | from json) released
    assert ($marker | path exists)

    let tools = ($root | path join kill-only)
    mkdir $tools
    let kill_path = (which --all kill | where type == external | first | get path)
    ^ln -s $kill_path ($tools | path join kill)
    let forbidden = ($root | path join legacy-must-not-start.txt)
    let missing_ps = (with-env {PATH: [$tools]} {
        do {
            cd $support_dir
            ^$nu.current-exe --no-config-file -c $program -- $forbidden
        } | complete
    })
    assert equal $missing_ps.exit_code 0
    assert equal $missing_ps.stderr ''
    assert equal ($missing_ps.stdout | from json) 'Nu process-group inspection requires external ps on PATH'
    assert (not ($forbidden | path exists))
}

def main [] {
    let root = (mktemp --directory)
    try {
        test-result-and-argv
        test-nested-timeout $root
        test-startup-and-preflight $root
        test-legacy-process-schema $root
    } finally { rm --recursive --force $root }
    assert (not ($root | path exists))
    print 'PASS: bounded Nu process cleanup (4 groups)'
}
