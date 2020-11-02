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
const streq = tokenize.streq;
const globals = @import("globals.zig");

pub const NodeKind = enum {
    NdAdd, // +
    NdSub, // -
    NdMul, // *
    NdDiv, // /
    NdNeg, // unary -
    NdEq, // ==
    NdNe, // !=
    NdLt, // <
    NdLe, // <=
    NdAssign, // =
    NdVar, // 変数
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

pub fn newBinary(kind: NodeKind, lhs: *Node, rhs: *Node) *Node {
    var node = globals.allocator.create(Node) catch @panic("cannot allocate Node");
    node.* = Node.init(kind);
    node.*.lhs = lhs;
    node.*.rhs = rhs;
    return node;
}

pub fn newUnary(kind: NodeKind, lhs: *Node) *Node {
    var node = globals.allocator.create(Node) catch @panic("cannot allocate Node");
    node.* = Node.init(kind);
    node.*.lhs = lhs;
    return node;
}

pub fn newNum(val: [:0]u8) *Node {
    var node = globals.allocator.create(Node) catch @panic("cannot allocate Node");
    node.* = Node.init(.NdNum);
    node.*.val = val;
    return node;
}

pub fn newVar(name: [:0]u8) *Node {
    var node = globals.allocator.create(Node) catch @panic("cannot allocate Node");
    node.* = Node.init(.NdVar);
    node.*.val = name;
    return node;
}

// program = stmt*
pub fn parse(tokens: []Token, ti: *usize) !ArrayList(*Node) {
    var nodes = ArrayList(*Node).init(globals.allocator);
    while (ti.* < tokens.len) {
        try nodes.append(stmt(tokens, ti));
    }
    return nodes;
}

// stmt = expr ";"
pub fn stmt(tokens: []Token, ti: *usize) *Node {
    const node = expr(tokens, ti);
    skip(tokens, ti, ";");
    return node;
}

// expr = assign
pub fn expr(tokens: []Token, ti: *usize) *Node {
    return assign(tokens, ti);
}

// assign = equality ("=" assign)?
pub fn assign(tokens: []Token, ti: *usize) *Node {
    var node = equality(tokens, ti);

    if (consumeTokVal(tokens, ti, "=")) {
        node = newBinary(.NdAssign, node, assign(tokens, ti));
    }
    return node;
}

// equality = relational ("==" relational | "!=" relational)*
pub fn equality(tokens: []Token, ti: *usize) *Node {
    var node = relational(tokens, ti);

    while (ti.* < tokens.len) {
        const token = tokens[ti.*];
        if (consumeTokVal(tokens, ti, "==")) {
            node = newBinary(.NdEq, node, relational(tokens, ti));
        } else if (consumeTokVal(tokens, ti, "!=")) {
            node = newBinary(.NdNe, node, relational(tokens, ti));
        } else {
            break;
        }
    }
    return node;
}

// relational = add ("<" add | "<=" add | ">" add | ">=" add)*
pub fn relational(tokens: []Token, ti: *usize) *Node {
    var node = add(tokens, ti);

    while (ti.* < tokens.len) {
        const token = tokens[ti.*];
        if (consumeTokVal(tokens, ti, "<")) {
            node = newBinary(.NdLt, node, add(tokens, ti));
        } else if (consumeTokVal(tokens, ti, "<=")) {
            node = newBinary(.NdLe, node, add(tokens, ti));
        } else if (consumeTokVal(tokens, ti, ">")) {
            node = newBinary(.NdLt, add(tokens, ti), node);
        } else if (consumeTokVal(tokens, ti, ">=")) {
            node = newBinary(.NdLe, add(tokens, ti), node);
        } else {
            break;
        }
    }
    return node;
}

// add = mul ("+" mul | "-" mul)*
pub fn add(tokens: []Token, ti: *usize) *Node {
    var node = mul(tokens, ti);

    while (ti.* < tokens.len) {
        const token = tokens[ti.*];
        if (consumeTokVal(tokens, ti, "+")) {
            node = newBinary(.NdAdd, node, mul(tokens, ti));
        } else if (consumeTokVal(tokens, ti, "-")) {
            node = newBinary(.NdSub, node, mul(tokens, ti));
        } else {
            break;
        }
    }
    return node;
}

// mul = unary ("*" unary | "/" unary)*
pub fn mul(tokens: []Token, ti: *usize) *Node {
    var node = unary(tokens, ti);

    while (ti.* < tokens.len) {
        const token = tokens[ti.*];
        if (streq(token.val, "*")) {
            ti.* += 1;
            node = newBinary(.NdMul, node, unary(tokens, ti));
        } else if (streq(token.val, "/")) {
            ti.* += 1;
            node = newBinary(.NdDiv, node, unary(tokens, ti));
        } else {
            break;
        }
    }
    return node;
}

// unary = ("+" | "-") unary
//       | primary
pub fn unary(tokens: []Token, ti: *usize) *Node {
    const token = tokens[ti.*];
    if (streq(token.val, "+")) {
        ti.* += 1;
        return unary(tokens, ti);
    }
    if (streq(token.val, "-")) {
        ti.* += 1;
        return newUnary(.NdNeg, unary(tokens, ti));
    }
    return primary(tokens, ti);
}

// primary = "(" expr ")" | ident | num
pub fn primary(tokens: []Token, ti: *usize) *Node {
    const token = tokens[ti.*];
    if (streq(token.val, "(")) {
        ti.* += 1;
        const node = expr(tokens, ti);
        skip(tokens, ti, ")");
        return node;
    }

    if (token.kind == TokenKind.TkIdent) {
        ti.* += 1;
        return newVar(token.val);
    }

    if (token.kind == TokenKind.TkNum) {
        ti.* += 1;
        return newNum(token.val);
    }

    errorAt(token.loc, "expected an expression");
}

fn skip(tokens: []Token, ti: *usize, s: [:0]const u8) void {
    if (tokens.len <= ti.*) {
        errorAt(tokens.len, "予期せず入力が終了しました。最後に ; を入力してください。");
    }
    const token = tokens[ti.*];
    if (streq(token.val, s)) {
        ti.* += 1;
    } else {
        const string = allocPrint0(globals.allocator, "期待した文字列がありません: {}", .{s}) catch "期待した文字列がありません";
        errorAt(token.loc, string);
    }
}

fn consumeTokVal(tokens: []Token, ti: *usize, s: [:0]const u8) bool {
    if (tokens.len <= ti.*) {
        return false;
    }
    const token = tokens[ti.*];
    if (streq(token.val, s)) {
        ti.* += 1;
        return true;
    }
    return false;
}
