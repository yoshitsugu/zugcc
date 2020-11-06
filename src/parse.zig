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
const typezig = @import("type.zig");
const TypeKind = typezig.TypeKind;
const Type = typezig.Type;
const addType = typezig.addType;

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
    NdAddr, // 単項演算子の&
    NdDeref, // 単項演算子の*
    NdReturn, // return
    NdBlock, // { ... }
    NdIf, // if
    NdFor, // "for" or "while"
    NdFuncall, // 関数呼出
    NdExprStmt, // expression statement
    NdVar, // 変数
    NdNum, // 数値
};

pub const Node = struct {
    kind: NodeKind, // 種別
    next: ?*Node, // 次のノード。NdExprStmtのときに使う
    ty: ?*Type, // 型情報
    tok: *Token, // エラー情報の補足のためにトークンの代表値を持っておく

    lhs: ?*Node, // Left-hand side
    rhs: ?*Node, // Right-hand side

    body: ?*Node, // NdBlockのときに使う

    // if, for, while 文で使う
    cond: ?*Node,
    then: ?*Node,
    els: ?*Node,
    init: ?*Node,
    inc: ?*Node,

    // 関数呼出のときに使う
    funcname: ?[:0]u8,
    args: ?*Node,

    variable: ?*Obj, // 変数、NdVarのときに使う
    val: ?[:0]u8, // NdNumのときに使われる

    pub fn init(kind: NodeKind, tok: *Token) Node {
        return Node{
            .kind = kind,
            .next = null,
            .ty = null,
            .tok = tok,
            .lhs = null,
            .rhs = null,
            .body = null,
            .cond = null,
            .then = null,
            .els = null,
            .init = null,
            .inc = null,
            .funcname = null,
            .args = null,
            .variable = null,
            .val = null,
        };
    }

    pub fn allocInit(kind: NodeKind, tok: *Token) *Node {
        var node = globals.allocator.create(Node) catch @panic("cannot allocate Node");
        node.* = Node.init(kind, tok);
        return node;
    }
};

// ローカル変数
pub const Obj = struct {
    name: [:0]u8,
    ty: ?*Type,
    offset: i32, // RBPからのオフセット
};

// 関数
pub const Func = struct {
    body: *Node, // 関数の開始ノード
    locals: ArrayList(*Obj),
    stack_size: i32,
};

pub fn newBinary(kind: NodeKind, lhs: *Node, rhs: *Node, tok: *Token) *Node {
    var node = Node.allocInit(kind, tok);
    node.*.lhs = lhs;
    node.*.rhs = rhs;
    return node;
}

pub fn newUnary(kind: NodeKind, lhs: *Node, tok: *Token) *Node {
    var node = Node.allocInit(kind, tok);
    node.*.lhs = lhs;
    return node;
}

fn newNum(val: [:0]u8, tok: *Token) *Node {
    var node = Node.allocInit(.NdNum, tok);
    node.*.val = val;
    return node;
}

fn newVarNode(v: *Obj, tok: *Token) *Node {
    var node = Node.allocInit(.NdVar, tok);
    node.*.variable = v;
    return node;
}

fn newBlockNode(n: ?*Node, tok: *Token) *Node {
    var node = Node.allocInit(.NdBlock, tok);
    node.*.body = n;
    return node;
}

// ローカル変数のリストを一時的に保有するためのグローバル変数
// 最終的にFuncに代入して使う
var locals: ArrayList(*Obj) = undefined;

fn newLVar(name: [:0]u8, ty: *Type) !*Obj {
    var lvar = globals.allocator.create(Obj) catch @panic("cannot allocate Obj");
    lvar.* = Obj{
        .name = name,
        .ty = ty,
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

fn getOrLast(tokens: []Token, ti: *usize) *Token {
    if (ti.* < tokens.len) {
        return &tokens[ti.*];
    }
    return &tokens[tokens.len - 1];
}

// program = stmt*
pub fn parse(tokens: []Token, ti: *usize) !*Func {
    Type.initGlobals();
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
//      | "for" "(" expr-stmt expr? ";" expr? ")" stmt
//      | "while" "(" expr ")" stmt
//      | "{" compound-stmt
//      | expr-stmt
pub fn stmt(tokens: []Token, ti: *usize) *Node {
    if (consumeTokVal(tokens, ti, "return")) {
        const node = newUnary(.NdReturn, expr(tokens, ti), getOrLast(tokens, ti));
        skip(tokens, ti, ";");
        return node;
    }
    if (consumeTokVal(tokens, ti, "if")) {
        const node = Node.allocInit(.NdIf, getOrLast(tokens, ti));
        skip(tokens, ti, "(");
        node.*.cond = expr(tokens, ti);
        skip(tokens, ti, ")");
        node.*.then = stmt(tokens, ti);
        if (consumeTokVal(tokens, ti, "else")) {
            node.*.els = stmt(tokens, ti);
        }
        return node;
    }
    if (consumeTokVal(tokens, ti, "for")) {
        const node = Node.allocInit(.NdFor, getOrLast(tokens, ti));
        skip(tokens, ti, "(");

        node.*.init = exprStmt(tokens, ti);

        if (!consumeTokVal(tokens, ti, ";")) {
            node.*.cond = expr(tokens, ti);
            skip(tokens, ti, ";");
        }

        if (!consumeTokVal(tokens, ti, ")")) {
            node.*.inc = expr(tokens, ti);
            skip(tokens, ti, ")");
        }

        node.*.then = stmt(tokens, ti);
        return node;
    }
    if (consumeTokVal(tokens, ti, "while")) {
        const node = Node.allocInit(.NdFor, getOrLast(tokens, ti));
        skip(tokens, ti, "(");
        node.*.cond = expr(tokens, ti);
        skip(tokens, ti, ")");
        node.*.then = stmt(tokens, ti);
        return node;
    }
    if (consumeTokVal(tokens, ti, "{")) {
        return compoundStmt(tokens, ti);
    }
    return exprStmt(tokens, ti);
}

// compound-stmt = (declaration | stmt)* "}"
fn compoundStmt(tokens: []Token, ti: *usize) *Node {
    var head = Node.init(.NdNum, getOrLast(tokens, ti));
    var cur: *Node = &head;
    var end = false;
    while (ti.* < tokens.len) {
        if (consumeTokVal(tokens, ti, "}")) {
            end = true;
            break;
        }
        if (streq(tokens[ti.*].val, "int")) {
            cur.*.next = declaration(tokens, ti);
        } else {
            cur.*.next = stmt(tokens, ti);
        }
        cur = cur.*.next.?;
        addType(cur);
    }
    if (!end) {
        errorAt(tokens[tokens.len - 1].loc, " } がありません");
    }
    return newBlockNode(head.next, getOrLast(tokens, ti));
}

// expr-stmt = expr? ";"
fn exprStmt(tokens: []Token, ti: *usize) *Node {
    if (consumeTokVal(tokens, ti, ";")) {
        return newBlockNode(null, getOrLast(tokens, ti));
    }
    const node = newUnary(.NdExprStmt, expr(tokens, ti), getOrLast(tokens, ti));
    skip(tokens, ti, ";");
    return node;
}

// declaration = declspec (declarator ("=" expr)? ("," declarator ("=" expr)?)*)? ";"
fn declaration(tokens: []Token, ti: *usize) *Node {
    if (tokens.len <= ti.*) {
        errorAt(tokens.len - 1, "Unexpected EOF");
    }
    var token = &tokens[ti.*];
    const baseTy = declspec(tokens, ti);

    var head = Node.init(.NdNum, token);
    var cur = &head;
    var i: usize = ti.*;

    while (ti.* < tokens.len and !consumeTokVal(tokens, ti, ";")) {
        if (i != ti.*)
            skip(tokens, ti, ",");

        var ty = declarator(tokens, ti, baseTy);
        var variable = newLVar(ty.*.name.?.*.val, ty) catch @panic("cannot allocate lvar");

        if (!consumeTokVal(tokens, ti, "="))
            continue;

        var lhs = newVarNode(variable, ty.*.name.?);

        var rhs = assign(tokens, ti);
        token = &tokens[ti.*];
        var node = newBinary(.NdAssign, lhs, rhs, token);
        cur.*.next = newUnary(.NdExprStmt, node, token);
        cur = cur.*.next.?;
    }

    var node = Node.allocInit(.NdBlock, token);
    node.*.body = head.next;

    return node;
}

// declarator = "*"* ident
fn declarator(tokens: []Token, ti: *usize, typ: *Type) *Type {
    var ty = typ;
    while (consumeTokVal(tokens, ti, "*"))
        ty = Type.pointerTo(ty);

    var tok = &tokens[ti.*];
    if (tok.*.kind != .TkIdent)
        errorAt(tok.*.loc, "expected a variable name");

    ty.*.name = tok;
    ti.* += 1;
    return ty;
}

// declspec = "int"
fn declspec(tokens: []Token, ti: *usize) *Type {
    skip(tokens, ti, "int");
    return Type.allocInit(.TyInt);
}

// expr = assign
pub fn expr(tokens: []Token, ti: *usize) *Node {
    return assign(tokens, ti);
}

// assign = equality ("=" assign)?
pub fn assign(tokens: []Token, ti: *usize) *Node {
    var node = equality(tokens, ti);

    if (consumeTokVal(tokens, ti, "=")) {
        node = newBinary(.NdAssign, node, assign(tokens, ti), getOrLast(tokens, ti));
    }
    return node;
}

// equality = relational ("==" relational | "!=" relational)*
pub fn equality(tokens: []Token, ti: *usize) *Node {
    var node = relational(tokens, ti);

    while (ti.* < tokens.len) {
        const token = tokens[ti.*];
        if (consumeTokVal(tokens, ti, "==")) {
            node = newBinary(.NdEq, node, relational(tokens, ti), getOrLast(tokens, ti));
        } else if (consumeTokVal(tokens, ti, "!=")) {
            node = newBinary(.NdNe, node, relational(tokens, ti), getOrLast(tokens, ti));
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
            node = newBinary(.NdLt, node, add(tokens, ti), getOrLast(tokens, ti));
        } else if (consumeTokVal(tokens, ti, "<=")) {
            node = newBinary(.NdLe, node, add(tokens, ti), getOrLast(tokens, ti));
        } else if (consumeTokVal(tokens, ti, ">")) {
            node = newBinary(.NdLt, add(tokens, ti), node, getOrLast(tokens, ti));
        } else if (consumeTokVal(tokens, ti, ">=")) {
            node = newBinary(.NdLe, add(tokens, ti), node, getOrLast(tokens, ti));
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
            node = newAdd(node, mul(tokens, ti), getOrLast(tokens, ti));
        } else if (consumeTokVal(tokens, ti, "-")) {
            node = newSub(node, mul(tokens, ti), getOrLast(tokens, ti));
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
            node = newBinary(.NdMul, node, unary(tokens, ti), getOrLast(tokens, ti));
        } else if (streq(token.val, "/")) {
            ti.* += 1;
            node = newBinary(.NdDiv, node, unary(tokens, ti), getOrLast(tokens, ti));
        } else {
            break;
        }
    }
    return node;
}

// unary = ("+" | "-" | "*" | "&") unary
//       | primary
pub fn unary(tokens: []Token, ti: *usize) *Node {
    const token = tokens[ti.*];
    if (consumeTokVal(tokens, ti, "+")) {
        return unary(tokens, ti);
    }
    if (consumeTokVal(tokens, ti, "-")) {
        return newUnary(.NdNeg, unary(tokens, ti), getOrLast(tokens, ti));
    }
    if (consumeTokVal(tokens, ti, "&")) {
        return newUnary(.NdAddr, unary(tokens, ti), getOrLast(tokens, ti));
    }
    if (consumeTokVal(tokens, ti, "*")) {
        return newUnary(.NdDeref, unary(tokens, ti), getOrLast(tokens, ti));
    }
    return primary(tokens, ti);
}

// primary = "(" expr ")" | ident func-args? | num
pub fn primary(tokens: []Token, ti: *usize) *Node {
    const token = tokens[ti.*];
    if (streq(token.val, "(")) {
        ti.* += 1;
        const node = expr(tokens, ti);
        skip(tokens, ti, ")");
        return node;
    }

    if (token.kind == TokenKind.TkIdent) {
        // 関数呼出のとき
        if (ti.* + 1 < tokens.len and consumeTokVal(tokens, &(ti.* + 1), "(")) {
            return funcall(tokens, ti);
        }
        // 変数
        var v = findVar(token);
        if (v == null) {
            errorAt(token.loc, "変数が未定義です");
        }
        ti.* += 1;
        return newVarNode(v.?, getOrLast(tokens, ti));
    }

    if (token.kind == TokenKind.TkNum) {
        ti.* += 1;
        return newNum(token.val, getOrLast(tokens, ti));
    }

    errorAt(token.loc, "expected an expression");
}

// funcall = ident "(" (assign ("," assign)*)? ")"
fn funcall(tokens: []Token, ti: *usize) *Node {
    var start = &tokens[ti.*];
    ti.* += 2;

    const startTi = ti.*;
    var head = Node.init(.NdNum, start);
    var cur = &head;
    while (!consumeTokVal(tokens, ti, ")")) {
        if (startTi != ti.*)
            skip(tokens, ti, ",");
        cur.*.next = assign(tokens, ti);
        cur = cur.*.next.?;
    }

    var node = Node.allocInit(.NdFuncall, start);
    node.*.funcname = start.*.val;
    node.*.args = head.next;
    return node;
}

fn skip(tokens: []Token, ti: *usize, s: [:0]const u8) void {
    if (tokens.len <= ti.*) {
        errorAt(tokens.len, "予期せず入力が終了しました。最後に ; を入力してください。");
    }
    const token = tokens[ti.*];
    if (streq(token.val, s)) {
        ti.* += 1;
    } else {
        const string = allocPrint0(globals.allocator, "期待した文字列 {} がありません", .{s}) catch "期待した文字列がありません";
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

fn newAdd(lhs: *Node, rhs: *Node, tok: *Token) *Node {
    addType(lhs);
    addType(rhs);

    // num + num
    if (lhs.*.ty.?.*.isInteger() and rhs.*.ty.?.*.isInteger())
        return newBinary(.NdAdd, lhs, rhs, tok);

    // ptr + ptr はエラー
    if (lhs.*.ty.?.*.base != null and rhs.*.ty.?.*.base != null)
        errorAt(tok.loc, "invalid operands");

    var l = lhs;
    var r = rhs;

    // num + ptrを ptr + numにそろえる
    if (lhs.*.ty.?.*.base == null and rhs.*.ty.?.*.base != null) {
        l = rhs;
        r = lhs;
    }

    // ptr + num
    // とりあえず8固定
    r = newBinary(.NdMul, r, newNum(Type.INT_SIZE_STR, tok), tok);
    addType(r);
    var n = newBinary(.NdAdd, l, r, tok);
    addType(n);
    return n;
}

fn newSub(lhs: *Node, rhs: *Node, tok: *Token) *Node {
    addType(lhs);
    addType(rhs);

    // num - num
    if (lhs.*.ty.?.*.isInteger() and rhs.*.ty.?.*.isInteger())
        return newBinary(.NdSub, lhs, rhs, tok);

    // ptr - ptr はポインタ間にいくつ要素(ポインタの指す型)があるかを返す
    if (lhs.*.ty.?.*.base != null and rhs.*.ty.?.*.base != null) {
        const node = newBinary(.NdSub, lhs, rhs, tok);
        node.*.ty = Type.allocInit(TypeKind.TyInt);
        return newBinary(.NdDiv, node, newNum(Type.INT_SIZE_STR, tok), tok);
    }

    // ptr - num
    // とりあえず8固定
    if (lhs.*.ty.?.*.base != null and rhs.*.ty.?.*.base == null) {
        var r = newBinary(.NdMul, rhs, newNum(Type.INT_SIZE_STR, tok), tok);
        addType(r);
        var n = newBinary(.NdSub, lhs, r, tok);
        n.*.ty = lhs.*.ty;
        return n;
    }

    errorAt(tok.loc, "Invalid operands");
}
