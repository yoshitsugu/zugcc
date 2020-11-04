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
    NdReturn, // return
    NdBlock, // { ... }
    NdIf, // if
    NdExprStmt, // expression statement
    NdVar, // 変数
    NdNum, // 数値
};

pub const Node = struct {
    kind: NodeKind, // 種別
    next: ?*Node, // 次のノード。NdExprStmtのときに使う
    lhs: ?*Node, // Left-hand side
    rhs: ?*Node, // Right-hand side

    body: ?*Node, // NdBlockのときに使う

    // if 文で使う
    cond: ?*Node,
    then: ?*Node,
    els: ?*Node,

    variable: ?*Obj, // 変数、NdVarのときに使う
    val: ?[:0]u8, // NdNumのときに使われる

    pub fn init(kind: NodeKind) Node {
        return Node{
            .kind = kind,
            .next = null,
            .lhs = null,
            .rhs = null,
            .body = null,
            .cond = null,
            .then = null,
            .els = null,
            .variable = null,
            .val = null,
        };
    }

    pub fn allocInit(kind: NodeKind) *Node {
        var node = globals.allocator.create(Node) catch @panic("cannot allocate Node");
        node.* = Node.init(kind);
        return node;
    }
};

// ローカル変数
pub const Obj = struct {
    name: [:0]u8,
    offset: i32, // RBPからのオフセット
};

// 関数
pub const Func = struct {
    body: *Node, // 関数の開始ノード
    locals: ArrayList(*Obj),
    stack_size: i32,
};

pub fn newBinary(kind: NodeKind, lhs: *Node, rhs: *Node) *Node {
    var node = Node.allocInit(kind);
    node.*.lhs = lhs;
    node.*.rhs = rhs;
    return node;
}

pub fn newUnary(kind: NodeKind, lhs: *Node) *Node {
    var node = Node.allocInit(kind);
    node.*.lhs = lhs;
    return node;
}

fn newNum(val: [:0]u8) *Node {
    var node = Node.allocInit(.NdNum);
    node.*.val = val;
    return node;
}

fn newVarNode(v: *Obj) *Node {
    var node = Node.allocInit(.NdVar);
    node.*.variable = v;
    return node;
}

fn newBlockNode(n: ?*Node) *Node {
    var node = Node.allocInit(.NdBlock);
    node.* = Node.init(.NdBlock);
    node.*.body = n;
    return node;
}

// ローカル変数のリストを一時的に保有するためのグローバル変数
// 最終的にFuncに代入して使う
var locals: ArrayList(*Obj) = undefined;

fn newLVar(name: [:0]u8) !*Obj {
    var lvar = globals.allocator.create(Obj) catch @panic("cannot allocate Obj");
    lvar.* = Obj{
        .name = name,
        .offset = 0,
    };
    locals.append(lvar) catch @panic("ローカル変数のパースに失敗しました");
    return lvar;
}

fn findVar(token: Token) ?*Obj {
    for (locals.items) |lv| {
        if (streq(lv.*.name, token.val)) {
            return lv;
        }
    }
    return null;
}

// program = stmt*
pub fn parse(tokens: []Token, ti: *usize) !*Func {
    locals = ArrayList(*Obj).init(globals.allocator);
    var func = try globals.allocator.create(Func);
    func.* = Func{
        .body = stmt(tokens, ti),
        .locals = locals,
        .stack_size = 0,
    };
    return func;
}

// stmt = "return" expr ";"
//      | "if" "(" expr ")" stmt ("else" stmt)?
//      | "{" compound-stmt
//      | expr-stmt
pub fn stmt(tokens: []Token, ti: *usize) *Node {
    if (consumeTokVal(tokens, ti, "return")) {
        const node = newUnary(.NdReturn, expr(tokens, ti));
        skip(tokens, ti, ";");
        return node;
    }
    if (consumeTokVal(tokens, ti, "if")) {
        const node = Node.allocInit(.NdIf);
        skip(tokens, ti, "(");
        node.*.cond = expr(tokens, ti);
        skip(tokens, ti, ")");
        node.*.then = stmt(tokens, ti);
        if (consumeTokVal(tokens, ti, "else")) {
            node.*.els = stmt(tokens, ti);
        }
        return node;
    }
    if (consumeTokVal(tokens, ti, "{")) {
        return compoundStmt(tokens, ti);
    }
    return exprStmt(tokens, ti);
}

// compound-stmt = stmt* "}"
fn compoundStmt(tokens: []Token, ti: *usize) *Node {
    var head = Node.init(.NdNum);
    var cur: *Node = &head;
    var end = false;
    while (ti.* < tokens.len) {
        if (consumeTokVal(tokens, ti, "}")) {
            end = true;
            break;
        }
        cur.*.next = stmt(tokens, ti);
        cur = cur.*.next.?;
    }
    if (!end) {
        errorAt(tokens[tokens.len - 1].loc, " } がありません");
    }
    return newBlockNode(head.next);
}

// expr-stmt = expr? ";"
fn exprStmt(tokens: []Token, ti: *usize) *Node {
    if (consumeTokVal(tokens, ti, ";")) {
        return newBlockNode(null);
    }
    const node = newUnary(.NdExprStmt, expr(tokens, ti));
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
        var v = findVar(token);
        if (v == null) {
            v = try newLVar(token.val);
        }
        ti.* += 1;
        return newVarNode(v.?);
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
