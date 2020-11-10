const std = @import("std");
const Allocator = std.mem.Allocator;

pub var allocator: *Allocator = undefined;

pub fn setAllocator(a: *Allocator) void {
    allocator = a;
}

pub fn getAllocator() *Allocator {
    return allocator;
}
