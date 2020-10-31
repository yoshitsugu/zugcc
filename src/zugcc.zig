const std = @import("std");
const stdout = std.io.getStdOut().outStream();
const print = stdout.print;
const t = @import("tokenize.zig");
const tokenize = t.tokenize;
const TokenKind = t.TokenKind;
const err = @import("error.zig");
const error_at = err.error_at;

fn streq(a: [:0]const u8, b: [:0]const u8) bool {
    return std.mem.eql(u8, a, b);
}

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = &arena.allocator;

    if (std.os.argv.len != 2) {
        @panic("コンパイルしたい文字列を引数として渡してください");
    }

    try print("  .globl main\n", .{});
    try print("main:\n", .{});

    const arg = std.os.argv[1];
    const tokenized = try tokenize(allocator, arg);

    var ti: usize = 0;
    const tokens = tokenized.items;
    while (ti < tokens.len) {
        const token = tokens[ti];
        switch (token.kind) {
            TokenKind.Num => {
                try print("  mov ${}, %rax\n", .{token.val});
                ti += 1;
            },
            TokenKind.Punct => {
                ti += 1;
                const num = tokens[ti];
                if (streq(token.val, "+")) {
                    if (num.kind != TokenKind.Num) {
                        error_at(arg, num.loc, "数値ではありません");
                    }
                    try print("  add ${}, %rax\n", .{num.val});
                    ti += 1;
                } else if (streq(token.val, "-")) {
                    if (num.kind != TokenKind.Num) {
                        error_at(arg, num.loc, "数値ではありません");
                    }
                    try print("  sub ${}, %rax\n", .{num.val});
                    ti += 1;
                } else {
                    error_at(arg, token.loc, "不正なトークンです");
                }
            },
        }
    }

    try print("  ret\n", .{});
}
