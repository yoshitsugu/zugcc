const std = @import("std");

const stdout = std.io.getStdOut().outStream();
const print = stdout.print;

pub fn main() !void {
    if (std.os.argv.len != 2) {
        @panic("Argument length must be 2");
    }
    try print("  .globl main\n", .{});
    try print("main:\n", .{});
    try print("  mov ${}, %rax\n", .{std.os.argv[1]});
    try print("  ret\n", .{});
}
