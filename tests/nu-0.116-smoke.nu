use std/assert

def flags [--count: int = 5, --nullable: oneof<int, nothing> = 7, --verbose] {
    {count: $count, nullable: $nullable, verbose: $verbose}
}

def complete-choice [token: record] {
    {completions: [alpha beta], options: {filter: true}, fallback: false}
}
def choose [value: string@complete-choice] { $value }

# Isolate potentially deadlocking code in a killable process, not a Nu worker.
# Use the job's own ID as the mailbox tag so a late result cannot satisfy a
# later invocation. This helper is only called from this suite's main thread.
def run-nu-bounded [program: string, --timeout: duration = 5sec] {
    # job kill shells out to kill/taskkill; detect a stripped PATH before
    # creating a child that could otherwise survive failed cancellation.
    let kill_tool = if $nu.os-info.name == windows { 'taskkill' } else { 'kill' }
    if (which --all $kill_tool | where type == external | is-empty) {
        error make {msg: $'Nu job cleanup requires external ($kill_tool) on PATH'}
    }
    let nu_exe = $nu.current-exe
    let worker = (job spawn {
        let result = (^$nu_exe --no-config-file -c $program | complete)
        $result | job send 0 --tag (job id)
    })
    let outcome = try {
        {result: (job recv --tag $worker --timeout $timeout)}
    } catch {|err| {error: $err} }
    let child_pids = (job list | where id == $worker | get pids | flatten)
    try { job kill $worker }
    let deadline = ((date now) + 2sec)
    loop {
        let child_alive = (ps | where {|p| $p.pid in $child_pids } | is-not-empty)
        if $worker not-in (job list | get id) and not $child_alive { break }
        if (date now) >= $deadline { error make {msg: 'Nu test process cleanup timed out'} }
        sleep 20ms
    }
    if $outcome.error? != null {
        error make {msg: $'Nu test process timed out after ($timeout)'}
    }
    $outcome.result
}

def test-flags [] {
    assert equal (flags --count=(null)).count 5
    assert equal (flags --nullable=null).nullable null
    assert equal (flags ...{count: 9, nullable: null, verbose: true}) {count: 9, nullable: null, verbose: true}
    assert equal (flags ...{count: null, verbose: false}).count 5
    assert equal (flags ...{verbose: null}).verbose false
    assert error { flags ...{unknown: true} }
    assert error { flags ...{count: wrong} }
}

def test-completion [] {
    let input = ('git checkout mai' | commandline complete --input)
    assert equal $input.token.text mai
    assert equal $input.place.command [git checkout mai]
    assert equal $input.buffer 'git checkout mai'
    assert equal ('choose al' | commandline complete --detailed | get value) [alpha]
    assert error { 'choose al' | commandline complete --input --detailed }
    let external = (^$nu.current-exe --no-config-file -c r#'
$env.config.completions.external.completer = {|place| [($place.command | str join ":")] }
alias gco = git checkout
"gco ma" | commandline complete --detailed | get value | to json
'# | complete)
    assert equal $external.exit_code 0
    assert equal ($external.stdout | from json) ['git:checkout:ma']
    # Release notes overstate the rejection of unknown positional names:
    # the first two positions still use the deprecated compatibility bridge.
    let legacy = (^$nu.current-exe --no-config-file -c r#'
def old-completer [anything] { [($anything | describe)] }
def old-choice [x: string@old-completer] {}
"old-choice " | commandline complete --detailed | get value | to json
'# | complete)
    assert equal $legacy.exit_code 0
    assert equal ($legacy.stdout | from json) [string]
    assert ($legacy.stderr | str contains 'nu::shell::deprecated')
}

def test-yaml-and-types [] {
    assert equal ({a: {|| $in}} | to yaml --non-roundtrip null | str trim) 'a: null'
    assert error { {a: {|| $in}} | to yaml --non-roundtrip 'lossy' }
    for style in [compact indented] {
        assert equal ({a: [1 2]} | to yaml --list-indent $style | from yaml) {a: [1 2]}
    }
    assert equal ('a.infra' | from yaml) 'a.infra'
    let text = ('1.2.3' | into semver | into string)
    assert equal ($text | describe) string
    let newer = (('1.2.3' | into semver) > '1.0.0')
    assert $newer
    assert (('1.2.3' | into semver) > '1.0.0')
}

def test-data [] {
    assert equal ({} | default 5 a.b) {a: {b: 5}}
    assert equal ({} | default 5 'a.b') {'a.b': 5}
    assert equal ({nested: {x: 1}, x: 2} | flatten) [{nested_x: 1, x: 2}]
    # Lock the remaining 0.116.0 generated-name collision so the warning is
    # revisited if upstream fixes it; neither field order preserves all values.
    assert equal (
        {nested: {x: 1}, nested_x: 3, x: 2} | flatten
    ) [{nested_x: 3, x: 2}]
    assert equal (
        {nested_x: 3, x: 2, nested: {x: 1}} | flatten
    ) [{nested_x: 1, x: 2}]
    assert equal ({a: [1 {b: 2}]} | update cells --recursive { $in * 2 }) {a: [2 {b: 4}]}
    assert equal ("a\n\nb\n" | lines --skip-empty) [a b]
    assert equal ([1 2 3 4] | take until --include 1 $it == 3) [1 2 3]
    assert error { [[name size]; [a 100b]] | where size <= 150 | length }
    assert error { [[name size]; [a 100b]] | where size <= 150 | columns }
    assert error { [[name size]; [a 100b]] | where size <= 150 | is-empty }
    assert error { [1 2] | each while { error make {msg: 'stream error'} } | collect }
    let parallel = (run-nu-bounded '0..99 | par-each --threads 1 { $in } | par-each --threads 1 { $in } | length')
    assert equal $parallel.exit_code 0
    assert equal ($parallel.stdout | str trim) '100'
    # Exercise cancellation as well as the fast successful path.
    let timeout_error = try {
        run-nu-bounded 'sleep 1min' --timeout 100ms
        null
    } catch {|err| $err.msg }
    assert equal $timeout_error 'Nu test process timed out after 100ms'
}

def test-cleanup [] {
    let result = (^$nu.current-exe --no-config-file -c r#'
try {
    try { error make {msg: inner} } finally { print inner }
} catch { print outer }
for n in [1 2] { try { break } finally { print break-cleanup } }
'# | complete)
    assert equal $result.exit_code 0
    assert equal ($result.stdout | lines) [inner outer break-cleanup]
}

def test-files-and-parser [] {
    let root = (mktemp --directory)
    try {
        let file = ($root | path join nested data.txt)
        'saved' | save --force $file
        assert equal (open --raw $file) saved
        assert error { mkdir --fail-if-exists $root }
        assert equal (mkdir --verbose $root | first | get created) false
        let missing = (^$nu.current-exe --no-config-file --ide-check 100 ($root | path join missing.nu) | complete)
        assert ($missing.exit_code != 0)
        assert ($missing.stderr | is-not-empty)
        for program in ['[1; 2]' '[[a b];]' '{a: [1]} | to yaml --compact-list-indent'] {
            let rejected = (^$nu.current-exe --no-config-file -c $program | complete)
            assert ($rejected.exit_code != 0)
        }
    } finally { rm --recursive --force $root }
    assert (not ($root | path exists))
}

def test-tui [] {
    let result = ([{name: a} {name: b}] | tui table --id items | tui debug --size [40 10] --keys [down enter])
    assert equal $result.selected.name b
    assert equal $result.action submit
    assert ($result.screen | is-not-empty)
}

def main [] {
    test-flags
    test-completion
    test-yaml-and-types
    test-data
    test-cleanup
    test-files-and-parser
    test-tui
    print 'PASS: Nu 0.116 migration smoke tests'
}
