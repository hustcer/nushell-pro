# Keep the version-to-suite routing here so local checks and CI run the same plan.
# All syntax in this entrypoint must parse on the oldest CI version, Nu 0.115.1.
const repo_root = path self ..

def main [--expected-version: string]: nothing -> nothing {
    let current_version = (version | get version)
    if $expected_version != null and $current_version != $expected_version {
        error make {msg: $'Expected Nu ($expected_version), got ($current_version)'}
    }
    let release = ($current_version | into semver)
    if not ($release in ('>=0.115.1' | into semver-range)) {
        error make {msg: 'The CI runner requires Nu 0.115.1 or newer'}
    }
    cd $repo_root
    let suites = [
        {file: 'tests/nu-0.115-smoke.nu', since: '0.115.1'}
        {file: 'tests/validation-and-daemon-smoke.nu', since: '0.115.1'}
        {file: 'tests/strings-and-validation-smoke.nu', since: '0.115.1'}
        {file: 'tests/nu-0.116-smoke.nu', since: '0.116.0'}
        {file: 'tests/process-cleanup-smoke.nu', since: '0.116.0'}
        {file: 'tests/nu-0.117-smoke.nu', since: '0.117.0'}
    ]
    let selected = ($suites | where {|suite| $release >= ($suite.since | into semver) } | get file)
    if ($selected | is-empty) { error make {msg: 'No CI suites selected'} }
    version | print
    print $'Nu ($current_version): running ($selected | length) suites'

    # Parse only selected suites: older Nu must never parse newer-version syntax.
    if 'tests/process-cleanup-smoke.nu' in $selected {
        nu-check --debug --as-module ($repo_root | path join tests support nu-process.nu) | ignore
        nu-check --debug ($repo_root | path join tests support nu-process-child.nu) | ignore
    }
    for suite in $selected {
        nu-check --debug ($repo_root | path join $suite) | ignore
    }
    for suite in $selected {
        print $'Running ($suite)'
        let result = (^$nu.current-exe --no-config-file $suite | complete)
        print --no-newline $result.stdout
        if ($result.stderr | is-not-empty) { print --stderr --no-newline $result.stderr }
        if $result.exit_code != 0 {
            error make {msg: $'($suite) failed with exit code ($result.exit_code)'}
        }
    }
    print $'CI suites passed: ($selected | length)'
}
