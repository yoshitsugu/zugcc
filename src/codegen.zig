const std = @import("std");
const ArrayList = std.ArrayList;
const stdout = std.io.getStdOut().outStream();
const allocPrint0 = std.fmt.allocPrint0;
const parse = @import("parse.zig");
const NodeKind = parse.NodeKind;
const Node = parse.Node;
const Obj = parse.Obj;
const assert = @import("std").debug.assert;
const err = @import("error.zig");
const errorAt = err.errorAt;
const errorAtToken = err.errorAtToken;
const t = @import("type.zig");
const Type = t.Type;
const TypeKind = t.TypeKind;
const allocator = @import("allocator.zig");
const getAllocator = allocator.getAllocator;

var depth: usize = 0;
var count_i: usize = 0;
var ARGREG8 = [_][:0]const u8{ "%dil", "%sil", "%dl", "%cl", "%r8b", "%r9b" };
var ARGREG64 = [_][:0]const u8{ "%rdi", "%rsi", "%rdx", "%rcx", "%r8", "%r9" };
var current_fn: *Obj = undefined;
var outStream: std.fs.File.OutStream = undefined;

pub fn codegen(prog: ArrayList(*Obj), out: *std.fs.File) !void {
    outStream = out.outStream();
    _ = assignLvarOffsets(prog);
    try emitData(prog);
    try emitText(prog);
}

fn emitData(prog: ArrayList(*Obj)) !void {
    for (prog.items) |v| {
        if (v.*.is_function)
            continue;

        try println("  .data", .{});
        try println("  .globl {}", .{v.*.name});
        try println("{}:", .{v.*.name});

        if (v.*.init_data.len != 0) {
            for (v.*.init_data) |c| {
                try println("  .byte {}", .{c});
            }
        } else {
            try println("  .zero {}", .{v.*.ty.?.*.size});
        }
    }
}

fn emitText(prog: ArrayList(*Obj)) !void {
    for (prog.items) |func| {
        if (!func.*.is_function)
            continue;
        try println("  .globl {}", .{func.*.name});
        try println("  .text", .{});
        try println("{}:", .{func.*.name});

        current_fn = func;

        // Prologue
        try println("  push %rbp", .{});
        try println("  mov %rsp, %rbp", .{});
        try println("  sub ${}, %rsp", .{func.*.stack_size});

        const fparams = func.params.items;
        var i: usize = fparams.len;
        while (i > 0) {
            const fparam = fparams[i - 1];
            if (fparam.*.ty.?.*.size == 1) {
                try println("  mov {}, {}(%rbp)", .{ ARGREG8[fparams.len - i], fparam.*.offset });
            } else {
                try println("  mov {}, {}(%rbp)", .{ ARGREG64[fparams.len - i], fparam.*.offset });
            }
            i -= 1;
        }

        try genStmt(func.*.body);
        assert(depth == 0);

        try println(".L.return.{}:", .{func.*.name});
        try println("  mov %rbp, %rsp", .{});
        try println("  pop %rbp", .{});
        try println("  ret", .{});
    }
}

fn genStmt(node: *Node) anyerror!void {
    try println("  .loc 1 {}", .{node.*.tok.*.line_no});

    switch (node.*.kind) {
        NodeKind.NdIf => {
            const c = count();
            try genExpr(node.*.cond);
            try println("  cmp $0, %rax", .{});
            try println("  je .L.else.{}", .{c});
            try genStmt(node.*.then.?);
            try println("  jmp .L.end.{}", .{c});
            try println(".L.else.{}:", .{c});
            if (node.*.els != null)
                try genStmt(node.*.els.?);
            try println(".L.end.{}:", .{c});
            return;
        },
        NodeKind.NdFor => {
            const c = count();
            if (node.*.init != null)
                try genStmt(node.*.init.?);
            try println(".L.begin.{}:", .{c});
            if (node.*.cond != null) {
                try genExpr(node.*.cond);
                try println("  cmp $0, %rax", .{});
                try println("  je .L.end.{}", .{c});
            }
            try genStmt(node.*.then.?);
            if (node.*.inc != null)
                try genExpr(node.*.inc);
            try println("  jmp .L.begin.{}", .{c});
            try println(".L.end.{}:", .{c});
            return;
        },
        NodeKind.NdBlock => {
            var n = node.*.body;
            while (n != null) {
                try genStmt(n.?);
                n = n.?.*.next;
            }
        },
        NodeKind.NdReturn => {
            try genExpr(node.*.lhs);
            try println("  jmp .L.return.{}", .{current_fn.*.name});
        },
        NodeKind.NdExprStmt => {
            try genExpr(node.*.lhs);
        },
        else => {
            errorAtToken(node.*.tok, "invalid statement");
        },
    }
}

fn genExpr(nodeWithNull: ?*Node) anyerror!void {
    if (nodeWithNull == null) {
        return;
    }
    const node: *Node = nodeWithNull.?;
    try println("  .loc 1 {}", .{node.*.tok.*.line_no});
    switch (node.*.kind) {
        NodeKind.NdNum => {
            try println("  mov ${}, %rax", .{node.*.val});
            return;
        },
        NodeKind.NdNeg => {
            try genExpr(node.*.lhs);
            try println("  neg %rax", .{});
            return;
        },
        NodeKind.NdVar, NodeKind.NdMember => {
            try genAddr(node);
            try load(node.*.ty.?);
            return;
        },
        NodeKind.NdDeref => {
            try genExpr(node.*.lhs);
            try load(node.*.ty.?);
            return;
        },
        NodeKind.NdAddr => {
            try genAddr(node.*.lhs.?);
            return;
        },
        NodeKind.NdAssign => {
            try genAddr(node.*.lhs.?);
            try push();
            try genExpr(node.*.rhs.?);
            try store(node.*.ty.?);
            return;
        },
        NodeKind.NdStmtExpr => {
            var n = node.*.body;
            while (n != null) : (n = n.?.*.next) {
                try genStmt(n.?);
            }
            return;
        },
        NodeKind.NdComma => {
            try genExpr(node.*.lhs);
            try genExpr(node.*.rhs);
            return;
        },
        NodeKind.NdFuncall => {
            var arg: ?*Node = node.*.args;
            var nargs: usize = 0;
            while (arg != null) {
                try genExpr(arg.?);
                try push();
                nargs += 1;
                arg = arg.?.*.next;
            }
            while (nargs > 0) {
                try pop(ARGREG64[nargs - 1]);
                nargs -= 1;
            }
            try println("  mov $0, %rax", .{});
            try println("  call {}", .{node.*.funcname});
            return;
        },
        else => {},
    }

    try genExpr(node.*.rhs);
    try push();
    try genExpr(node.*.lhs);
    try pop("%rdi");

    switch (node.*.kind) {
        NodeKind.NdAdd => try println("  add %rdi, %rax", .{}),
        NodeKind.NdSub => try println("  sub %rdi, %rax", .{}),
        NodeKind.NdMul => try println("  imul %rdi, %rax", .{}),
        NodeKind.NdDiv => {
            try println("  cqo", .{});
            try println("  idiv %rdi", .{});
        },
        NodeKind.NdEq, NodeKind.NdNe, NodeKind.NdLt, NodeKind.NdLe => {
            try println("  cmp %rdi, %rax", .{});

            if (node.*.kind == NodeKind.NdEq) {
                try println("  sete %al", .{});
            } else if (node.*.kind == NodeKind.NdNe) {
                try println("  setne %al", .{});
            } else if (node.*.kind == NodeKind.NdLt) {
                try println("  setl %al", .{});
            } else if (node.*.kind == NodeKind.NdLe) {
                try println("  setle %al", .{});
            }
            try println("  movzb %al, %rax", .{});
        },
        else => errorAtToken(node.*.tok, "code generationに失敗しました"),
    }
}

fn push() !void {
    try println("  push %rax", .{});
    depth += 1;
}

fn pop(arg: [:0]const u8) !void {
    try println("  pop {}", .{arg});
    depth -= 1;
}

fn genAddr(node: *Node) anyerror!void {
    switch (node.*.kind) {
        NodeKind.NdVar => {
            if (node.*.variable.?.*.is_local) {
                try println("  lea {}(%rbp), %rax", .{node.*.variable.?.*.offset});
            } else {
                try println("  lea {}(%rip), %rax", .{node.*.variable.?.*.name});
            }
            return;
        },
        NodeKind.NdDeref => {
            try genExpr(node.*.lhs);
            return;
        },
        NodeKind.NdComma => {
            try genExpr(node.*.lhs);
            try genAddr(node.*.rhs.?);
            return;
        },
        NodeKind.NdMember => {
            try genAddr(node.*.lhs.?);
            try println("  add ${}, %rax", .{node.*.member.?.*.offset});
            return;
        },
        else => errorAtToken(node.*.tok, "ローカル変数ではありません"),
    }
}

fn assignLvarOffsets(prog: ArrayList(*Obj)) void {
    for (prog.items) |func| {
        if (!func.*.is_function)
            continue;
        var offset: i32 = 0;

        const ls = func.*.locals.items;
        if (ls.len > 0) {
            var li: usize = ls.len - 1;
            while (true) {
                offset += @intCast(i32, ls[li].ty.?.*.size);
                offset = alignTo(offset, @intCast(i32, ls[li].ty.?.*.alignment));
                ls[li].offset = -offset;
                if (li > 0) {
                    li -= 1;
                } else {
                    break;
                }
            }
        }
        func.*.stack_size = alignTo(offset, 16);
    }
}

// アライン処理。関数を呼び出す前にRBPを16アラインしないといけない。
pub fn alignTo(n: i32, a: i32) i32 {
    return @divFloor((n + a - 1), a) * a;
}

fn count() !usize {
    count_i += 1;
    return count_i;
}

fn load(ty: *Type) !void {
    if (ty.*.kind == TypeKind.TyArray) {
        return;
    }

    if (ty.*.size == 1) {
        try println("  movsbq (%rax), %rax", .{});
    } else {
        try println("  mov (%rax), %rax", .{});
    }
}

fn store(ty: *Type) !void {
    try pop("%rdi");

    if (ty.*.size == 1) {
        try println("  mov %al, (%rdi)", .{});
    } else {
        try println("  mov %rax, (%rdi)", .{});
    }
}

pub fn println(comptime format: []const u8, args: anytype) !void {
    try outStream.print(format, args);
    try outStream.print("\n", .{});
}
