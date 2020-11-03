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

assert 0 'return 0;'
assert 42 'return 42;'
assert 15 'return 10-3+8;'
assert 31 'return 10 * 3 + 4 / 2 - 1;'
assert 40 'return (6 - (+3) + - 1) * -20 * -1;'
assert 1 'return (3 < (3 + 2)) == (4 >= 4);'
assert 1 'return (5 > 4) != (100 <= 1);'
assert 2 '3 + 20 / 5; return 4 - 2;'
assert 7 'return 3 + 20 / 5;  4 - 2;'

assert 1 'a = 1;b = 2; return b - a;'
assert 14 'abc = 10; def = 3; return abc * def - 10 - (2 * 3);'

echo OK