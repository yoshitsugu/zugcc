const std = @import("std");
const stderr = std.io.getStdErr().outStream();
const printErr = stderr.print;

var target_string: *const [*:0]u8 = undefined;

pub fn setTargetString(strPtr: *const [*:0]u8) void {
    target_string = strPtr;
}

pub fn errorAt(index: usize, errorMessage: [*:0]const u8) noreturn {
    _ = printErr("=== COMPILE ERROR ===\n{}\n", .{target_string.*}) catch {};
    var i: usize = 0;
    while (i < index) {
        _ = printErr(" ", .{}) catch {};
        i += 1;
    }
    _ = printErr("^ {}\n", .{errorMessage}) catch {};
    std.os.exit(1);
}
