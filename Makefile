zugcc: zugcc.zig tokenize.zig
	zig build-exe zugcc.zig

test: zugcc
	./test.sh

clean:
	rm -f zugcc *.o *~ tmp*

.PHONY: test clean