const std = @import("std");
const allocPrint0 = std.fmt.allocPrint0;
const stdout = std.io.getStdOut().outStream();
const print = stdout.print;
const ps = @import("parse.zig");
const Node = ps.Node;
const Member = ps.Member;
const Token = @import("tokenize.zig").Token;
const allocator = @import("allocator.zig");
const getAllocator = allocator.getAllocator;
const err = @import("error.zig");
const errorAt = err.errorAt;
const errorAtToken = err.errorAtToken;

pub const TypeKind = enum {
    TyChar,
    TyInt,
    TyLong,
    TyPtr,
    TyFunc,
    TyArray,
    TyStruct,
    TyUnion,
};

pub const Type = struct {
    kind: TypeKind,

    size: usize, // sizeof
    alignment: usize,

    base: ?*Type, // ポインタの場合に使う
    name: ?*Token, // 宣言のときに使う

    // Array
    array_len: usize,

    // Struct
    members: ?*Member,

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
            .alignment = 0,
            .base = null,
            .name = null,
            .array_len = 0,
            .members = null,
            .return_ty = null,
            .params = null,
            .next = null,
        };
    }

    pub fn allocInit(kind: TypeKind) *Type {
        var ty = getAllocator().create(Type) catch @panic("cannot allocate Type");
        ty.* = Type.init(kind);
        return ty;
    }

    pub fn typeInt() *Type {
        var ty = Type.allocInit(.TyInt);
        ty.*.size = 4;
        ty.*.alignment = 4;
        return ty;
    }

    pub fn typeLong() *Type {
        var ty = Type.allocInit(.TyLong);
        ty.*.size = 8;
        ty.*.alignment = 8;
        return ty;
    }

    pub fn typeChar() *Type {
        var ty = Type.allocInit(.TyChar);
        ty.*.size = 1;
        ty.*.alignment = 1;
        return ty;
    }

    pub fn pointerTo(base: *Type) *Type {
        var ty = Type.allocInit(.TyPtr);
        ty.*.base = base;
        ty.*.size = 8;
        ty.*.alignment = 8;
        return ty;
    }

    pub fn isInteger(self: *Type) bool {
        return self.*.kind == .TyInt or self.*.kind == .TyChar or self.*.kind == .TyLong;
    }

    pub fn funcType(return_ty: *Type) *Type {
        var ty = Type.allocInit(.TyFunc);
        ty.return_ty = return_ty;
        return ty;
    }

    pub fn arrayOf(base: *Type, len: usize) *Type {
        var ty = Type.allocInit(.TyArray);
        ty.*.size = base.*.size * len;
        ty.*.alignment = base.*.alignment;
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
                errorAtToken(node.*.lhs.?.*.tok, "not an lvalue");
            node.*.ty = node.*.lhs.?.*.ty;
            return;
        },
        .NdEq, .NdNe, .NdLt, .NdLe, .NdVar, .NdNum, .NdFuncall => {
            node.*.ty = Type.typeLong();
            return;
        },
        .NdComma => {
            node.*.ty = node.*.rhs.?.*.ty;
            return;
        },
        .NdMember => {
            node.*.ty = node.*.member.?.*.ty;
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
                errorAtToken(node.*.tok, "Invalid pointer dereference");
            node.*.ty = node.*.lhs.?.*.ty.?.*.base;
            return;
        },
        .NdStmtExpr => {
            if (node.*.body != null) {
                var stmt = node.*.body.?;
                while (stmt.*.next != null)
                    stmt = stmt.*.next.?;
                if (stmt.*.kind == .NdExprStmt) {
                    node.*.ty = stmt.*.lhs.?.*.ty.?;
                    return;
                }
            }
            errorAtToken(node.*.tok, "statement expression returning void is not supported");
        },
        else => {
            return;
        },
    }
}

fn stringToSlice(s: [*:0]const u8) [:0]u8 {
    return allocPrint0(getAllocator(), "{}", .{s}) catch @panic("cannot allocate string");
}
