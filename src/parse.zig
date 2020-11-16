const std = @import("std");
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;
const stdout = std.io.getStdOut().outStream();
const print = stdout.print;
const allocPrint0 = std.fmt.allocPrint0;
const err = @import("error.zig");
const errorAt = err.errorAt;
const errorAtToken = err.errorAtToken;
const tokenize = @import("tokenize.zig");
const Token = tokenize.Token;
const TokenKind = tokenize.TokenKind;
const atoi = tokenize.atoi;
const streq = tokenize.streq;
const allocator = @import("allocator.zig");
const getAllocator = allocator.getAllocator;
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
    NdComma, // ,
    NdAddr, // 単項演算子の&
    NdDeref, // 単項演算子の*
    NdReturn, // return
    NdBlock, // { ... }
    NdIf, // if
    NdFor, // "for" or "while"
    NdFuncall, // 関数呼出
    NdExprStmt, // expression statement
    NdStmtExpr, // statement expression
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
        var node = getAllocator().create(Node) catch @panic("cannot allocate Node");
        node.* = Node.init(kind, tok);
        return node;
    }
};

// 変数 or 関数
pub const Obj = struct {
    name: [:0]u8,
    ty: ?*Type,
    is_local: bool,
    is_function: bool,

    // ローカル変数のとき
    offset: i32, // RBPからのオフセット

    // グローバル変数のとき
    init_data: [:0]u8,

    // 関数のとき
    params: ArrayList(*Obj),
    body: *Node, // 関数の開始ノード
    locals: ArrayList(*Obj),
    stack_size: i32,

    pub fn initVar(is_local: bool, name: [:0]u8, ty: *Type) Obj {
        return Obj{
            .name = name,
            .ty = ty,
            .is_local = is_local,
            .is_function = false,
            .offset = 0,
            .init_data = "",
            .params = undefined,
            .body = undefined,
            .locals = undefined,
            .stack_size = 0,
        };
    }

    pub fn allocVar(is_local: bool, name: [:0]u8, ty: *Type) *Obj {
        var f = getAllocator().create(Obj) catch @panic("cannot allocate Var");
        f.* = Obj.initVar(is_local, name, ty);
        return f;
    }

    pub fn initFunc(name: [:0]u8, params: ArrayList(*Obj), body: *Node) Obj {
        return Obj{
            .name = name,
            .is_local = true,
            .is_fuction = true,
            .kind = .ObjFunc,
            .offset = null,
            .params = params,
            .body = body,
            .locals = ArrayList(*Obj).init(getAllocator()),
            .stack_size = 0,
        };
    }

    pub fn allocFunc(name: [:0]u8, params: ArrayList(*Obj), body: *Node) *Obj {
        var f = getAllocator().create(*Obj) catch @panic("cannot allocate Func");
        f.* = Obj.initFunc(name, params, body);
        return f;
    }
};

// ローカル変数、グローバル変数のスコープ
const VarScope = struct {
    next: ?*VarScope,
    name: [:0]u8,
    variable: *Obj,

    pub fn init(name: [:0]u8, v: *Obj) VarScope {
        return VarScope{
            .next = null,
            .name = name,
            .variable = v,
        };
    }

    pub fn allocInit(name: [:0]u8, v: *Obj) *VarScope {
        var vs = getAllocator().create(VarScope) catch @panic("cannot allocate VarScope");
        vs.* = VarScope.init(name, v);
        return vs;
    }
};

// ブロックのスコープ
const Scope = struct {
    next: ?*Scope,
    vars: ?*VarScope,

    pub fn allocInit() *Scope {
        var sc = getAllocator().create(Scope) catch @panic("cannot allocate Scope");
        sc.* = Scope{ .next = null, .vars = null };
        return sc;
    }
};

fn pushVarToScope(v: *Obj) *VarScope {
    var vs = VarScope.allocInit(v.*.name, v);
    vs.*.next = current_scope.*.vars;
    current_scope.*.vars = vs;
    return vs;
}

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
    node.*.ty = v.ty;
    return node;
}

fn newBlockNode(n: ?*Node, tok: *Token) *Node {
    var node = Node.allocInit(.NdBlock, tok);
    node.*.body = n;
    return node;
}

fn newStringLiteral(s: [:0]u8, ty: *Type) *Obj {
    var gv = newAnonGvar(ty);
    gv.init_data = s;
    return gv;
}

fn newAnonGvar(ty: *Type) *Obj {
    return newGvar(newUniqueName(), ty);
}

var unique_id: isize = -1;

fn newUniqueName() [:0]u8 {
    unique_id += 1;
    return allocPrint0(getAllocator(), ".L..{}", .{unique_id}) catch @panic("cannot allocate unique name");
}

// 引数のリストを一時的に保有するためのグローバル変数
var fn_args: ArrayList(*Obj) = undefined;
// ローカル変数のリストを一時的に保有するためのグローバル変数
var locals: ArrayList(*Obj) = undefined;
// グローバル変数のリストを一時的に保有するためのグローバル変数
var globals: ArrayList(*Obj) = undefined;
// 現在のスコープを保持するためのグローバル変数
var current_scope: *Scope = undefined;

fn newLvar(name: [:0]u8, ty: *Type) *Obj {
    var v = Obj.allocVar(true, name, ty);
    _ = pushVarToScope(v);
    locals.append(v) catch @panic("ローカル変数のパースに失敗しました");
    return v;
}

fn newGvar(name: [:0]u8, ty: *Type) *Obj {
    var v = Obj.allocVar(false, name, ty);
    _ = pushVarToScope(v);
    globals.append(v) catch @panic("グローバル変数のパースに失敗しました");
    return v;
}

fn enterScope() void {
    var sc = Scope.allocInit();
    sc.*.next = current_scope;
    current_scope = sc;
}

fn leaveScope() void {
    current_scope = current_scope.*.next.?;
}

fn findVar(token: Token) ?*Obj {
    for (locals.items) |lv| {
        if (streq(lv.*.name, token.val)) {
            return lv;
        }
    }
    for (globals.items) |gv| {
        if (streq(gv.*.name, token.val)) {
            return gv;
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

// program = (function-definition | global-variable)*
pub fn parse(tokens: []Token, ti: *usize) !ArrayList(*Obj) {
    Type.initGlobals();
    globals = ArrayList(*Obj).init(getAllocator());
    current_scope = Scope.allocInit();
    while (ti.* < tokens.len) {
        const basety = declspec(tokens, ti);
        if (isFunction(tokens, ti)) {
            _ = function(tokens, ti, basety);
        } else {
            globalVariable(tokens, ti, basety);
        }
    }
    return globals;
}

fn isFunction(tokens: []Token, ti: *usize) bool {
    const tok = &tokens[ti.*];
    const original_ti = ti.*;
    if (streq(tok.*.val, ";"))
        return false;

    const ty = declarator(tokens, ti, Type.typeInt());
    ti.* = original_ti;
    return ty.*.kind == TypeKind.TyFunc;
}

// function = declarator ident { compound_stmt }
fn function(tokens: []Token, ti: *usize, basety: *Type) *Obj {
    locals = ArrayList(*Obj).init(getAllocator());
    const ty = declarator(tokens, ti, basety);

    enterScope();

    createParamLvars(ty.*.params);
    var params = ArrayList(*Obj).init(getAllocator());
    for (locals.items) |lc| {
        params.append(lc) catch @panic("cannot append params");
    }

    skip(tokens, ti, "{");
    var f = newGvar(ty.*.name.?.*.val, ty);
    f.*.is_function = true;
    f.*.params = params;
    f.*.body = compoundStmt(tokens, ti);
    f.*.locals = locals;

    leaveScope();

    return f;
}

fn globalVariable(tokens: []Token, ti: *usize, basety: *Type) void {
    var first = true;

    while (!consumeTokVal(tokens, ti, ";")) {
        if (!first)
            skip(tokens, ti, ",");
        first = false;

        const ty = declarator(tokens, ti, basety);
        _ = newGvar(ty.*.name.?.*.val, ty);
    }
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

    enterScope();

    while (ti.* < tokens.len) {
        if (consumeTokVal(tokens, ti, "}")) {
            end = true;
            break;
        }
        if (isTypeName(tokens, ti)) {
            cur.*.next = declaration(tokens, ti);
        } else {
            cur.*.next = stmt(tokens, ti);
        }
        cur = cur.*.next.?;
        addType(cur);
    }

    leaveScope();

    if (!end) {
        errorAtToken(&tokens[tokens.len - 1], " } がありません");
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
        errorAtToken(&tokens[tokens.len - 1], "Unexpected EOF");
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
        var variable = newLvar(ty.*.name.?.*.val, ty);

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

// declarator = "*"* ident type-suffix
fn declarator(tokens: []Token, ti: *usize, typ: *Type) *Type {
    var ty = typ;
    while (consumeTokVal(tokens, ti, "*"))
        ty = Type.pointerTo(ty);

    var tok = &tokens[ti.*];
    if (tok.*.kind != .TkIdent)
        errorAtToken(tok, "expected a variable name");

    ti.* += 1;
    ty = typeSuffix(tokens, ti, ty);
    ty.*.name = tok;
    return ty;
}

// declspec = "char" | "int"
fn declspec(tokens: []Token, ti: *usize) *Type {
    if (consumeTokVal(tokens, ti, "char")) {
        return Type.typeChar();
    }

    skip(tokens, ti, "int");
    return Type.typeInt();
}

// type-suffix = "(" func-params
//             | "[" num "]" type-suffix
//             | ε
fn typeSuffix(tokens: []Token, ti: *usize, ty: *Type) *Type {
    if (consumeTokVal(tokens, ti, "("))
        return funcParams(tokens, ti, ty);
    if (consumeTokVal(tokens, ti, "[")) {
        var sz = getNumber(tokens, ti);
        skip(tokens, ti, "]");
        return Type.arrayOf(typeSuffix(tokens, ti, ty), @intCast(usize, sz));
    }

    return ty;
}

// func-params = (param ("," param)*)? ")"
// param       = declspec declarator
fn funcParams(tokens: []Token, ti: *usize, ty: *Type) *Type {
    var head = Type.init(TypeKind.TyInt);
    var cur = &head;

    while (!consumeTokVal(tokens, ti, ")")) {
        if (cur != &head)
            skip(tokens, ti, ",");
        var basety = declspec(tokens, ti);
        cur.*.next = declarator(tokens, ti, basety);
        cur = cur.*.next.?;
    }

    var tp = Type.funcType(ty);
    tp.*.params = head.next;
    return tp;
}

// expr = assign ("," expr)?
pub fn expr(tokens: []Token, ti: *usize) *Node {
    var node = assign(tokens, ti);
    if (consumeTokVal(tokens, ti, ","))
        return newBinary(.NdComma, node, expr(tokens, ti), &tokens[ti.* - 1]);
    return node;
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
//       | postfix
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
    return postfix(tokens, ti);
}

// postfix = primary ("[" expr "]")*
fn postfix(tokens: []Token, ti: *usize) *Node {
    var node = primary(tokens, ti);

    while (consumeTokVal(tokens, ti, "[")) {
        var start = &tokens[ti.* - 1];
        var idx = expr(tokens, ti);
        skip(tokens, ti, "]");
        node = newUnary(.NdDeref, newAdd(node, idx, start), start);
    }

    return node;
}

// primary = "(" "{" stmt+ "}" ")"
//         | "(" expr ")"
//         | "sizeof" unary
//         | ident func-args?
//         | str
//         | num
fn primary(tokens: []Token, ti: *usize) *Node {
    var token = tokens[ti.*];
    if (streq(token.val, "(") and ti.* + 1 < tokens.len and streq(tokens[ti.* + 1].val, "{")) {
        // This is a GNU statement expression
        var node = Node.allocInit(.NdStmtExpr, &tokens[ti.*]);
        ti.* += 2;
        node.*.body = compoundStmt(tokens, ti).*.body;
        skip(tokens, ti, ")");
        return node;
    }
    if (streq(token.val, "(")) {
        ti.* += 1;
        const node = expr(tokens, ti);
        skip(tokens, ti, ")");
        return node;
    }

    if (consumeTokVal(tokens, ti, "sizeof")) {
        const tok = &tokens[ti.*];
        var node = unary(tokens, ti);
        addType(node);
        const sizeStr = allocPrint0(getAllocator(), "{}", .{node.*.ty.?.*.size}) catch @panic("cannot allocate sizeof");
        return newNum(sizeStr, tok);
    }

    if (token.kind == TokenKind.TkIdent) {
        // 関数呼出のとき
        if (ti.* + 1 < tokens.len and consumeTokVal(tokens, &(ti.* + 1), "(")) {
            return funcall(tokens, ti);
        }
        // 変数
        var v = findVar(token);
        if (v == null) {
            errorAtToken(&token, "変数が未定義です");
        }
        ti.* += 1;
        return newVarNode(v.?, getOrLast(tokens, ti));
    }

    if (token.kind == TokenKind.TkStr) {
        const tok = getOrLast(tokens, ti);
        ti.* += 1;
        return newVarNode(newStringLiteral(tok.*.val, tok.*.ty.?), tok);
    }

    if (token.kind == TokenKind.TkNum) {
        ti.* += 1;
        return newNum(token.val, getOrLast(tokens, ti));
    }

    errorAtToken(&token, "expected an expression");
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
        errorAt(tokens.len, null, "予期せず入力が終了しました。最後に ; を入力してください。");
    }
    var token = tokens[ti.*];
    if (streq(token.val, s)) {
        ti.* += 1;
    } else {
        const string = allocPrint0(getAllocator(), "期待した文字列 {} がありません", .{s}) catch "期待した文字列がありません";
        errorAtToken(&token, string);
    }
}

fn getNumber(tokens: []Token, ti: *usize) i32 {
    if (tokens.len <= ti.*) {
        errorAt(ti.*, null, "数値ではありません");
    }
    var tok = tokens[ti.*];
    if (tok.kind != TokenKind.TkNum)
        errorAtToken(&tok, "数値ではありません");
    ti.* += 1;
    return atoi(tok.val);
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
        errorAtToken(tok, "invalid operands");

    var l = lhs;
    var r = rhs;

    // num + ptrを ptr + numにそろえる
    if (lhs.*.ty.?.*.base == null and rhs.*.ty.?.*.base != null) {
        l = rhs;
        r = lhs;
    }

    // ptr + num
    const num = allocPrint0(getAllocator(), "{}", .{l.*.ty.?.*.base.?.*.size}) catch @panic("cannot allocate newNum");
    r = newBinary(.NdMul, r, newNum(num, tok), tok);
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
        node.*.ty = Type.typeInt();
        const num = allocPrint0(getAllocator(), "{}", .{lhs.*.ty.?.*.base.?.*.size}) catch @panic("cannot allocate newNum");
        return newBinary(.NdDiv, node, newNum(num, tok), tok);
    }

    // ptr - num
    if (lhs.*.ty.?.*.base != null and rhs.*.ty.?.*.base == null) {
        const num = allocPrint0(getAllocator(), "{}", .{lhs.*.ty.?.*.base.?.*.size}) catch @panic("cannot allocate newNum");
        var r = newBinary(.NdMul, rhs, newNum(num, tok), tok);
        addType(r);
        var n = newBinary(.NdSub, lhs, r, tok);
        n.*.ty = lhs.*.ty;
        return n;
    }

    errorAtToken(tok, "Invalid operands");
}

fn createParamLvars(param: ?*Type) void {
    if (param == null) {
        return;
    }
    const prm = param.?;
    createParamLvars(prm.*.next);
    _ = newLvar(prm.*.name.?.*.val, prm);
}

fn isTypeName(tokens: []Token, ti: *usize) bool {
    if (tokens.len <= ti.*) {
        errorAt(ti.*, null, "Unexpected EOF");
    }
    const tok = tokens[ti.*];
    return streq(tok.val, "int") or streq(tok.val, "char");
}
