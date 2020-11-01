const std = @import("std");
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;
const stdout = std.io.getStdOut().outStream();
const print = stdout.print;
const allocPrint0 = std.fmt.allocPrint0;
const err = @import("error.zig");
const errorAt = err.errorAt;
const tokenize = @import("tokenize.zig");
const Token = tokenize.Token;
const TokenKind = tokenize.TokenKind;
const globals = @import("globals.zig");

pub const NodeKind = enum {
    NdAdd, // +
    NdSub, // -
    NdMul, // *
    NdDiv, // /
    NdNum, // 数値
};

pub const Node = struct {
    kind: NodeKind, // 種別
    lhs: ?*Node, // Left-hand side
    rhs: ?*Node, // Right-hand side
    val: ?[:0]u8, // Numのときに使われる

    pub fn init(kind: NodeKind) Node {
        return Node{
            .kind = kind,
            .lhs = null,
            .rhs = null,
            .val = null,
        };
    }
};

fn streq(a: [:0]const u8, b: [:0]const u8) bool {
    return std.mem.eql(u8, a, b);
}

pub fn newBinary(kind: NodeKind, lhs: *Node, rhs: *Node) *Node {
    var node = globals.allocator.create(Node) catch @panic("cannot allocate Node");
    node.* = Node.init(kind);
    node.*.lhs = lhs;
    node.*.rhs = rhs;
    return node;
}

pub fn newNum(val: [:0]u8) *Node {
    var node = globals.allocator.create(Node) catch @panic("cannot allocate Node");
    node.* = Node.init(.NdNum);
    node.*.val = val;
    return node;
}

// expr = mul ("+" mul | "-" mul)*
pub fn expr(tokens: []Token, ti: *usize) *Node {
    var node = mul(tokens, ti);

    while (ti.* < tokens.len) {
        const token = tokens[ti.*];
        if (streq(token.val, "+")) {
            ti.* += 1;
            node = newBinary(.NdAdd, node, mul(tokens, ti));
        } else if (streq(token.val, "-")) {
            ti.* += 1;
            node = newBinary(.NdSub, node, mul(tokens, ti));
        } else {
            break;
        }
    }
    return node;
}

// mul = primary ("*" primary | "/" primary)*
pub fn mul(tokens: []Token, ti: *usize) *Node {
    var node = primary(tokens, ti);

    while (ti.* < tokens.len) {
        const token = tokens[ti.*];
        if (streq(token.val, "*")) {
            ti.* += 1;
            node = newBinary(.NdMul, node, primary(tokens, ti));
        } else if (streq(token.val, "/")) {
            ti.* += 1;
            node = newBinary(.NdDiv, node, primary(tokens, ti));
        } else {
            break;
        }
    }
    return node;
}

// primary = "(" expr ")" | num
pub fn primary(tokens: []Token, ti: *usize) *Node {
    const token = tokens[ti.*];
    if (streq(token.val, "(")) {
        ti.* += 1;
        const node = expr(tokens, ti);
        skip(tokens, ti, ")");
        return node;
    }

    if (token.kind == TokenKind.TkNum) {
        ti.* += 1;
        return newNum(token.val);
    }

    errorAt(token.loc, "expected an expression");
}

fn skip(tokens: []Token, ti: *usize, s: [:0]const u8) void {
    const token = tokens[ti.*];
    if (streq(token.val, s)) {
        ti.* += 1;
    } else {
        const string = allocPrint0(globals.allocator, "期待した文字列がありません: {}", .{s}) catch "期待した文字列がありません";
        errorAt(token.loc, string);
    }
}
