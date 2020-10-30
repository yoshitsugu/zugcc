const std = @import("std");

const stdout = std.io.getStdOut().outStream();
const print = stdout.print;

fn is_number(c: u8) bool {
    return '0' <= c and c <= '9';
}

fn expect_number(ptr: [*:0]const u8, index: usize) usize {
    if (is_number(ptr[index])) {
        return parse_number(ptr, index);
    } else {
        @panic("数値ではありません");
    }
}

fn parse_number(ptr: [*:0]const u8, index: usize) usize {
    var end = index;
    while (is_number(ptr[end])) {
        end += 1;
    }
    return end;
}

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = &arena.allocator;

    if (std.os.argv.len != 2) {
        @panic("コンパイルしたい文字列を1つ引数として渡してください");
    }

    try print("  .globl main\n", .{});
    try print("main:\n", .{});

    const arg = std.os.argv[1];
    var i: usize = 0;
    {
        const j = i;
        i = expect_number(arg, i);
        try print("  mov ${}, %rax\n", .{arg[j..i]});
    }
    while (arg[i] != 0) {
        if (arg[i] == '+') {
            i += 1;
            const j = i;
            i = expect_number(arg, i);
            try print("  add ${}, %rax\n", .{arg[j..i]});
        } else if (arg[i] == '-') {
            i += 1;
            const j = i;
            i = expect_number(arg, i);
            try print("  sub ${}, %rax\n", .{arg[j..i]});
        } else {
            @panic(try std.fmt.allocPrint(allocator, "不正な文字です: {}", .{arg[i .. i + 1]}));
        }
    }
    try print("  ret\n", .{});
}
