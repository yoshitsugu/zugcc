#!/bin/sh
tmp=`mktemp -d /tmp/zugcc-test-XXXXXX`
trap 'rm -rf $tmp' INT TERM HUP EXIT
echo > $tmp/empty.c

check() {
    if [ $? -eq 0 ]; then
        echo "testing $1 ... passed"
    else
        echo "testing $1 ... failed"
        exit 1
    fi
}

# -o
rm -f $tmp/out
./zig-cache/bin/zugcc -o $tmp/out $tmp/empty.c
[ -f $tmp/out ]
check -o

# --help
./zig-cache/bin/zugcc --help 2>&1 | grep -q zugcc
check --help

echo OK