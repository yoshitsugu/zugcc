const std = @import("std");
const stdout = std.io.getStdOut().outStream();
const print = stdout.print;
const t = @import("tokenize.zig");
const tokenize = t.tokenize;
const TokenKind = t.TokenKind;
const err = @import("error.zig");
const error_at = err.error_at;
const setTargetString = err.setTargetString;
const parse = @import("parse.zig");
const expr = parse.expr;
const codegen = @import("codegen.zig");
const genExpr = codegen.genExpr;
const globals = @import("globals.zig");

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    globals.setAllocator(&arena.allocator);

    if (std.os.argv.len != 2) {
        @panic("コンパイルしたい文字列を引数として渡してください");
    }

    const arg = std.os.argv[1];
    setTargetString(&arg);
    const tokenized = try tokenize(arg);
    var ti: usize = 0;
    const node = expr(tokenized.items, &ti);

    try print("  .globl main\n", .{});
    try print("main:\n", .{});

    try genExpr(node);

    try print("  ret\n", .{});
}
