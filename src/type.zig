const std = @import("std");
const allocPrint0 = std.fmt.allocPrint0;
const stdout = std.io.getStdOut().outStream();
const print = stdout.print;
const Node = @import("parse.zig").Node;
const Token = @import("tokenize.zig").Token;
const globals = @import("globals.zig");
const err = @import("error.zig");
const errorAt = err.errorAt;

pub const TypeKind = enum {
    TyInt,
    TyPtr,
    TyFunc,
    TyArray,
};

pub const Type = struct {
    kind: TypeKind,

    // sizeof
    size: usize,

    base: ?*Type, // ポインタの場合に使う
    name: ?*Token, // 宣言のときに使う

    // Array
    array_len: usize,

    // 関数
    return_ty: ?*Type,
    params: ?*Type,
    next: ?*Type,

    pub var INT_SIZE_STR: [:0]u8 = undefined;

    pub fn initGlobals() void {
        Type.INT_SIZE_STR = stringToSlice("8");
    }

    pub fn init(kind: TypeKind) Type {
        return Type{
            .kind = kind,
            .size = 0,
            .base = null,
            .name = null,
            .array_len = 0,
            .return_ty = null,
            .params = null,
            .next = null,
        };
    }

    pub fn allocInit(kind: TypeKind) *Type {
        var ty = globals.allocator.create(Type) catch @panic("cannot allocate Type");
        ty.* = Type.init(kind);
        return ty;
    }

    pub fn typeInt() *Type {
        var ty = Type.allocInit(.TyInt);
        ty.*.size = 8;
        return ty;
    }

    pub fn pointerTo(base: *Type) *Type {
        var ty = Type.allocInit(.TyPtr);
        ty.*.base = base;
        ty.*.size = 8;
        return ty;
    }

    pub fn isInteger(self: *Type) bool {
        return self.*.kind == .TyInt;
    }

    pub fn funcType(return_ty: *Type) *Type {
        var ty = Type.allocInit(.TyFunc);
        ty.return_ty = return_ty;
        return ty;
    }

    pub fn arrayOf(base: *Type, len: usize) *Type {
        var ty = Type.allocInit(.TyArray);
        ty.*.size = base.*.size * len;
        ty.*.base = base;
        ty.*.array_len = len;
        return ty;
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
    n = node.*.args;
    while (n != null) {
        addType(n.?);
        n = n.?.*.next;
    }

    switch (node.*.kind) {
        .NdAdd, .NdSub, .NdMul, .NdDiv, .NdNeg => {
            node.*.ty = node.*.lhs.?.*.ty;
            return;
        },
        .NdAssign => {
            if (node.*.lhs.?.*.ty.?.*.kind == .TyArray)
                errorAt(node.*.lhs.?.*.tok.*.loc, "not an lvalue");
            node.*.ty = node.*.lhs.?.*.ty;
            return;
        },
        .NdEq, .NdNe, .NdLt, .NdLe, .NdVar, .NdNum, .NdFuncall => {
            node.*.ty = Type.typeInt();
            return;
        },
        .NdAddr => {
            if (node.*.lhs.?.*.ty.?.*.kind == .TyArray) {
                node.*.ty = Type.pointerTo(node.*.lhs.?.*.ty.?.*.base.?);
            } else {
                node.*.ty = Type.pointerTo(node.*.lhs.?.*.ty.?);
            }
            return;
        },
        .NdDeref => {
            if (node.*.lhs.?.*.ty.?.*.base == null)
                errorAt(node.*.tok.*.loc, "Invalid pointer dereference");
            node.*.ty = node.*.lhs.?.*.ty.?.*.base;
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
