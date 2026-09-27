use std/assert

def flags [--count: int = 5, --nullable: oneof<int, nothing> = 7, --verbose] {
    {count: $count, nullable: $nullable, verbose: $verbose}
}

def complete-choice [token: record] {
    {completions: [alpha beta], options: {filter: true}, fallback: false}
}
def choose [value: string@complete-choice] { $value }

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
    let external = (^nu --no-config-file -c r#'
$env.config.completions.external.completer = {|place| [($place.command | str join ":")] }
alias gco = git checkout
"gco ma" | commandline complete --detailed | get value | to json
'# | complete)
    assert equal $external.exit_code 0
    assert equal ($external.stdout | from json) ['git:checkout:ma']
    # Release notes overstate the rejection of unknown positional names:
    # the first two positions still use the deprecated compatibility bridge.
    let legacy = (^nu --no-config-file -c r#'
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
    assert equal ({a: [1 {b: 2}]} | update cells --recursive { $in * 2 }) {a: [2 {b: 4}]}
    assert equal ("a\n\nb\n" | lines --skip-empty) [a b]
    assert equal ([1 2 3 4] | take until --include 1 $it == 3) [1 2 3]
    assert error { [[name size]; [a 100b]] | where size <= 150 | length }
    assert error { [[name size]; [a 100b]] | where size <= 150 | columns }
    assert error { [[name size]; [a 100b]] | where size <= 150 | is-empty }
    assert error { [1 2] | each while { error make {msg: 'stream error'} } | collect }
    assert equal (0..99 | par-each --threads 1 { $in } | par-each --threads 1 { $in } | length) 100
}

def test-cleanup [] {
    let result = (^nu --no-config-file -c r#'
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
        let missing = (^nu --no-config-file --ide-check 100 ($root | path join missing.nu) | complete)
        assert ($missing.exit_code != 0)
        assert ($missing.stderr | is-not-empty)
        for program in ['[1; 2]' '[[a b];]' '{a: [1]} | to yaml --compact-list-indent'] {
            let rejected = (^nu --no-config-file -c $program | complete)
            assert ($rejected.exit_code != 0)
        }
    } finally { rm --recursive --force $root }
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
