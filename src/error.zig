const std = @import("std");
const stderr = std.io.getStdErr().outStream();
const printErr = stderr.print;
const Token = @import("tokenize.zig").Token;

var target_string: [:0]u8 = "";
var target_filename: [:0]u8 = "";

pub fn setTargetString(str: [:0]u8) void {
    target_string = str;
}
pub fn setTargetFilename(filename: [:0]u8) void {
    target_filename = filename;
}

pub fn errorAt(index: usize, line: ?usize, errorMessage: [*:0]const u8) noreturn {
    var input = target_string;
    var start: usize = index;
    while (0 < start and input[start - 1] != '\n')
        start -= 1;
    var end: usize = index;
    while (end < input.len and input[end] != '\n')
        end += 1;

    var line_no: usize = 0;
    if (line == null) {
        var i: usize = 0;
        while (i < start) : (i += 1) {
            if (input[i] == '\n') {
                line_no += 1;
            }
        }
        line_no += 1;
    } else {
        line_no = line.?;
    }
    _ = printErr("{}:{}: \n", .{ target_filename, line_no }) catch {};
    _ = printErr(" {}\n", .{input[start..end]}) catch {};
    var i = start;
    while (i < index) : (i += 1) {
        _ = printErr(" ", .{}) catch {};
    }
    _ = printErr("^ {}\n", .{errorMessage}) catch {};
    std.os.exit(1);
}

pub fn errorAtToken(token: *Token, errorMessage: [*:0]const u8) noreturn {
    errorAt(token.*.loc, token.*.line_no, errorMessage);
}
