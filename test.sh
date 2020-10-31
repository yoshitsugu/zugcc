#!/bin/bash
assert() {
  expected="$1"
  input="$2"
  zig build
  ./zig-cache/bin/zugcc "$input" > tmp.s || exit
  gcc -static -o tmp tmp.s
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
assert 15 '10 - 3 + 8'

echo OK