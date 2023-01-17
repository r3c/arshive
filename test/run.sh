#!/bin/sh

compare() {
    local actual="$2"
    local actual_eof=0
    local actual_line
    local context="$1"
    local expect_eof=0
    local expect_line
    local line_index=0
    local result=0

    while true; do
        IFS='' read -r actual_line <&3 || actual_eof=1
        IFS='' read -r expect_line <&4 || expect_eof=1

        if [ "$actual_eof" -ne 0 -a "$expect_eof" -ne 0 ]; then
            break
        elif [ "$actual_eof" -ne 0 ]; then
            echo >&2 "error for '$context' at line $line_index, unexpected EOL"
            echo >&2 "  expected: [$expect_line]"

            return=1

            break
        elif [ "$expect_eof" -ne 0 ]; then
            echo >&2 "error for '$context' at line $line_index, exceeding line"
            echo >&2 "  obtained: [$actual_line]"

            return=1

            break
        fi

        line_index="$((line_index + 1))"

        if ! echo "$actual_line" | grep -Eq -- "$expect_line"; then
            echo >&2 "error for '$context' at line $line_index, lines did not match:"
            echo >&2 "  expected: [$expect_line]"
            echo >&2 "  obtained: [$actual_line]"

            result=1

            break
        fi
    done 3<"$actual" 4<&0

    return "$result"
}

invoke() {
    local script="$basedir/../src/arshive.sh"
    local shell="$1"

    shift

    "$shell" "$script" "$@"
}

run() {
    local worktree="$(mktemp -d)"
    local config="$worktree/config"
    local result=0
    local shell="$1"
    local stderr="$worktree/stderr"

    # Should read rule files from absolute path
    absolute="$(mktemp -d)"

    cat >"$config" <<EOF
rules='$absolute/*'
EOF

    cat >"$absolute/1" <<EOF
test-directory1: echo -n > {}
EOF

    cat >"$absolute/2" <<EOF
test-directory2: echo -n > {}
EOF

    invoke "$shell" -c "$config" -d 2>"$stderr"
    rm -r "$absolute"

    if ! printf '^test-directory1: backup file would have been created without dry-run mode\n^test-directory2: backup file would have been created without dry-run mode\n' | compare 'test-absolute' "$stderr"; then
        result=1
    fi

    # Should read rule files from relative path
    relative1="$(dirname "$config")/test-relative1.rule"
    relative2="$(dirname "$config")/test-relative2.rule"

    cat >"$config" <<EOF
rules=test-*.rule
EOF

    cat >"$relative1" <<EOF
test-relative1: echo -n > {}
EOF

    cat >"$relative2" <<EOF
test-relative2: echo -n > {}
EOF

    invoke "$shell" -c "$config" -d 2>"$stderr"
    rm "$relative1" "$relative2"

    if ! printf '^test-relative1: backup file would have been created without dry-run mode\n^test-relative2: backup file would have been created without dry-run mode\n' | compare 'test-relative' "$stderr"; then
        result=1
    fi

    # Should parse and execute various rule files
    for rule in "$basedir"/*.rule; do
        target="$worktree/target"

        mkdir "$target"
        cat >"$config" <<EOF
rules='$(readlink -m "$rule")'
target='$target'
EOF

        invoke "$shell" -c "$config" 2>"$stderr"

        if ! compare "$rule (stderr)" "$stderr" <"${rule%.rule}.stderr"; then
            result=1
        fi

        rm -r "$target"
    done

    # Cleanup
    rm -r "$worktree"

    return "$result"
}

basedir="$(dirname "$0")"
opt_shell=sh

while getopts :hs: opt; do
    case "$opt" in
    h)
        echo >&2 "$(basename $0) [-h] [-s <shell>]"
        echo >&2 '  -h: display help and exit'
        echo >&2 '  -s <shell>: use specified shell to run tests'
        exit
        ;;

    s)
        opt_shell="$OPTARG"
        ;;

    :)
        echo >&2 "missing argument for option '-$OPTARG'"
        exit 1
        ;;

    *)
        echo >&2 "unknown option '-$OPTARG'"
        exit 1
        ;;
    esac
done

shift "$((OPTIND - 1))"

run "$opt_shell"

exit $?
