use std/assert

# Run a nested Nushell with a clean environment and decode its JSON stdout.
# Any non-zero exit or stderr output is a harness failure, not an assertion
# failure, so it is raised here instead of inside a test.
def run-nu-json [args: list<string>] {
    let result = (^nu --no-config-file ...$args | complete)

    if $result.exit_code != 0 or ($result.stderr | str trim | is-not-empty) {
        error make {
            msg: $'nested nu failed with exit code ($result.exit_code): ($result.stderr | str trim)'
        }
    }

    $result.stdout | from json
}

# Run a nested Nushell program and return its trimmed stdout lines, including
# the runs that are expected to fail.
def run-nu-lines [program: string] {
    ^nu --no-config-file -c $program
    | complete
    | get stdout
    | lines
    | each {|line| $line | str trim }
    | where {|line| $line | is-not-empty }
}

def test-yaml-spec-selection [] {
    assert equal ('yes' | from yaml) 'yes'
    assert equal ('yes' | from yaml --spec 1.1) true
    assert equal ('0247' | from yaml) 247
    assert equal ('0247' | from yaml --spec 1.1) 0o247

    # YAML 1.1 read colon-bearing scalars as base-60; 1.2 keeps them as strings.
    assert equal ('190:20:30' | from yaml) '190:20:30'
    assert equal ('190:20:30' | from yaml --spec 1.1) 685230
}

def test-yaml-reader-strictness [] {
    assert error { 'true: enabled' | from yaml }

    let verbatim = ('true: enabled' | from yaml --key-resolution verbatim)
    assert equal ($verbatim | columns) ['true']
    assert equal ($verbatim | values) ['enabled']

    assert error { 'Key: !Sub ${AWS::StackName}' | from yaml }
    assert equal (
        'Key: !Sub ${AWS::StackName}'
        | from yaml --ignore-tags
        | get Key
    ) '${AWS::StackName}'

    assert equal ('name: dev' | from yaml --multiple auto | describe) 'record<name: string>'
    assert equal ('name: dev' | from yaml --multiple list) [{name: dev}]
    assert error { "name: dev\n---\nname: prod" | from yaml --multiple single }
}

def test-yaml-writer-non-roundtrip [] {
    assert error { {|| $in} | to yaml }

    # The opt-out value is a string. A bare `null` is the `nothing` literal and
    # fails to parse, so the quoted form is the only working spelling.
    assert equal ({a: {|| $in}} | to yaml --non-roundtrip 'null' | str trim) 'a: null'
    assert equal ({a: {|| $in}} | to yaml --serialize | str trim) 'a: !closure "{|| $in}"'

    # Locks a 0.115.0 defect: `to yaml` rejects 'lossy' even though its own
    # error message lists it. When a patched Nu accepts it, this assertion
    # fails and references/nu-0.115-migration.md must be retracted.
    assert error { {a: {|| $in}} | to yaml --non-roundtrip 'lossy' }
    # `to kdl` is unaffected by the same defect.
    assert (({a: {|| $in}} | to kdl --non-roundtrip 'lossy') | is-not-empty)
}

def test-row-condition-predicates [] {
    assert ([9 8 7 6] | enumerate | any item == index * 2)
    assert ([1sec 1min 1hr] | all ($it | describe) == duration)
    # Guard against a vacuously true row condition.
    assert not ([1sec 'x' 1hr] | all ($it | describe) == duration)
}

def test-binary-filesize-slicing [] {
    assert equal (
        0x[01 02 03 04]
        | chunks 2b
        | each { encode hex }
    ) ['0102' '0304']

    assert equal (0x[01 02 03 04] | first 2b | encode hex) '0102'
    assert equal (0x[01 02 03 04] | skip 2b | encode hex) '0304'
    # `drop` accepts binary input from 0.115.
    assert equal (0x[01 02 03 04] | drop 2b | encode hex) '0102'
}

def test-semver-comparison [] {
    # Keep each comparison in an unconstrained list and extract it immediately.
    # In 0.115.0 a `bool` parameter infers `semver`, and `let` fails the other
    # way round. See references/nu-0.115-migration.md.
    assert equal ([
        (('2.0.1' | into semver) > '1.9.9')
    ] | first) true
    assert equal ([
        (('1.0.0-alpha' | into semver) < '1.0.0')
    ] | first) true

    let loose_versions = (['v1.2.3' 'v2.0.0'] | into semver --loose)
    assert equal ($loose_versions | each { describe }) [semver semver]
    # `--loose` accepts the prefix but does not normalize it away.
    assert equal (
        $loose_versions | each { into string }
    ) ['v1.2.3' 'v2.0.0']
}

def test-take-include-boundary [] {
    assert equal (
        [1 2 3 4] | take until --include 0 {|value| $value == 3 }
    ) [1 2]
    assert equal (
        [1 2 3 4] | take until --include 1 {|value| $value == 3 }
    ) [1 2 3]
    assert equal (
        [1 2 3 4] | take while --include 1 {|value| $value < 3 }
    ) [1 2 3]
    # Counts above one keep consuming past the original stopping point.
    assert equal (
        [1 2 3 4] | take until --include 2 {|value| $value == 3 }
    ) [1 2 3 4]
}

def test-group-by-null-keys [] {
    let groups = ([a '' null] | group-by --to-table)
    assert equal ($groups | length) 3
    assert equal $groups.0.group a
    assert equal $groups.1.group ''
    assert equal $groups.2.group null

    # Record output cannot hold a null key, so that group disappears.
    let record_groups = ([a '' null] | group-by)
    assert equal ($record_groups | columns) [a '']

    # A required cell path keeps the null group; an optional one skips it.
    assert equal ([{x: a} {x: null}] | group-by x --to-table | length) 2
    assert equal ([{x: a} {x: null}] | group-by x? --to-table | length) 1
}

def test-path-type-and-error-labels [] {
    assert equal ('' | path type) null
    # A label without `span` is rejected; the spanned shape is required.
    assert error { error make {msg: 'bad label', label: {text: 'missing span'}} }
    assert error {
        error make {msg: 'bad label', label: {text: 't', start: 0, end: 1}}
    }
}

def test-deprecation-metadata [] {
    # `deprecation_info` is a table, so a single command's entry is `.0`.
    let deprecated = (
        scope commands
        | where name == 'str downcase'
        | first
        | get deprecation_info.0
    )
    assert equal ($deprecated.since | describe) string
    assert ($deprecated.help | is-not-empty)
}

def test-nested-finally-cleanup [] {
    # Locks a 0.115.0 defect: a `try/finally` nested directly inside an outer
    # `try` whose handler is `catch` silently skips the inner `finally`.
    # Fixed in 0.116; retain the historical expectation for older targets.
    let expected = if (version | get version | into semver) in ('>=0.116.0' | into semver-range) {
        ['INNER' 'OUTER']
    } else {
        ['OUTER']
    }
    assert equal (run-nu-lines r#'try {
    try { error make {msg: "inner"} } finally { print "INNER" }
} catch { print "OUTER" }'#) $expected

    # A `do` boundary restores the cleanup.
    assert equal (run-nu-lines r#'try {
    do { try { error make {msg: "inner"} } finally { print "INNER" } }
} catch { print "OUTER" }'#) ['INNER' 'OUTER']

    # So does giving the outer block a `finally` instead of a `catch`.
    assert equal (run-nu-lines r#'try {
    try { error make {msg: "inner"} } finally { print "INNER" }
} finally { print "OUTER" }'#) ['INNER' 'OUTER']
}

def test-external-arg-tokens [] {
    let fixture_root = (mktemp --directory)

    try {
        let script = ($fixture_root | path join 'external-arg.nu')
        r#'def main [
    first: external_arg
    second: external_arg
    ...rest: external_arg
] {
    {
        first: ($first | into string)
        first_type: ($first | describe)
        second: ($second | into string)
        second_type: ($second | describe)
        rest: ($rest | each { into string })
        rest_type: ($rest | describe)
    } | to json --raw
}
'# | save --force $script

        let parsed = (run-nu-json [$script '0001' 'true' '--' '001'])
        assert equal $parsed.first '0001'
        assert equal $parsed.first_type glob
        assert equal $parsed.second 'true'
        assert equal $parsed.second_type glob
        assert equal $parsed.rest ['001']
        assert equal $parsed.rest_type 'list<glob>'

        # `nu -c` accepts arguments after `--` from 0.115, so the program text
        # stays constant and the value travels separately.
        let command_result = (run-nu-json ['-c' r#'def main [value: external_arg] {
    {value: ($value | into string), type: ($value | describe)} | to json --raw
}'# '--' '0001'])
        assert equal $command_result {value: '0001', type: glob}
    } finally {
        rm -r -f $fixture_root
    }

    # The fixture is owned by this test, so its removal is part of the contract.
    assert (not ($fixture_root | path exists))
}

def main [] {
    test-yaml-spec-selection
    test-yaml-reader-strictness
    test-yaml-writer-non-roundtrip
    test-row-condition-predicates
    test-binary-filesize-slicing
    test-semver-comparison
    test-take-include-boundary
    test-group-by-null-keys
    test-path-type-and-error-labels
    test-deprecation-metadata
    test-nested-finally-cleanup
    test-external-arg-tokens
    print 'nu-0.115-smoke: ok'
}
