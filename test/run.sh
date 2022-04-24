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
    local script=$(dirname "$0")/../src/mysync.sh

    "$script" -c "$config" -d
}

worktree="$(mktemp -d)"
config="$worktree/config"
result=0
stderr="$worktree/stderr"

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
for path in $(dirname "$0")/*.rule; do
    cat > "$config" << EOF
sources='$(readlink -m "$path")'
EOF

    invoke "$config" 2> "$stderr"

    if ! compare "$path (stderr)" "$stderr" < "${path%.rule}.stderr"; then
        result=1
    fi
done

# Cleanup
rm -r "$worktree"

exit "$result"
