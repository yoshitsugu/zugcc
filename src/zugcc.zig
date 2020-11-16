const std = @import("std");
const fs = std.fs;
const stdout = std.io.getStdOut().outStream();
const print = stdout.print;
const stderr = std.io.getStdErr().outStream();
const printErr = stderr.print;
const allocPrint0 = std.fmt.allocPrint0;
const Allocator = std.mem.Allocator;
const t = @import("tokenize.zig");
const tokenizeFile = t.tokenizeFile;
const streq = t.streq;
const TokenKind = t.TokenKind;
const err = @import("error.zig");
const error_at = err.error_at;
const pr = @import("parse.zig");
const parse = pr.parse;
const codegen = @import("codegen.zig").codegen;
const allocator = @import("allocator.zig");

const ZugccOption = struct {
    output_path: [:0]u8,
    input_path: [:0]u8,
};

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    allocator.setAllocator(&arena.allocator);

    const option = try parseArgs(&arena.allocator);
    const tokenized = try tokenizeFile(option.*.input_path);
    var ti: usize = 0;
    const functions = try parse(tokenized.items, &ti);
    var out = openOutFile(option.*.output_path);
    try out.outStream().print("  .file 1 \"{}\"\n", .{option.*.input_path});
    try codegen(functions, &out);
}

fn parseArgs(alloc: *Allocator) !*ZugccOption {
    const args = try std.process.argsAlloc(alloc);
    defer std.process.argsFree(alloc, args);
    var option = try alloc.create(ZugccOption);
    option.* = ZugccOption{
        .input_path = "",
        .output_path = "",
    };
    var output = false;
    for (args) |arg, argi| {
        if (streq(arg, "--help")) {
            usage(0);
        }
        if (streq(arg, "-o")) {
            output = true;
            continue;
        }
        if (output) {
            option.*.output_path = try allocPrint0(alloc, "{}", .{arg});
            output = false;
            continue;
        }
        if (arg.len > 1 and arg[0] == '-') {
            std.debug.panic("Unknown argument: {}\n", .{arg});
        }
        if (argi > 0)
            option.*.input_path = try allocPrint0(alloc, "{}", .{arg});
    }
    return option;
}

fn usage(status: u8) void {
    printErr("zugcc [ -o <path> ] <file>\n", .{}) catch {};
    std.os.exit(status);
}

fn openOutFile(filename: [:0]u8) fs.File {
    if (filename.len == 0 or streq(filename, "-")) {
        return std.io.getStdOut();
    } else {
        const cwd = fs.cwd();
        cwd.writeFile(filename, "") catch |e| {
            std.debug.panic("Unable to create file: {}\n", .{@errorName(e)});
        };
        return cwd.openFile(filename, .{ .write = true }) catch |e| {
            std.debug.panic("Unable to open file: {}\n", .{@errorName(e)});
        };
    }
}
