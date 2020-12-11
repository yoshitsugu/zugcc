CFLAGS=-std=c11 -g -fno-common

SRCS=$(wildcard src/*.zig)

TEST_SRCS=$(wildcard test/*.c)
TESTS=$(TEST_SRCS:.c=.exe)

zugcc: $(SRCS)
	zig build
	cp zig-cache/bin/zugcc .

test/%.exe: zugcc test/%.c
	$(CC) -o- -E -P -C test/$*.c | ./zugcc -o test/$*.s -
	$(CC) -o $@ test/$*.s -xc test/common

test: $(TESTS)
	for i in $^; do echo $$i; ./$$i || exit 1; echo; done
	test/driver.sh

clean:
	rm -rf zugcc zig-cache $(TESTS) test/*.s test/*.exe
	find * -type f '(' -name '*~' -o -name '*.o' ')' -exec rm {} ';'

.PHONY: test clean
