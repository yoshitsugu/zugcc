const std = @import("std");
const stdout = std.io.getStdOut().outStream();
const print = stdout.print;
const parse = @import("parse.zig");
const NodeKind = parse.NodeKind;
const Node = parse.Node;

pub fn genExpr(nodeWithNull: ?*Node) anyerror!void {
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
}

fn pop(arg: [:0]const u8) !void {
    try print("  pop {}\n", .{arg});
}
