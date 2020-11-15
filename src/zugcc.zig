const std = @import("std");
const stdout = std.io.getStdOut().outStream();
const print = stdout.print;
const allocPrint0 = std.fmt.allocPrint0;
const t = @import("tokenize.zig");
const tokenizeFile = t.tokenizeFile;
const TokenKind = t.TokenKind;
const err = @import("error.zig");
const error_at = err.error_at;
const pr = @import("parse.zig");
const parse = pr.parse;
const codegen = @import("codegen.zig").codegen;
const allocator = @import("allocator.zig");

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    allocator.setAllocator(&arena.allocator);

    if (std.os.argv.len != 2) {
        @panic("コンパイルしたい文字列を引数として渡してください");
    }

    const filename = try allocPrint0(allocator.getAllocator(), "{}", .{std.os.argv[1]});
    const arg = std.os.argv[1];
    const tokenized = try tokenizeFile(filename);
    var ti: usize = 0;
    const functions = try parse(tokenized.items, &ti);
    try codegen(functions);
}
