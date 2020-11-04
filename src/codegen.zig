const std = @import("std");
const ArrayList = std.ArrayList;
const stdout = std.io.getStdOut().outStream();
const print = stdout.print;
const parse = @import("parse.zig");
const NodeKind = parse.NodeKind;
const Node = parse.Node;
const Func = parse.Func;
const assert = @import("std").debug.assert;

var depth: usize = 0;
var count_i: usize = 0;

pub fn codegen(func: *Func) !void {
    _ = assignLvarOffsets(func);

    try print("  .globl main\n", .{});
    try print("main:\n", .{});

    // Prologue
    try print("  push %rbp\n", .{});
    try print("  mov %rsp, %rbp\n", .{});
    try print("  sub ${}, %rsp\n", .{func.*.stack_size});

    try genStmt(func.*.body);
    assert(depth == 0);

    try print(".L.return:\n", .{});
    try print("  mov %rbp, %rsp\n", .{});
    try print("  pop %rbp\n", .{});
    try print("  ret\n", .{});
}

fn genStmt(node: *Node) anyerror!void {
    const c = count();
    switch (node.*.kind) {
        NodeKind.NdIf => {
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
        NodeKind.NdBlock => {
            var n = node.*.body;
            while (n != null) {
                try genStmt(n.?);
                n = n.?.*.next;
            }
        },
        NodeKind.NdReturn => {
            try genExpr(node.*.lhs);
            try print("  jmp .L.return\n", .{});
        },
        NodeKind.NdExprStmt => {
            try genExpr(node.*.lhs);
        },
        else => {
            std.debug.panic("invalid statement {}", .{node.*.kind});
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
            try print("  mov (%rax), %rax\n", .{});
            return;
        },
        NodeKind.NdAssign => {
            try genAddr(node.*.lhs.?);
            try push();
            try genExpr(node.*.rhs.?);
            try pop("%rdi");
            try print("  mov %rax, (%rdi)\n", .{});
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
        else => @panic("code generationに失敗しました"),
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
    if (node.*.kind == NodeKind.NdVar) {
        try print("  lea {}(%rbp), %rax\n", .{node.*.variable.?.*.offset});
        return;
    }

    @panic("ローカル変数ではありません");
}

fn assignLvarOffsets(func: *Func) void {
    var offset: i32 = 0;
    for (func.*.locals.items) |lv| {
        offset += 8;
        lv.offset = -offset;
    }
    func.*.stack_size = alignTo(offset, 16);
}

// アライン処理。関数を呼び出す前にRBPを16アラインしないといけない。
fn alignTo(n: i32, a: i32) i32 {
    return @divFloor((n + a - 1), a) * a;
}

fn count() !usize {
    count_i += 1;
    return count_i;
}
