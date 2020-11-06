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

assert 0 '{ return 0; }'
assert 42 '{ return 42; }'
assert 15 '{ return 10-3+8; }'
assert 31 '{ return 10 * 3 + 4 / 2 - 1; }'
assert 40 '{ return (6 - (+3) + - 1) * -20 * -1; }'
assert 1 '{ return (3 < (3 + 2)) == (4 >= 4); }'
assert 1 '{ return (5 > 4) != (100 <= 1); }'
assert 2 '{ 3 + 20 / 5; return 4 - 2; }'
assert 7 '{ return 3 + 20 / 5;  4 - 2; }'

assert 1 '{ int a = 1; int b = 2; return b - a; }'
assert 14 '{ int abc = 10; int def = 3; return abc * def - 10 - (2 * 3); }'
assert 3 '{ int a = 1; {int b = 1;} return 3;}'
assert 5 '{ ;{;}; return 5;}'

assert 3 '{ if (0) return 2; return 3; }'
assert 3 '{ if (1-1) return 2; return 3; }'
assert 2 '{ if (1) return 2; return 3; }'
assert 2 '{ if (2-1) return 2; return 3; }'
assert 4 '{ if (0) { 1; 2; return 3; } else { return 4; } }'
assert 3 '{ if (1) { 1; 2; return 3; } else { return 4; } }'

assert 55 '{ int i=0; int j=0; for (i=0; i<=10; i=i+1) j=i+j; return j; }'
assert 3 '{ for (;;) {return 3;} return 5; }'
assert 13 '{ int a = 10; int b = 0; while (b < 3) { a = a + 1; b = b + 1; } return a; }'
assert 3 '{ while (1) {return 3;} return 5; }'

assert 20 '{ int a = 1; int *b = &a; *b = 20; return a; }'
assert 7 '{ int a = 1; int b = 7; return *(&a + 1); }'
assert 5 '{ int x=3; return (&x+2)-&x+3; }'
assert 30 '{ int x=3; int *y = &x; *y = 30; return x; }'

echo OK