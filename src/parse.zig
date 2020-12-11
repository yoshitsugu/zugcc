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
const copyType = typezig.copyType;
const addType = typezig.addType;
const alignToI32 = @import("codegen.zig").alignTo;

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
    NdMember, // . (struct member access)
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
    NdCast, // Type Cast
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

    // Structのメンバ
    member: ?*Member,

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
            .member = null,
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

pub const Member = struct {
    next: ?*Member,
    ty: ?*Type,
    name: *Token,
    offset: usize,

    pub fn init(name: *Token) Member {
        return Member{
            .next = null,
            .ty = null,
            .name = name,
            .offset = 0,
        };
    }

    pub fn allocInit(name: *Token) *Member {
        var m = getAllocator().create(Member) catch @panic("cannot allocate Member");
        m.* = Member.init(name);
        return m;
    }
};

// 変数 or 関数
pub const Obj = struct {
    name: [:0]u8,
    ty: ?*Type,
    is_local: bool,
    is_function: bool,
    is_definition: bool,

    // ローカル変数のとき
    offset: i32, // RBPからのオフセット

    // グローバル変数のとき
    init_data: [:0]u8,

    // 関数のとき
    params: ?ArrayList(*Obj),
    body: *Node, // 関数の開始ノード
    locals: ?ArrayList(*Obj),
    stack_size: i32,

    pub fn initVar(is_local: bool, name: [:0]u8, ty: *Type) Obj {
        return Obj{
            .name = name,
            .ty = ty,
            .is_local = is_local,
            .is_function = false,
            .is_definition = false,
            .offset = 0,
            .init_data = "",
            .params = null,
            .body = undefined,
            .locals = null,
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

// ローカル変数、グローバル変数, typedefのスコープ
const VarScope = struct {
    next: ?*VarScope,
    name: [:0]u8,
    variable: ?*Obj,
    type_def: ?*Type,

    pub fn init(name: [:0]u8) VarScope {
        return VarScope{
            .next = null,
            .name = name,
            .variable = null,
            .type_def = null,
        };
    }

    pub fn allocInit(name: [:0]u8) *VarScope {
        var vs = getAllocator().create(VarScope) catch @panic("cannot allocate VarScope");
        vs.* = VarScope.init(name);
        return vs;
    }
};

// typedef や externで使う変数の属性
const VarAttr = struct {
    is_typedef: bool,

    pub fn init() VarAttr {
        return VarAttr{ .is_typedef = false };
    }

    pub fn allocInit() *VarAttr {
        var vs = getAllocator().create(VarAttr) catch @panic("cannot allocate VarAttr");
        vs.* = VarAttr.init();
        return vs;
    }
};

// 構造体、ユニオンのタグ名のスコープ
const TagScope = struct {
    next: ?*TagScope,
    name: [:0]u8,
    ty: ?*Type,

    pub fn init(name: [:0]u8) TagScope {
        return TagScope{
            .next = null,
            .name = name,
            .ty = null,
        };
    }

    pub fn allocInit(name: [:0]u8) *TagScope {
        var s = getAllocator().create(TagScope) catch @panic("cannot allocate TagScope");
        s.* = TagScope.init(name);
        return s;
    }
};

// ブロックのスコープ
const Scope = struct {
    next: ?*Scope,
    vars: ?*VarScope,
    tags: ?*TagScope,

    pub fn allocInit() *Scope {
        var sc = getAllocator().create(Scope) catch @panic("cannot allocate Scope");
        sc.* = Scope{ .next = null, .vars = null, .tags = null };
        return sc;
    }
};

fn pushScope(name: [:0]u8) *VarScope {
    var vs = VarScope.allocInit(name);
    vs.*.next = current_scope.*.vars;
    current_scope.*.vars = vs;
    return vs;
}

fn pushTagScope(tok: *Token, ty: *Type) void {
    var ts = TagScope.allocInit(tok.*.val);
    ts.*.ty = ty;
    ts.*.next = current_scope.*.tags;
    current_scope.*.tags = ts;
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

fn newCast(e: *Node, ty: *Type) *Node {
    addType(e);

    var node = Node.allocInit(.NdCast, e.*.tok);
    node.*.lhs = e;
    node.*.ty = copyType(ty);
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
    var sc = pushScope(name);
    sc.*.variable = v;
    locals.append(v) catch @panic("ローカル変数のパースに失敗しました");
    return v;
}

fn newGvar(name: [:0]u8, ty: *Type) *Obj {
    var v = Obj.allocVar(false, name, ty);
    var sc = pushScope(name);
    sc.*.variable = v;
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

fn findVar(token: Token) ?*VarScope {
    var sc: ?*Scope = current_scope;
    while (sc != null) : (sc = sc.?.*.next) {
        var sv = sc.?.*.vars;
        while (sv != null) : (sv = sv.?.*.next) {
            if (streq(token.val, sv.?.*.name)) {
                return sv;
            }
        }
    }
    return null;
}

fn findTag(token: *Token) ?*Type {
    var s: ?*Scope = current_scope;
    while (s != null) : (s = s.?.*.next) {
        var t = s.?.*.tags;
        while (t != null) : (t = t.?.*.next) {
            if (streq(token.*.val, t.?.*.name))
                return t.?.*.ty;
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

fn findTypedef(tokens: []Token, ti: *usize) ?*Type {
    if (ti.* >= tokens.len) {
        errorAtToken(getOrLast(tokens, ti), "Unexpected EOF");
    }
    const token = tokens[ti.*];
    if (token.kind == TokenKind.TkIdent) {
        var sc = findVar(token);
        if (sc != null)
            return sc.?.*.type_def;
    }
    return null;
}

fn parseTypedef(tokens: []Token, ti: *usize, basety: *Type) void {
    var first = true;
    while (!consumeTokVal(tokens, ti, ";")) {
        if (!first)
            skip(tokens, ti, ",");
        first = false;

        var ty = declarator(tokens, ti, basety);
        pushScope(ty.*.name.?.*.val).*.type_def = ty;
    }
}

// program = (typedef | function-definition | global-variable)*
pub fn parse(tokens: []Token, ti: *usize) !ArrayList(*Obj) {
    Type.initGlobals();
    globals = ArrayList(*Obj).init(getAllocator());
    current_scope = Scope.allocInit();
    while (ti.* < tokens.len) {
        var attr = VarAttr.init();
        const basety = declspec(tokens, ti, &attr);

        // Typedef
        if (attr.is_typedef) {
            parseTypedef(tokens, ti, basety);
            continue;
        }

        if (isFunction(tokens, ti)) {
            function(tokens, ti, basety);
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
fn function(tokens: []Token, ti: *usize, basety: *Type) void {
    locals = ArrayList(*Obj).init(getAllocator());
    const ty = declarator(tokens, ti, basety);
    const is_definition = !consumeTokVal(tokens, ti, ";");
    var f = newGvar(ty.*.name.?.*.val, ty);
    f.*.is_function = true;
    f.*.is_definition = is_definition;
    if (!f.*.is_definition) {
        return;
    }

    enterScope();

    createParamLvars(ty.*.params);
    var params = ArrayList(*Obj).init(getAllocator());
    for (locals.items) |lc| {
        params.append(lc) catch @panic("cannot append params");
    }
    f.*.params = params;
    skip(tokens, ti, "{");
    f.*.body = compoundStmt(tokens, ti);
    f.*.locals = locals;

    leaveScope();
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
            var attr = VarAttr.init();
            var basety = declspec(tokens, ti, &attr);

            if (attr.is_typedef) {
                parseTypedef(tokens, ti, basety);
                continue;
            }
            cur.*.next = declaration(tokens, ti, basety);
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
fn declaration(tokens: []Token, ti: *usize, basety: *Type) *Node {
    if (tokens.len <= ti.*) {
        errorAtToken(&tokens[tokens.len - 1], "Unexpected EOF");
    }
    var token = &tokens[ti.*];

    var head = Node.init(.NdNum, token);
    var cur = &head;
    var first: bool = true;

    while (ti.* < tokens.len and !consumeTokVal(tokens, ti, ";")) {
        if (!first) {
            skip(tokens, ti, ",");
        } else {
            first = false;
        }

        var ty = declarator(tokens, ti, basety);
        if (ty.*.kind == TypeKind.TyVoid) {
            errorAtToken(&tokens[ti.*], "変数がvoidとして宣言されています");
        }
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

// declarator = "*"* ("(" ident ")" | "(" declarator ")" | ident) type-suffix
fn declarator(tokens: []Token, ti: *usize, typ: *Type) *Type {
    var ty = typ;
    while (consumeTokVal(tokens, ti, "*")) {
        ty = Type.pointerTo(ty);
    }

    if (consumeTokVal(tokens, ti, "(")) {
        const start = ti.*;
        while (!consumeTokVal(tokens, ti, ")")) {
            ti.* += 1;
        }
        ty = typeSuffix(tokens, ti, ty);
        const end = ti.*;
        ti.* = start;
        ty = declarator(tokens, ti, ty);
        ti.* = end;
        return ty;
    }
    var tok = &tokens[ti.*];
    if (tok.*.kind != .TkIdent) {
        errorAtToken(tok, "expected a variable name");
    }

    ti.* += 1;
    ty = typeSuffix(tokens, ti, ty);
    ty.*.name = tok;
    return ty;
}

// declspec = ("void" | "char" | "short" | "int" | "long"
//             | "typedef"
//             | struct-decl | union-decl | typedef-name)+
//
// The order of typenames in a type-specifier doesn't matter. For
// example, `int long static` means the same as `static long int`.
// That can also be written as `static long` because you can omit
// `int` if `long` or `short` are specified. However, something like
// `char int` is not a valid type specifier. We have to accept only a
// limited combinations of the typenames.
//
// In this function, we count the number of occurrences of each typename
// while keeping the "current" type object that the typenames up
// until that point represent. When we reach a non-typename token,
// we returns the current type object.
fn declspec(tokens: []Token, ti: *usize, attr: ?*VarAttr) *Type {
    // We use a single integer as counters for all typenames.
    // For example, bits 0 and 1 represents how many times we saw the
    // keyword "void" so far. With this, we can use a switch statement
    // as you can see below.
    const TypeMax = enum(usize) {
        Void = 1 << 0,
        Char = 1 << 2,
        Short = 1 << 4,
        Int = 1 << 6,
        Long = 1 << 8,
        Other = 1 << 10,
    };

    var ty = Type.typeInt();
    var counter: usize = 0;

    while (isTypeName(tokens, ti)) {
        if (consumeTokVal(tokens, ti, "typedef")) {
            if (attr == null)
                errorAtToken(getOrLast(tokens, ti), "不正なストレージクラス指定子です");
            attr.?.*.is_typedef = true;
            continue;
        }

        var ty2 = findTypedef(tokens, ti);
        var typeMaxOther = false;
        var token = getOrLast(tokens, ti);
        if (streq(token.val, "struct") or
            streq(token.val, "union") or
            ty2 != null)
        {
            if (counter > 0) {
                break;
            }
            if (consumeTokVal(tokens, ti, "struct")) {
                ty = structDecl(tokens, ti);
            } else if (consumeTokVal(tokens, ti, "union")) {
                ty = unionDecl(tokens, ti);
            } else {
                ty = ty2.?;
                ti.* += 1;
            }
            counter += @enumToInt(TypeMax.Other);
            continue;
        }

        if (consumeTokVal(tokens, ti, "void")) {
            counter += @enumToInt(TypeMax.Void);
        } else if (consumeTokVal(tokens, ti, "char")) {
            counter += @enumToInt(TypeMax.Char);
        } else if (consumeTokVal(tokens, ti, "short")) {
            counter += @enumToInt(TypeMax.Short);
        } else if (consumeTokVal(tokens, ti, "int")) {
            counter += @enumToInt(TypeMax.Int);
        } else if (consumeTokVal(tokens, ti, "long")) {
            counter += @enumToInt(TypeMax.Long);
        } else {
            unreachable;
        }

        switch (counter) {
            @enumToInt(TypeMax.Void) => ty = Type.typeVoid(),
            @enumToInt(TypeMax.Char) => ty = Type.typeChar(),
            @enumToInt(TypeMax.Short), @enumToInt(TypeMax.Short) + @enumToInt(TypeMax.Int) => ty = Type.typeShort(),
            @enumToInt(TypeMax.Int) => ty = Type.typeInt(),
            @enumToInt(TypeMax.Long),
            @enumToInt(TypeMax.Long) + @enumToInt(TypeMax.Int),
            @enumToInt(TypeMax.Long) + @enumToInt(TypeMax.Long),
            @enumToInt(TypeMax.Long) + @enumToInt(TypeMax.Long) + @enumToInt(TypeMax.Int),
            => ty = Type.typeLong(),
            else => errorAtToken(getOrLast(tokens, ti), "不正な型名です"),
        }
    }

    return ty;
}

// struct-union-decl = ident? ("{" struct-members)?
fn structUnionDecl(tokens: []Token, ti: *usize, typeKind: TypeKind) *Type {
    var tok = getOrLast(tokens, ti);

    // 構造体タグ名を読む
    var tag: ?*Token = null;
    if (tok.*.kind == TokenKind.TkIdent) {
        tag = tok;
        ti.* += 1;
    }

    if (!consumeTokVal(tokens, ti, "{") and tag != null) {
        var tyTag = findTag(tag.?);
        if (tyTag == null)
            errorAtToken(&tokens[ti.*], "Unknown struct type");
        return tyTag.?;
    }

    // construct struct object
    var ty = Type.allocInit(typeKind);
    structMembers(tokens, ti, ty);
    ty.*.alignment = 1;

    if (tag != null)
        pushTagScope(tag.?, ty);

    return ty;
}

// struct-decl = struct-union-decl
fn structDecl(tokens: []Token, ti: *usize) *Type {
    var ty = structUnionDecl(tokens, ti, .TyStruct);

    // Assign offsets within the struct tomembers
    var offset: usize = 0;
    var m = ty.*.members;
    while (m != null) : (m = m.?.*.next) {
        offset = alignTo(offset, m.?.*.ty.?.*.alignment);
        m.?.*.offset = offset;
        offset += m.?.*.ty.?.*.size;

        if (ty.*.alignment < m.?.*.ty.?.*.alignment)
            ty.*.alignment = m.?.*.ty.?.*.alignment;
    }
    ty.*.size = alignTo(offset, ty.*.alignment);
    return ty;
}

// union-decl = struct-union-decl
fn unionDecl(tokens: []Token, ti: *usize) *Type {
    var ty = structUnionDecl(tokens, ti, .TyUnion);

    // If union, we don't have to assign offsets because they
    // are already initialized to zero. We need to compute the
    // alignment and the size though.
    var m = ty.*.members;
    while (m != null) : (m = m.?.*.next) {
        if (ty.*.alignment < m.?.*.ty.?.*.alignment)
            ty.*.alignment = m.?.*.ty.?.*.alignment;
        if (ty.*.size < m.?.*.ty.?.*.size)
            ty.*.size = m.?.*.ty.?.*.size;
    }
    ty.*.size = alignTo(ty.*.size, ty.*.alignment);
    return ty;
}

// struct-members = (declspec declarator (","  declarator)* ";")*
fn structMembers(tokens: []Token, ti: *usize, ty: *Type) void {
    var head = Member.init(&tokens[ti.*]);
    var cur: *Member = &head;

    while (!consumeTokVal(tokens, ti, "}")) {
        var basety = declspec(tokens, ti, null);
        var first: bool = true;

        while (!consumeTokVal(tokens, ti, ";")) {
            if (!first)
                skip(tokens, ti, ",");
            first = false;

            var t = declarator(tokens, ti, basety);
            var m = Member.allocInit(t.*.name.?);
            m.ty = t;
            cur.*.next = m;
            cur = cur.*.next.?;
        }
    }

    ty.*.members = head.next;
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
        var basety = declspec(tokens, ti, null);
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

// mul = cast ("*" cast | "/" cast)*
pub fn mul(tokens: []Token, ti: *usize) *Node {
    var node = cast(tokens, ti);

    while (ti.* < tokens.len) {
        const token = tokens[ti.*];
        if (streq(token.val, "*")) {
            ti.* += 1;
            node = newBinary(.NdMul, node, cast(tokens, ti), getOrLast(tokens, ti));
        } else if (streq(token.val, "/")) {
            ti.* += 1;
            node = newBinary(.NdDiv, node, cast(tokens, ti), getOrLast(tokens, ti));
        } else {
            break;
        }
    }
    return node;
}

// cast = "(" type-name ")" cast | unary
fn cast(tokens: []Token, ti: *usize) *Node {
    if (consumeTokVal(tokens, ti, "(")) {
        if (isTypeName(tokens, ti)) {
            var start = ti.* - 1;
            var ty = typename(tokens, ti);
            skip(tokens, ti, ")");
            var node = newCast(cast(tokens, ti), ty);
            node.*.tok = &tokens[start];
            return node;
        } else {
            ti.* -= 1;
        }
    }

    return unary(tokens, ti);
}

// unary = ("+" | "-" | "*" | "&") cast
//       | postfix
fn unary(tokens: []Token, ti: *usize) *Node {
    const token = tokens[ti.*];
    if (consumeTokVal(tokens, ti, "+")) {
        return cast(tokens, ti);
    }
    if (consumeTokVal(tokens, ti, "-")) {
        return newUnary(.NdNeg, cast(tokens, ti), getOrLast(tokens, ti));
    }
    if (consumeTokVal(tokens, ti, "&")) {
        return newUnary(.NdAddr, cast(tokens, ti), getOrLast(tokens, ti));
    }
    if (consumeTokVal(tokens, ti, "*")) {
        return newUnary(.NdDeref, cast(tokens, ti), getOrLast(tokens, ti));
    }
    return postfix(tokens, ti);
}

// postfix = primary ("[" expr "]" | "." ident | "->" ident)*
fn postfix(tokens: []Token, ti: *usize) *Node {
    var node = primary(tokens, ti);

    while (true) {
        if (consumeTokVal(tokens, ti, "[")) {
            var start = &tokens[ti.* - 1];
            var idx = expr(tokens, ti);
            skip(tokens, ti, "]");
            node = newUnary(.NdDeref, newAdd(node, idx, start), start);
            continue;
        }
        if (consumeTokVal(tokens, ti, ".")) {
            node = structRef(tokens, ti, node);
            ti.* += 1;
            continue;
        }
        if (consumeTokVal(tokens, ti, "->")) {
            node = newUnary(.NdDeref, node, getOrLast(tokens, ti));
            node = structRef(tokens, ti, node);
            ti.* += 1;
            continue;
        }
        return node;
    }
}

fn structRef(tokens: []Token, ti: *usize, lhs: *Node) *Node {
    addType(lhs);
    if (lhs.*.ty.?.*.kind != TypeKind.TyStruct and lhs.*.ty.?.*.kind != TypeKind.TyUnion)
        errorAtToken(lhs.*.tok, "構造体でもユニオンでもありません");

    var node = newUnary(.NdMember, lhs, getOrLast(tokens, ti));
    node.*.member = getStructMember(tokens, ti, lhs.*.ty.?);
    return node;
}

fn getStructMember(tokens: []Token, ti: *usize, ty: *Type) *Member {
    var m = ty.*.members;
    var tok = &tokens[ti.*];
    while (m != null) : (m = m.?.*.next) {
        if (streq(m.?.*.name.*.val, tok.*.val))
            return m.?;
    }
    errorAtToken(tok, "no such member");
}

// primary = "(" "{" stmt+ "}" ")"
//         | "(" expr ")"
//         | "sizeof" "(" type-name ")"
//         | "sizeof" unary
//         | ident func-args?
//         | str
//         | num
fn primary(tokens: []Token, ti: *usize) *Node {
    const start = ti.*;
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

    var t2: usize = ti.*;
    var ti2 = &t2;
    if (consumeTokVal(tokens, ti2, "sizeof") and
        consumeTokVal(tokens, ti2, "(") and
        isTypeName(tokens, ti2))
    {
        var ty = typename(tokens, ti2);
        skip(tokens, ti2, ")");
        ti.* = ti2.*;
        const sizeStr = allocPrint0(getAllocator(), "{}", .{ty.*.size}) catch @panic("cannot allocate string for size");
        return newNum(sizeStr, &tokens[start]);
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
        var sc = findVar(token);
        if (sc == null or sc.?.*.variable == null) {
            errorAtToken(&token, "変数が未定義です");
        }
        ti.* += 1;
        return newVarNode(sc.?.*.variable.?, getOrLast(tokens, ti));
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

fn typename(tokens: []Token, ti: *usize) *Type {
    var ty = declspec(tokens, ti, null);
    return abstractDeclarator(tokens, ti, ty);
}

// abstract-declarator = "*"* ("(" abstract-declarator ")")? type-suffix
fn abstractDeclarator(tokens: []Token, ti: *usize, basety: *Type) *Type {
    var ty = basety;
    while (consumeTokVal(tokens, ti, "*")) {
        ty = Type.pointerTo(ty);
    }

    if (consumeTokVal(tokens, ti, "(")) {
        var start = ti.*;
        var ignore = Type.typeInt();
        _ = abstractDeclarator(tokens, ti, ignore);
        skip(tokens, ti, ")");
        ty = typeSuffix(tokens, ti, ty);
        return abstractDeclarator(tokens, &start, ty);
    }

    return typeSuffix(tokens, ti, ty);
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
    var types = [_][:0]const u8{ "void", "char", "int", "short", "long", "struct", "union", "typedef" };
    for (types) |t| {
        if (streq(tok.val, t)) {
            return true;
        }
    }
    return findTypedef(tokens, ti) != null;
}

fn alignTo(n: usize, a: usize) usize {
    return @intCast(usize, alignToI32(@intCast(i32, n), @intCast(i32, a)));
}
