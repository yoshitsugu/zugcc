const std = @import("std");
const stdout = std.io.getStdOut().outStream();
const print = stdout.print;
const t = @import("tokenize.zig");
const tokenize = t.tokenize;
const TokenKind = t.TokenKind;
const err = @import("error.zig");
const error_at = err.error_at;
const setTargetString = err.setTargetString;
const pr = @import("parse.zig");
const parse = pr.parse;
const codegen = @import("codegen.zig").codegen;
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
    const function = try parse(tokenized.items, &ti);
    try codegen(function);
}
