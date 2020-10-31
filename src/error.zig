const std = @import("std");
const stderr = std.io.getStdErr().outStream();
const printErr = stderr.print;

pub fn error_at(str: [*:0]const u8, index: usize, errorMessage: [*:0]const u8) noreturn {
    _ = printErr("=== COMPILE ERROR ===\n{}\n", .{str}) catch {};
    var i: usize = 0;
    while (i < index) {
        _ = printErr(" ", .{}) catch {};
        i += 1;
    }
    _ = printErr("^ {}\n", .{errorMessage}) catch {};
    std.os.exit(1);
}
