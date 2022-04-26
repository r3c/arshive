#!/bin/sh

compare() {
    local actual="$2"
    local actual_line
    local context="$1"
    local expect_line
    local line_index=0
    local result=0

    while IFS='' read -r actual_line <&3 && read -r expect_line <&4; do
        line_index="$((line_index + 1))"

        if ! echo "$actual_line" | grep -Eq -- "$expect_line"; then
            echo >&2 "match error for '$context' at line $line_index:"
            echo >&2 "  expected: [$expect_line]"
            echo >&2 "  obtained: [$actual_line]"

            result=1
        fi
    done 3< "$actual" 4<&0

    return "$result"
}

invoke() {
    local config="$1"
    local script="$basedir/../src/arshive.sh"

    "$shell" "$script" -c "$config" -d
}

run() {
    local worktree="$(mktemp -d)"
    local config="$worktree/config"
    local result=0
    local shell="$1"
    local stderr="$worktree/stderr"

    # Should read rule files from absolute path
    absolute="$(mktemp -d)"

    cat > "$config" << EOF
sources='$absolute/*'
EOF

    cat > "$absolute/1" << EOF
test-directory1: echo -n > {}
EOF

    cat > "$absolute/2" << EOF
test-directory2: echo -n > {}
EOF

    invoke "$config" 2> "$stderr"
    rm -r "$absolute"

    if ! printf '^test-directory1: should backup\n^test-directory2: should backup\n^$\n' | compare 'test-absolute' "$stderr"; then
        result=1
    fi

    # Should read rule files from relative path
    relative1="$(dirname "$config")/test-relative1.rule"
    relative2="$(dirname "$config")/test-relative2.rule"

    cat > "$config" << EOF
sources=test-*.rule
EOF

    cat > "$relative1" << EOF
test-relative1: echo -n > {}
EOF

    cat > "$relative2" << EOF
test-relative2: echo -n > {}
EOF

    invoke "$config" 2> "$stderr"
    rm "$relative1" "$relative2"

    if ! printf '^test-relative1: should backup\n^test-relative2: should backup\n^$\n' | compare 'test-relative' "$stderr"; then
        result=1
    fi

    # Should parse and execute various rule files
    for rule in "$basedir"/*.rule; do
        cat > "$config" << EOF
sources='$(readlink -m "$rule")'
EOF

        invoke "$config" 2> "$stderr"

        if ! compare "$rule (stderr)" "$stderr" < "${rule%.rule}.stderr"; then
            result=1
        fi
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
