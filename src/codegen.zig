const std = @import("std");
const ArrayList = std.ArrayList;
const stdout = std.io.getStdOut().outStream();
const print = stdout.print;
const parse = @import("parse.zig");
const NodeKind = parse.NodeKind;
const Node = parse.Node;
const Obj = parse.Obj;
const assert = @import("std").debug.assert;
const err = @import("error.zig");
const errorAt = err.errorAt;
const t = @import("type.zig");
const Type = t.Type;
const TypeKind = t.TypeKind;

var depth: usize = 0;
var count_i: usize = 0;
var ARGREG8 = [_][:0]const u8{ "%dil", "%sil", "%dl", "%cl", "%r8b", "%r9b" };
var ARGREG64 = [_][:0]const u8{ "%rdi", "%rsi", "%rdx", "%rcx", "%r8", "%r9" };
var current_fn: *Obj = undefined;

pub fn codegen(prog: ArrayList(*Obj)) !void {
    _ = assignLvarOffsets(prog);
    try emitData(prog);
    try emitText(prog);
}

fn emitData(prog: ArrayList(*Obj)) !void {
    for (prog.items) |v| {
        if (v.*.is_function)
            continue;

        try print("  .data\n", .{});
        try print("  .globl {}\n", .{v.*.name});
        try print("{}:\n", .{v.*.name});
        try print("  .zero {}\n", .{v.*.ty.?.*.size});
    }
}

fn emitText(prog: ArrayList(*Obj)) !void {
    for (prog.items) |func| {
        if (!func.*.is_function)
            continue;
        try print("  .globl {}\n", .{func.*.name});
        try print("  .text\n", .{});
        try print("{}:\n", .{func.*.name});

        current_fn = func;

        // Prologue
        try print("  push %rbp\n", .{});
        try print("  mov %rsp, %rbp\n", .{});
        try print("  sub ${}, %rsp\n", .{func.*.stack_size});

        const fparams = func.params.items;
        var i: usize = fparams.len;
        while (i > 0) {
            const fparam = fparams[i - 1];
            if (fparam.*.ty.?.*.size == 1) {
                try print("  mov {}, {}(%rbp)\n", .{ ARGREG8[fparams.len - i], fparam.*.offset });
            } else {
                try print("  mov {}, {}(%rbp)\n", .{ ARGREG64[fparams.len - i], fparam.*.offset });
            }
            i -= 1;
        }

        try genStmt(func.*.body);
        assert(depth == 0);

        try print(".L.return.{}:\n", .{func.*.name});
        try print("  mov %rbp, %rsp\n", .{});
        try print("  pop %rbp\n", .{});
        try print("  ret\n", .{});
    }
}

fn genStmt(node: *Node) anyerror!void {
    switch (node.*.kind) {
        NodeKind.NdIf => {
            const c = count();
            try genExpr(node.*.cond);
            try print("  cmp $0, %rax\n", .{});
            try print("  je .L.else.{}\n", .{c});
            try genStmt(node.*.then.?);
            try print("  jmp .L.end.{}\n", .{c});
            try print(".L.else.{}:\n", .{c});
            if (node.*.els != null)
                try genStmt(node.*.els.?);
            try print(".L.end.{}:\n", .{c});
            return;
        },
        NodeKind.NdFor => {
            const c = count();
            if (node.*.init != null)
                try genStmt(node.*.init.?);
            try print(".L.begin.{}:\n", .{c});
            if (node.*.cond != null) {
                try genExpr(node.*.cond);
                try print("  cmp $0, %rax\n", .{});
                try print("  je .L.end.{}\n", .{c});
            }
            try genStmt(node.*.then.?);
            if (node.*.inc != null)
                try genExpr(node.*.inc);
            try print("  jmp .L.begin.{}\n", .{c});
            try print(".L.end.{}:\n", .{c});
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
            try print("  jmp .L.return.{}\n", .{current_fn.*.name});
        },
        NodeKind.NdExprStmt => {
            try genExpr(node.*.lhs);
        },
        else => {
            errorAt(node.*.tok.*.loc, "invalid statement");
        },
    }
}

fn genExpr(nodeWithNull: ?*Node) anyerror!void {
    if (nodeWithNull == null) {
        return;
    }
    const node: *Node = nodeWithNull.?;
    switch (node.*.kind) {
        NodeKind.NdNum => {
            try print("  mov ${}, %rax\n", .{node.*.val});
            return;
        },
        NodeKind.NdNeg => {
            try genExpr(node.*.lhs);
            try print("  neg %rax\n", .{});
            return;
        },
        NodeKind.NdVar => {
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
            try print("  mov $0, %rax\n", .{});
            try print("  call {}\n", .{node.*.funcname});
            return;
        },
        else => {},
    }

    try genExpr(node.*.rhs);
    try push();
    try genExpr(node.*.lhs);
    try pop("%rdi");

    switch (node.*.kind) {
        NodeKind.NdAdd => try print("  add %rdi, %rax\n", .{}),
        NodeKind.NdSub => try print("  sub %rdi, %rax\n", .{}),
        NodeKind.NdMul => try print("  imul %rdi, %rax\n", .{}),
        NodeKind.NdDiv => {
            try print("  cqo\n", .{});
            try print("  idiv %rdi\n", .{});
        },
        NodeKind.NdEq, NodeKind.NdNe, NodeKind.NdLt, NodeKind.NdLe => {
            try print("  cmp %rdi, %rax\n", .{});

            if (node.*.kind == NodeKind.NdEq) {
                try print("  sete %al\n", .{});
            } else if (node.*.kind == NodeKind.NdNe) {
                try print("  setne %al\n", .{});
            } else if (node.*.kind == NodeKind.NdLt) {
                try print("  setl %al\n", .{});
            } else if (node.*.kind == NodeKind.NdLe) {
                try print("  setle %al\n", .{});
            }
            try print("  movzb %al, %rax\n", .{});
        },
        else => errorAt(node.*.tok.*.loc, "code generationに失敗しました"),
    }
}

fn push() !void {
    try print("  push %rax\n", .{});
    depth += 1;
}

fn pop(arg: [:0]const u8) !void {
    try print("  pop {}\n", .{arg});
    depth -= 1;
}

fn genAddr(node: *Node) !void {
    switch (node.*.kind) {
        NodeKind.NdVar => {
            if (node.*.variable.?.*.is_local) {
                try print("  lea {}(%rbp), %rax\n", .{node.*.variable.?.*.offset});
            } else {
                try print("  lea {}(%rip), %rax\n", .{node.*.variable.?.*.name});
            }
            return;
        },
        NodeKind.NdDeref => {
            try genExpr(node.*.lhs);
            return;
        },
        else => errorAt(node.*.tok.*.loc, "ローカル変数ではありません"),
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
fn alignTo(n: i32, a: i32) i32 {
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
        try print("  movsbq (%rax), %rax\n", .{});
    } else {
        try print("  mov (%rax), %rax\n", .{});
    }
}

fn store(ty: *Type) !void {
    try pop("%rdi");

    if (ty.*.size == 1) {
        try print("  mov %al, (%rdi)\n", .{});
    } else {
        try print("  mov %rax, (%rdi)\n", .{});
    }
}
