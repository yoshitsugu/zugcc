#!/bin/bash
set -e
zig build
set +e

assert() {
  set -e
  expected="$1"
  input="$2"
  ./zig-cache/bin/zugcc "$input" > tmp.s || exit
  gcc -static -o tmp tmp.s
  set +e
  ./tmp
  actual="$?"

  if [ "$actual" = "$expected" ]; then
    echo "$input => $actual"
  else
    echo "$input => $expected expected, but got $actual"
    exit 1
  fi
}

assert 0 0
assert 42 42
assert 15 '10-3+8'
assert 31 '10 * 3 + 4 / 2 - 1'

echo OK