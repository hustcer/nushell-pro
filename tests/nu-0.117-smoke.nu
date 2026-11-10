use std/assert
use support/nu-process.nu run-nu-bounded

type Point = record<x: float, y: float>
type Polygon = list<Point>
def first-x [poly: Polygon]: nothing -> float { $poly.0.x }
def literal-kind [value: oneof<string, int> = 5] { $value | describe }
def list-kind [value: oneof<string, list<string>>] { $value | describe }

module geometry {
    export type Count = int
}
use geometry Count
def count-plus-one [value: Count]: nothing -> int { $value + 1 }

def assert-error-code [action: closure, expected: string] {
    let code = try { do $action | collect | ignore; null } catch {|e| $e.details.code }
    assert equal $code $expected
}

def test-types-and-parser [] {
    assert equal (first-x [{x: 1.0, y: 2.0}]) 1.0
    assert equal (count-plus-one 4) 5
    assert equal (literal-kind 007) int
    assert equal (literal-kind '007') string
    assert equal (literal-kind) int
    assert equal (list-kind [foo bar]) 'list<string>'
    let version: semver = ('1.2.3' | into semver)
    assert equal ($version | into string) '1.2.3'
    const ends = [([1 2 3] | first) ([1 2 3] | last)]
    assert equal $ends [1 3]
    assert (not 1 == 2)
    let n = 3
    assert equal (-$n) (-3)
    assert equal (-(2 + 3)) (-5)
    assert equal (9223372036854775807b | into int) 9223372036854775807
    assert equal ([INF] | first | describe) string
    assert equal (nan | describe) float
    assert equal (match [1 2 3 4] { [1 ..$middle 4] => $middle, _ => [] }) [2 3]
    assert equal (match [1 2 9] { [1 .. 4] => true, _ => false }) false
    assert equal ([{a: true, b: true} {a: true, b: false}] | where a and b) [{a: true, b: true}]

    for program in [
        'def type [] {}'
        '9223372036854775808'
        '9223372036854775808b'
        '2023-02-29'
        '{a: 1, a: 2}'
        'def bad [--one(-x), --two(-x)] {}'
        'alias bad = echo hi | str length'
        '[1] | get --ignore-errors a'
        '[1] | filter { true }'
    ] {
        let rejected = (^$nu.current-exe --no-config-file -c $program | complete)
        assert ($rejected.exit_code != 0)
    }
    # The notes' breaking-change bullet is superseded by the later const fix.
    let unlet_result = (^$nu.current-exe --no-config-file -c 'const n = 1; unlet $n; print ok' | complete)
    assert equal $unlet_result.exit_code 0
    assert equal ($unlet_result.stdout | str trim) ok
    let hidden_const = (^$nu.current-exe --no-config-file -c 'const n = 1; unlet $n; $n' | complete)
    assert ($hidden_const.exit_code != 0)
}

def test-get-and-grouping [] {
    assert equal ({a: 1, b: 2} | get) {a: 1, b: 2}
    assert equal ({a: 1} | get ...[a]) [1]
    assert equal ({a: 1} | get ...[]) []
    assert equal ({a: {b: 1}, 'a.b': 2} | get ...['a.b' $.a.b]) [2 1]
    assert error { get }
    let groups = ([true 'true' 1 '1' null] | group-by --to-table)
    assert equal ($groups | get group | each { describe }) [bool string int string nothing]
    assert equal ($groups | get items | each { length }) [1 1 1 1 1]
    assert equal ([true 'true'] | group-by | get true | length) 2
    let sizes = ([1000000b 1001000b] | group-by --to-table)
    assert equal ($sizes | get group | each { describe }) [filesize filesize]
    assert equal ($sizes | get group | each { into int }) [1000000 1001000]
}

def test-record-commands [] {
    assert equal ({a: 1, b: 2} | record where value > 1) {b: 2}
    assert equal ({a: 1, b: 2} | record where {|key, value| $key == a and $value == 1 }) {a: 1}
    assert equal ({a: '', b: 2} | record where --values { is-not-empty }) {b: 2}
    assert equal ({a: 1, b: 2} | record each {|key, value| [($key | str uppercase) ($value * 2)] }) {A: 2, B: 4}
    # record each deliberately replaces duplicate generated keys, unlike flatten.
    assert equal ({a: 1, b: 2} | record each {|key, value| {same: $value} }) {same: 2}
    assert equal ({a: 1, b: {c: [2 3]}} | record walk {|value| $value * 2 }) {a: 2, b: {c: [4 6]}}
    assert equal ({a: [2 1]} | record walk --no-lists { sort }) {a: [1 2]}
    assert equal ({a: {value: 2}} | record walk --containers {|value|
        if ($value | describe) starts-with record { $value.value } else { $value }
    }) {a: 2}
    assert equal ({age: '42', email: 'A@B.COM'} | record apply {age: {into int}, email: {str lowercase}}) {age: 42, email: 'a@b.com'}
    assert equal ([{age: '1'} {age: '2'}] | record apply {age: {into int}}) [{age: 1} {age: 2}]
    assert equal ({a: 1} | record apply {missing: {into int}}) {a: 1}
    assert error { {a: 1} | record apply --strict {missing: {into int}} }
    assert error { [{a: nope}] | record apply {a: {into int}} | collect }
}

def test-default-and-data-errors [] {
    assert equal (1 | default { error make {msg: unused} }) 1
    assert equal (null | default { 42 }) 42
    assert error { 1 | default (error make {msg: eager}) }
    let fallback = { 42 }
    assert equal (null | default $fallback | describe) closure
    for data in [
        {nested: {x: 1}, nested_x: 3, x: 2}
        {nested_x: 3, x: 2, nested: {x: 1}}
    ] {
        assert-error-code { $data | flatten } 'nu::shell::column_defined_twice'
    }
    let cell_error = try { [[a]; [1]] | update cells { error make {msg: cell-error} } | collect } catch {|e| $e }
    assert equal $cell_error.msg cell-error
    assert equal ([[a b]; [1 10] [2 20]] | update cells { $in * 2 } a) [[a b]; [2 10] [4 20]]
    let legacy_columns = (^$nu.current-exe --no-config-file -c '[[a b]; [1 10]] | update cells -c [a] { $in * 2 } | to json' | complete)
    assert equal $legacy_columns.exit_code 0
    assert equal ($legacy_columns.stdout | from json) [[a b]; [2 10]]
    assert ($legacy_columns.stderr | str contains 'nu::parser::deprecated')
    let each_error = try { [1] | each { error make {msg: closure-error} } | collect } catch {|e| $e }
    assert equal $each_error.msg closure-error
    # error make without an explicit code keeps null in structured details;
    # the rendered fallback code is presentation, not the stored code.
    assert equal $each_error.details.code null
    assert error { [[id]; [1]] | join [[other]; [1]] id | collect }
    assert equal ([[id]; [1] [2]] | join --anti [[id]; [2]] id) [[id]; [1]]
    assert equal ([[a b]; [1 10] [2 20]] | math sum a) {a: 3}
    assert error { [[a]; [[1 2]] [[3 4]]] | math sum a }
    assert equal ([[a]; [[1 2]] [[3 4]]] | update a { math sum }) [[a]; [3] [7]]
}

def test-dynamic-calls [] {
    let sorter = 'sort'
    assert equal ([1 3 2] | %$sorter --reverse) [3 2 1]
    assert equal ([1 3 2] | %$sorter ...{reverse: true}) [3 2 1]
    assert error { [1 2] | %$sorter --unknown }
    let echoer = 'echo'
    assert equal (%$echoer '--foo') '--foo'
    assert equal (%$echoer -- --foo) '--foo'
    assert error { %$echoer --foo }
}

def test-dotenv-and-env [] {
    let parsed = (r#'APP=demo
NEXT=${APP}/data
LITERAL='${APP}'
COMMAND=$(echo not-executed)
'# | from dotenv)
    assert equal $parsed {APP: demo, NEXT: 'demo/data', LITERAL: '${APP}', COMMAND: '$(echo not-executed)'}
    let record = {NAME: 'my app', TEXT: "line1\nline2", LITERAL: '$APP'}
    assert equal ($record | to dotenv | from dotenv) $record
    with-env {PATH: ($env.PATH | str join (char esep))} {
        assert equal ($env.PATH | describe) 'list<string>'
    }
    with-env --no-convert {NU_PRO_CONVERT: raw} { assert equal $env.NU_PRO_CONVERT raw }
    with-env {ENV_CONVERSIONS: {NU_PRO_NUMBER: {from_string: {|s| $s | into int}}}} {
        load-env {NU_PRO_NUMBER: '42'}
        assert equal $env.NU_PRO_NUMBER 42
        load-env --no-convert {NU_PRO_NUMBER: '007'}
        assert equal $env.NU_PRO_NUMBER '007'
    }
    assert error { load-env {Pwd: /} }
    assert error { with-env {Pwd: /} { $env.PWD } }
}

def test-config-and-ps [] {
    let defaults = (config default)
    assert ($defaults.keybindings | is-not-empty)
    assert ($defaults.menus | is-not-empty)
    with-env {config: $defaults} {
        $env.config.keybindings = []
        $env.config.menus = []
        assert equal $env.config.keybindings []
        assert equal $env.config.menus []
        $env.config.keybindings = $defaults.keybindings
        $env.config.menus = $defaults.menus
        let original = $env.config.keybindings
        assert error { $env.config.keybindings = [{name: bad, modifier: impossible, keycode: char_a, mode: emacs, event: null}] }
        assert equal $env.config.keybindings $original
        assert error { $env.config.menus = [{name: bad, type: {}}] }
        assert equal $env.config.menus $defaults.menus
    }
    assert equal (ps | columns) [pid ppid name user status cpu cpu_time mem]
    let processes = (ps --long)
    for column in [virtual private command exe start_time user_id process_group_id session_id priority nice threads read written cwd environment] {
        assert ($column in ($processes | columns))
    }
    assert equal ($processes | where pid == $nu.pid | first | get cwd) $env.PWD
    if $nu.os-info.name == macos { assert ($processes | where pid == 0 | is-not-empty) }
}

def test-completion-and-externs [root: path] {
    let generated = ('  -s, --short   show status concisely' | generate completions 'nu-pro-tool' --source help)
    let module_path = ($root | path join tool-completions.nu)
    $generated | save $module_path
    assert (nu-check --debug --as-module $module_path)
    # Import is parse-time, so invoke from the owned directory with fixed source.
    let result = (do { cd $root; ^$nu.current-exe --no-config-file -c 'use tool-completions.nu *; "nu-pro-tool --sh" | commandline complete --detailed | get value | to json' } | complete)
    assert equal $result.exit_code 0
    assert equal ($result.stdout | from json) [--short]
    let strict_result = (^$nu.current-exe --no-config-file -c 'extern --strict nu-pro-missing [--known]; nu-pro-missing --knwon' | complete)
    assert ($strict_result.exit_code != 0)
    assert ($strict_result.stderr | str contains 'nu::parser::unknown_flag')
    # git is already needed for release maintenance; use its read-only version call.
    let structured = (^$nu.current-exe --no-config-file -c r#'
@structured [--version] { parse --regex '^git version (?<version>\S+)' }
extern git []
let decoded = git
let raw = (git --version | complete)
{decoded: $decoded, raw: $raw} | to json
'# | complete)
    assert equal $structured.exit_code 0
    let values = ($structured.stdout | from json)
    assert equal ($values.decoded | length) 1
    assert ($values.decoded.0.version | is-not-empty)
    assert equal $values.raw.exit_code 0
    assert ($values.raw.stdout | str starts-with 'git version ')
}

def test-files-and-run [root: path] {
    let env_path = ($root | path join .env.local)
    {APP: demo} | save $env_path
    assert equal (open $env_path) {APP: demo}
    let json_path = ($root | path join data.JSON)
    {a: 1} | save $json_path
    assert equal (open --raw $json_path | from json) {a: 1}
    let converter = (^$nu.current-exe --no-config-file -c r#'
def 'to owned' []: int -> string { into string }
def main [target: path] { {a: 1} | save $target }
'# -- ($root | path join wrong.owned) | complete)
    assert ($converter.exit_code != 0)
    assert ($converter.stderr | str contains 'nu::shell::only_supports_this_input_type')
    assert (not ($root | path join wrong.owned | path exists))
    let script = ($root | path join stage.nu)
    'def leaked [] { 1 }; def main [--name: string] { $name }' | save $script
    let run_result = (do { cd $root; ^$nu.current-exe --no-config-file -c r#'
let output = run stage.nu ...{name: "23"}
{output: $output, leaked: (scope commands | any name == leaked)} | to json
'# } | complete)
    assert equal $run_result.exit_code 0
    assert equal ($run_result.stdout | from json) {output: '23', leaked: false}
    let run_bad = (do { cd $root; ^$nu.current-exe --no-config-file -c 'run stage.nu --name 23' } | complete)
    assert ($run_bad.exit_code != 0)
    let spread_flags = (do { cd $root; ^$nu.current-exe --no-config-file -c 'run stage.nu ...[--name foo]' } | complete)
    assert ($spread_flags.exit_code != 0)
}

def test-external-streams [root: path] {
    let big = (run-nu-bounded r#'try { ^$nu.current-exe --no-config-file -c 'print --no-newline ("x" | fill --width 300002 --character x)' } | str length'#)
    assert equal $big.exit_code 0
    assert equal ($big.stdout | str trim) '300002'
    let final = (run-nu-bounded r#'use std/assert
try {
    ^$nu.current-exe --no-config-file -c 'print out; print --stderr err'
} finally {|value| assert equal ($value | str trim) out } | complete | to json'#)
    assert equal $final.exit_code 0
    assert equal $final.stderr ''
    assert equal ($final.stdout | from json) {stdout: "out\n", stderr: "err\n", exit_code: 0}
    # With pipefail enabled, finally-only propagates failure before an outer
    # complete can run, and the finalizer receives the error record.
    let finalizer_file = ($root | path join finalizer.json)
    let failed_finally = (run-nu-bounded r#'def main [target: path] {
    try {
        ^$nu.current-exe --no-config-file -c 'print out; print --stderr err; exit 3'
    } finally {|value|
        {is_record: (($value | describe) starts-with record), exit_code: $value.exit_code}
        | to json | save $target
    } | complete | to json
}'# --args [$finalizer_file])
    assert equal $failed_finally {stdout: '', stderr: "err\n", exit_code: 3}
    assert equal (open $finalizer_file) {is_record: true, exit_code: 3}
    # Collect the structured result before crossing the try/finally boundary.
    let captured_failure = (run-nu-bounded r#'use std/assert
try {
    ^$nu.current-exe --no-config-file -c 'print out; print --stderr err; exit 3' | complete
} finally {|value| assert equal $value.exit_code 3 } | to json'#)
    assert equal $captured_failure.exit_code 0
    assert equal $captured_failure.stderr ''
    assert equal ($captured_failure.stdout | from json) {stdout: "out\n", stderr: "err\n", exit_code: 3}
    let failed = (run-nu-bounded r#'try { ^$nu.current-exe --no-config-file -c 'exit 3' } | complete | to json'#)
    assert equal $failed.exit_code 0
    assert equal ($failed.stdout | from json | get exit_code) 3
    let redirected = (run-nu-bounded r#'def main [target: path] {
    ^$nu.current-exe --no-config-file -c 'print out; print --stderr err; exit 3' o> $target | complete | to json
}'# --args [($root | path join out.txt)])
    assert equal $redirected.exit_code 0
    assert equal ($redirected.stdout | from json) {stderr: "err\n", exit_code: 3}
    assert equal (open --raw ($root | path join out.txt)) "out\n"

    let side_effect = ($root | path join side-effect.txt)
    let streamed_failure = (run-nu-bounded r#'def main [target: path] {
    try {
        ^$nu.current-exe --no-config-file -c 'print row; exit 4'
        | lines | each {|line| $line | save --append $target; $line }
    } catch { 'caught' } | to json
}'# --args [$side_effect])
    assert equal $streamed_failure.exit_code 0
    assert equal $streamed_failure.stderr ''
    assert equal ($streamed_failure.stdout | from json) caught
    assert equal (open --raw $side_effect) row

    let guarded_effect = ($root | path join guarded-effect.txt)
    let collected_failure = (run-nu-bounded r#'def main [target: path] {
    try {
        ^$nu.current-exe --no-config-file -c 'print row; exit 4'
        | collect | lines | each {|line| $line | save --append $target; $line }
    } catch { 'caught' } | to json
}'# --args [$guarded_effect])
    assert equal $collected_failure.exit_code 0
    assert equal $collected_failure.stderr ''
    assert equal ($collected_failure.stdout | from json) caught
    assert (not ($guarded_effect | path exists))
    let timeout = try { run-nu-bounded 'sleep 1min' --timeout 100ms; null } catch {|e| $e.msg }
    assert equal $timeout 'Nu test process timed out after 100ms'
}

def test-dates-and-security [] {
    assert (2024-01-01 older-than 2025-01-01)
    assert (((date now) - 10day) older-than 1wk)
    assert not (2024-01-01 older-than 2024-01-01)
    assert equal (null newer-than 2024-01-01) null
    assert error { '2025-02-30' | into datetime }
    assert equal ('1hr 3min' | detect type) 63min
    assert equal (' 5ns' | detect type) ' 5ns'
    # --walk-up is useful for display but cannot establish containment.
    assert error { '/a/b' | path relative-to /safe }
    assert equal ('/a/b' | path relative-to /safe --walk-up) '../a/b'
    assert equal ($"(char --unicode feff){\"a\":1}" | from json) {a: 1}
    assert equal (0x[01 02] | bytes remove --end 0x[ff]) 0x[01 02]
}

def main [] {
    assert ((version | get version | into semver) in ('>=0.117.0' | into semver-range))
    let root = (mktemp --directory)
    try {
        test-types-and-parser
        test-get-and-grouping
        test-record-commands
        test-default-and-data-errors
        test-dynamic-calls
        test-dotenv-and-env
        test-config-and-ps
        test-completion-and-externs $root
        test-files-and-run $root
        test-external-streams $root
        test-dates-and-security
    } finally { rm --recursive --force $root }
    assert (not ($root | path exists))
    print 'PASS: Nu 0.117 migration smoke tests (11 groups)'
}
