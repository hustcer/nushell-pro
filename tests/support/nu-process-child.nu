# Keep the job's group leader alive until the parent records its ownership.
# The program text comes only from trusted regression fixtures; paths/argv stay data.
def main [ready: path, gate: path, program: string, ...args: string] {
    let staging = ($ready | path dirname | path join ready.tmp)
    $nu.pid | into string | save $staging
    mv $staging $ready
    loop {
        if ($gate | path exists) { break }
        sleep 5ms
    }
    ^$nu.current-exe --no-config-file -c $program -- ...$args
}
