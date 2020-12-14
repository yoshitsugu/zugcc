const std = @import("std");
const allocPrint0 = std.fmt.allocPrint0;
const stdout = std.io.getStdOut().outStream();
const print = stdout.print;
const ps = @import("parse.zig");
const Node = ps.Node;
const Member = ps.Member;
const newCast = ps.newCast;
const tk = @import("tokenize.zig");
const Token = tk.Token;
const atoi = tk.atoi;
const allocator = @import("allocator.zig");
const getAllocator = allocator.getAllocator;
const err = @import("error.zig");
const errorAt = err.errorAt;
const errorAtToken = err.errorAtToken;

pub const TypeKind = enum {
    TyVoid,
    TyChar,
    TyShort,
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

    pub fn typeVoid() *Type {
        var ty = Type.allocInit(.TyVoid);
        ty.*.size = 1;
        ty.*.alignment = 1;
        return ty;
    }

    pub fn typeChar() *Type {
        var ty = Type.allocInit(.TyChar);
        ty.*.size = 1;
        ty.*.alignment = 1;
        return ty;
    }

    pub fn typeShort() *Type {
        var ty = Type.allocInit(.TyShort);
        ty.*.size = 2;
        ty.*.alignment = 2;
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

    pub fn pointerTo(base: *Type) *Type {
        var ty = Type.allocInit(.TyPtr);
        ty.*.base = base;
        ty.*.size = 8;
        ty.*.alignment = 8;
        return ty;
    }

    pub fn isInteger(self: *Type) bool {
        return self.*.kind == .TyChar or self.*.kind == .TyShort or self.*.kind == .TyInt or self.*.kind == .TyLong;
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
        .NdNum => {
            const valueAsI64 = atoi(node.*.val.?);
            @setRuntimeSafety(false);
            node.*.ty = if (valueAsI64 == @intCast(i32, valueAsI64)) Type.typeInt() else Type.typeLong();
            return;
        },
        .NdAdd, .NdSub, .NdMul, .NdDiv => {
            usualArithConv(&(node.*.lhs.?), &(node.*.rhs.?));
            node.*.ty = node.*.lhs.?.*.ty;
            return;
        },
        .NdNeg => {
            var ty = getCommonType(Type.typeInt(), node.*.lhs.?.*.ty.?);
            node.*.lhs = newCast(node.*.lhs.?, ty);
            node.*.ty = ty;
            return;
        },
        .NdAssign => {
            if (node.*.lhs.?.*.ty.?.*.kind == .TyArray)
                errorAtToken(node.*.lhs.?.*.tok, "not an lvalue");
            if (node.*.lhs.?.*.ty.?.*.kind != .TyStruct)
                node.*.rhs = newCast(node.*.rhs.?, node.*.lhs.?.*.ty.?);
            node.*.ty = node.*.lhs.?.*.ty;
            return;
        },
        .NdEq, .NdNe, .NdLt, .NdLe => {
            usualArithConv(&(node.*.lhs.?), &(node.*.rhs.?));
            node.*.ty = Type.typeLong();
            return;
        },
        .NdVar => {
            node.*.ty = node.*.variable.?.*.ty;
            return;
        },
        .NdFuncall => {
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
            if (node.*.lhs.?.*.ty.?.*.base.?.*.kind == .TyVoid)
                errorAtToken(node.*.tok, "void型をdereferenceしようとしています");
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

pub fn getCommonType(ty1: *Type, ty2: *Type) *Type {
    if (ty1.*.base != null)
        return Type.pointerTo(ty1.*.base.?);
    if (ty1.*.size == 8 or ty2.*.size == 8)
        return Type.typeLong();
    return Type.typeInt();
}

pub fn usualArithConv(lhs: **Node, rhs: **Node) void {
    var ty = getCommonType(lhs.*.*.ty.?, rhs.*.*.ty.?);
    lhs.* = newCast(lhs.*, ty);
    rhs.* = newCast(rhs.*, ty);
}

fn stringToSlice(s: [*:0]const u8) [:0]u8 {
    return allocPrint0(getAllocator(), "{}", .{s}) catch @panic("cannot allocate string");
}

pub fn copyType(ty: *Type) *Type {
    var newType = Type.allocInit(ty.*.kind);
    newType.*.size = ty.*.size;
    newType.*.alignment = ty.*.alignment;
    newType.*.base = ty.*.base;
    newType.*.name = ty.*.name;
    newType.*.array_len = ty.*.array_len;
    newType.*.members = ty.*.members;
    newType.*.return_ty = ty.*.return_ty;
    newType.*.params = ty.*.params;
    newType.*.next = ty.*.next;

    return newType;
}
