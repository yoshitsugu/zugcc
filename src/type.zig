const std = @import("std");
const allocPrint0 = std.fmt.allocPrint0;
const Node = @import("parse.zig").Node;
const globals = @import("globals.zig");

pub const TypeKind = enum {
    TyInt,
    TyPtr,
};

pub const Type = struct {
    kind: TypeKind,
    base: ?*Type,

    pub var INT_SIZE_STR: [:0]u8 = undefined;

    pub fn initGlobals() void {
        Type.INT_SIZE_STR = stringToSlice("8");
    }

    pub fn init(kind: TypeKind) Type {
        return Type{
            .kind = kind,
            .base = null,
        };
    }

    pub fn allocInit(kind: TypeKind) *Type {
        var ty = globals.allocator.create(Type) catch @panic("cannot allocate Type");
        ty.* = Type.init(kind);
        return ty;
    }

    pub fn pointerTo(base: *Type) *Type {
        var ty = Type.allocInit(.TyPtr);
        ty.base = base;
        return ty;
    }

    pub fn isInteger(self: *Type) bool {
        return self.*.kind == .TyInt;
    }
};

pub fn addType(nodeWithNull: ?*Node) void {
    if (nodeWithNull == null or nodeWithNull.?.*.ty != null)
        return;

    var node = nodeWithNull.?;

    addType(node.*.lhs);
    addType(node.*.rhs);
    addType(node.*.cond);
    addType(node.*.then);
    addType(node.*.els);
    addType(node.*.init);
    addType(node.*.inc);

    var n = node.*.body;
    while (n != null) {
        addType(n.?);
        n = n.?.*.next;
    }

    switch (node.*.kind) {
        .NdAdd, .NdSub, .NdMul, .NdDiv, .NdNeg, .NdAssign => {
            node.*.ty = node.*.lhs.?.*.ty;
            return;
        },
        .NdEq, .NdNe, .NdLt, .NdLe, .NdVar, .NdNum => {
            node.*.ty = Type.allocInit(.TyInt);
            return;
        },
        .NdAddr => {
            node.*.ty = Type.pointerTo(node.*.lhs.?.*.ty.?);
            return;
        },
        .NdDeref => {
            if (node.*.lhs.?.*.ty.?.*.kind == .TyPtr) {
                node.*.ty = node.*.lhs.?.*.ty.?.*.base;
            } else {
                node.*.ty = Type.allocInit(.TyInt);
            }
            return;
        },
        else => {
            return;
        },
    }
}

fn stringToSlice(s: [*:0]const u8) [:0]u8 {
    return allocPrint0(globals.allocator, "{}", .{s}) catch @panic("cannot allocate string");
}
