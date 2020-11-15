const std = @import("std");
const stderr = std.io.getStdErr().outStream();
const printErr = stderr.print;

var target_string: *const [:0]u8 = undefined;
var target_filename: [:0]u8 = "";

pub fn setTargetString(strPtr: *const [:0]u8) void {
    target_string = strPtr;
}
pub fn setTargetFilename(filename: [:0]u8) void {
    target_filename = filename;
}

pub fn errorAt(index: usize, errorMessage: [*:0]const u8) noreturn {
    var input = target_string.*;
    var start: usize = index;
    while (0 < start and input[start - 1] != '\n')
        start -= 1;
    var end: usize = index;
    while (end < input.len and end != '\n')
        end += 1;

    var i: usize = 0;
    var line_no: usize = 0;
    while (i < start) : (i += 1) {
        if (input[i] == '\n') {
            line_no += 1;
        }
    }
    _ = printErr("{}:{}: \n", .{ target_filename, line_no + 1 }) catch {};
    _ = printErr(" {}", .{input[start..end]}) catch {};
    i = start;
    while (i < end) : (i += 1) {
        _ = printErr(" ", .{}) catch {};
    }
    _ = printErr("^ {}\n", .{errorMessage}) catch {};
    std.os.exit(1);
}
