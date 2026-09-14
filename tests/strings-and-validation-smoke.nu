use std/assert

def run-nu [args: list<string>]: nothing -> record {
    ^nu --no-config-file ...$args | complete
}

def doc-example [file: path, heading: string]: nothing -> string {
    open --raw $file
    | split row $heading
    | get 1
    | split row '```nu'
    | get 1
    | split row '```'
    | first
    | str trim
}

def test-check-contract [fixture_root: path]: nothing -> nothing {
    let checker = ($fixture_root | path join checker.nu)
    r#'def main [script: path, --debug] {
    if $debug { nu-check --debug $script } else { nu-check $script }
}'# | save $checker

    for case in [
        {name: syntax, code: 'let value = ('}
        {name: type, code: 'let value: int = "text"'}
    ] {
        let script = ($fixture_root | path join $'($case.name).nu')
        $case.code | save $script
        let plain = (run-nu [$checker $script])
        assert equal $plain.exit_code 0
        assert equal ($plain.stdout | str trim) 'false'
        let debugged = (run-nu [$checker $script '--debug'])
        assert not equal $debugged.exit_code 0
        assert ($debugged.stderr | is-not-empty)
    }

    let missing = (run-nu [$checker ($fixture_root | path join missing.nu)])
    assert not equal $missing.exit_code 0
    assert ('export def answer [] { 42 }' | nu-check --as-module)
    assert not ('print "script body"' | nu-check --as-module)
}

def test-check-does-not-execute [fixture_root: path]: nothing -> nothing {
    let script = ($fixture_root | path join side-effect.nu)
    let marker = ($fixture_root | path join marker.txt)
    '"executed" | save $env.NUSHELL_PRO_VALIDATION_MARKER' | save $script
    with-env {NUSHELL_PRO_VALIDATION_MARKER: $marker} {
        assert (nu-check --debug $script)
        let ide = (run-nu ['--ide-check' '100' $script])
        assert equal $ide.exit_code 0
        let errors = ($ide.stdout | lines | where {|line| $line | str trim | is-not-empty }
            | each { from json } | where {|item| $item.type? == diagnostic and $item.severity? == Error })
        assert ($errors | is-empty)
        assert not ($marker | path exists)

        # A trusted, constant source command intentionally demonstrates execution.
        let sourced = (do {
            cd $fixture_root
            run-nu ['-c' 'source side-effect.nu']
        })
        assert equal $sourced.exit_code 0
        assert equal (open --raw $marker) 'executed'
    }
    assert ('error make {msg: "runtime-only failure"}' | nu-check)
    let runtime = (run-nu ['-c' 'error make {msg: "runtime-only failure"}'])
    assert not equal $runtime.exit_code 0
}

def test-relative-imports [fixture_root: path]: nothing -> nothing {
    let subdir = ($fixture_root | path join imports)
    mkdir $subdir
    'export def answer [] { 42 }' | save ($subdir | path join nu_check_fixture_helper.nu)
    let script = ($subdir | path join entry.nu)
    'use ./nu_check_fixture_helper.nu answer; answer' | save $script
    with-env {NU_LIB_DIRS: []} {
        assert (nu-check --debug $script)
        # Piped contents are anonymous; supplying the path does not restore scope.
        assert not (open --raw $script | nu-check $script)
    }
}

def test-string-meaning []: nothing -> nothing {
    let silent = r#'$'(1 + 1) items''#
    assert ($silent | nu-check)
    let wrong = (run-nu ['-c' $silent])
    assert equal $wrong.exit_code 0
    assert equal ($wrong.stdout | str trim) '2 items'
    let backslash = (run-nu ['-c' r#'$'\(1 + 1) items''#])
    assert equal $backslash.exit_code 0
    assert equal ($backslash.stdout | str trim) '\2 items'

    let count = 3
    let label = (['Done ' ($count | into string) ' file(s)'] | str join)
    assert equal $label 'Done 3 file(s)'
    assert equal $"Done ($count) file\(s)" $label
    let data = r#'literal (1 + 1) and \ backslash'#
    assert equal $'Value: ($data)' 'Value: literal (1 + 1) and \ backslash'
}

def test-javascript-data-boundary []: nothing -> nothing {
    let values = [
        'deck (draft).pptx'
        r#'quote" apostrophe' backslash\ backtick`'#
        r#'"); globalThis.injected = true; //'#
        r#'$(echo should-stay-data); (1 + 1)'#
        "line1\nline2"
        '中文'
        ''
        '0001'
        8
        false
    ]
    let payload = ($values | to json --raw)
    let expression = (['window.renderProbe(...' $payload ')'] | str join)
    # The executable template is fixed; only serialized JSON data varies.
    let consumer = r#'globalThis.injected = false;
globalThis.window = { renderProbe: (...args) => args };
const values = (0, eval)(process.argv[1]);
process.stdout.write(JSON.stringify({ values, injected: globalThis.injected }));'#
    let result = (^node --input-type=module -e $consumer $expression | complete)
    assert equal $result.exit_code 0
    assert equal $result.stderr ''
    let decoded = ($result.stdout | from json)
    assert equal $decoded.values $values
    assert equal $decoded.injected false
}

def test-documented-runner [fixture_root: path, docs_root: path]: nothing -> nothing {
    let example = (doc-example ($docs_root | path join references modules-and-scripts.md) '### Basic test framework (without Nupm)')
    let good = ($fixture_root | path join documented-runner.nu)
    $example | save $good
    assert (nu-check --debug $good)
    let passed = (run-nu [$good])
    assert equal $passed.exit_code 0
    assert str contains $passed.stdout 'Tests passed: 2'

    let failed = ($fixture_root | path join failing-runner.nu)
    assert str contains $example 'assert equal (increment 1) 2'
    $example | str replace 'assert equal (increment 1) 2' 'assert equal (increment 1) 99' | save $failed
    let rejected = (run-nu [$failed])
    assert not equal $rejected.exit_code 0
    assert not ($rejected.stdout | str contains 'Tests passed:')

    let empty = ($fixture_root | path join empty-runner.nu)
    assert str contains $example 'run-tests $cases'
    $example | str replace 'run-tests $cases' 'run-tests []' | save $empty
    let zero = (run-nu [$empty])
    assert not equal $zero.exit_code 0
    assert not ($zero.stdout | str contains 'Tests passed:')
}

# Requires Node for the real JavaScript data-boundary check.
def main [--docs-root: path]: nothing -> nothing {
    let docs_root = ($docs_root | default ($env.CURRENT_FILE | path dirname | path dirname))
    let fixture_root = (mktemp --directory)
    # Preserve an explicit outcome across cleanup; success text must never
    # follow a deferred error from a try/finally pipeline.
    let outcome = (try {
        test-check-contract $fixture_root
        test-check-does-not-execute $fixture_root
        test-relative-imports $fixture_root
        test-string-meaning
        test-javascript-data-boundary
        test-documented-runner $fixture_root $docs_root
        {passed: true, message: ''}
    } catch {|err|
        {passed: false, message: $err.msg}
    } finally {
        rm -r -f $fixture_root
    })
    assert not ($fixture_root | path exists)
    if not $outcome.passed {
        error make {msg: $outcome.message}
    }
    print 'strings-and-validation-smoke: 6 groups passed'
}
