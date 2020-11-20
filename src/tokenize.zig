const std = @import("std");
const fs = std.fs;
const ArrayList = std.ArrayList;
const ArrayListSentineled = std.ArrayListSentineled;
const allocPrint0 = std.fmt.allocPrint0;
const err = @import("error.zig");
const errorAt = err.errorAt;
const setTargetString = err.setTargetString;
const setTargetFilename = err.setTargetFilename;
const allocator = @import("allocator.zig");
const getAllocator = allocator.getAllocator;
const stdout = std.io.getStdOut().outStream();
const print = stdout.print;
const Type = @import("type.zig").Type;

const SPACE_CHARS = " \n\t\x0b\x0c\r";
const PUNCT_CHARS = "+-*/()<>;={}&,[].";
const PUNCT_STRS = [_][:0]const u8{ "==", "!=", "<=", ">=", "->" };
const KEYWORDS = [_][:0]const u8{ "return", "if", "else", "for", "while", "sizeof", "char", "int", "struct" };

pub const TokenKind = enum {
    TkIdent, // 識別子
    TkPunct, // 区切り記号
    TkKeyword, // キーワード
    TkStr, // 文字列
    TkNum, // 数値
};

pub const Token = struct {
    kind: TokenKind, // トークン種別
    val: [:0]u8, // トークン文字列
    loc: usize, // 元の文字列上の場所
    ty: ?*Type, // 文字列のときに使う
    line_no: usize, // 元ファイルの行数
};

pub fn newToken(kind: TokenKind, val: []const u8, loc: usize, str: [:0]u8) !Token {
    return Token{
        .kind = kind,
        .val = try allocPrint0(getAllocator(), "{}", .{val}),
        .loc = loc,
        .ty = null,
        .line_no = getLineNo(str, loc),
    };
}

pub fn tokenize(filename: [:0]u8, str: [:0]u8) !ArrayList(Token) {
    setTargetFilename(filename);
    setTargetString(str);

    var tokens = ArrayList(Token).init(getAllocator());
    var i: usize = 0;
    while (str[i] != 0) {
        const c = str[i];
        if (startsWith(str, i, "//")) {
            i += 2;
            while (str[i] != '\n')
                i += 1;
            continue;
        }
        if (startsWith(str, i, "/*")) {
            i += 2;
            while (!startsWith(str, i, "*/")) {
                i += 1;
                if (i >= str.len)
                    errorAt(i, null, "コメントが閉じられていません");
            }
            i += 2;
            continue;
        }
        if (isSpace(c)) {
            i += 1;
            continue;
        }
        if (isNumber(c)) {
            const h = i;
            i = expectNumber(str, i);
            const num = try newToken(.TkNum, str[h..i], i, str);
            try tokens.append(num);
            continue;
        }
        if (c == '"') {
            const tok = try readStringLiteral(tokens, str, &i);
            try tokens.append(tok.*);
            continue;
        }
        if (isIdentHead(c)) {
            const h = i;
            i = readIdent(str, i);
            var tk = try newToken(.TkIdent, str[h..i], i, str);
            if (isKeyword(str, h, i)) {
                tk = try newToken(.TkKeyword, str[h..i], i, str);
            }
            try tokens.append(tk);
            continue;
        }
        const puncts_end = readPuncts(str, i);
        if (puncts_end > i) {
            const punct = try newToken(.TkPunct, str[i..puncts_end], i, str);
            try tokens.append(punct);
            i = puncts_end;
            continue;
        }
        if (isPunct(c)) {
            const punct = try newToken(.TkPunct, str[i .. i + 1], i, str);
            try tokens.append(punct);
            i += 1;
            continue;
        }
        errorAt(i, null, "トークナイズできませんでした");
    }
    return tokens;
}

fn isNumber(c: u8) bool {
    return '0' <= c and c <= '9';
}

fn isSpace(c: u8) bool {
    for (SPACE_CHARS) |k| {
        if (c == k) {
            return true;
        }
    }
    return false;
}

fn isPunct(c: u8) bool {
    for (PUNCT_CHARS) |k| {
        if (c == k) {
            return true;
        }
    }
    return false;
}

fn isIdentHead(c: u8) bool {
    return ('a' <= c and c <= 'z') or ('A' <= c and c <= 'Z') or c == '_';
}

fn isIdentTail(c: u8) bool {
    return isIdentHead(c) or ('0' <= c and c <= '9');
}

fn readIdent(str: [*:0]const u8, i: usize) usize {
    if (str[i] == 0 or !isIdentHead(str[i])) {
        return i;
    }
    var h = i + 1;
    while (str[h] != 0 and isIdentTail(str[h])) {
        h += 1;
    }
    return h;
}

fn isKeyword(str: [*:0]const u8, startIndex: usize, endIndex: usize) bool {
    const pstr = allocPrint0(getAllocator(), "{}", .{str[startIndex..endIndex]}) catch "";
    for (KEYWORDS) |kwd| {
        if (streq(kwd, pstr)) {
            return true;
        }
    }
    return false;
}

fn readPuncts(str: [*:0]const u8, i: usize) usize {
    for (PUNCT_STRS) |pstr| {
        const cut_str = allocPrint0(getAllocator(), "{}", .{str[i .. i + pstr.len]}) catch "";
        if (streq(cut_str, pstr)) {
            return i + pstr.len;
        }
    }
    return i;
}

fn expectNumber(ptr: [*:0]const u8, index: usize) usize {
    if (isNumber(ptr[index])) {
        return consumeNumber(ptr, index);
    } else {
        errorAt(index, null, "数値ではありません");
    }
}

fn consumeNumber(ptr: [*:0]const u8, index: usize) usize {
    var end = index;
    while (isNumber(ptr[end])) {
        end += 1;
    }
    return end;
}

pub fn streq(a: [:0]const u8, b: [:0]const u8) bool {
    return std.mem.eql(u8, a, b);
}

fn startsWith(str: [:0]u8, i: usize, target: [:0]const u8) bool {
    if (target.len > str.len)
        return false;
    var j: usize = 0;
    while (j + i + target.len < str.len and j < target.len) : (j += 1) {
        if (str[i + j] != target[j])
            return false;
    }
    return j == target.len;
}

pub fn atoi(s: [:0]u8) i32 {
    var n: i32 = 0;
    var neg = false;
    var si: usize = 0;
    if (s.len == 0)
        return n;
    while (si < s.len and isSpace(s[si]))
        si += 1;
    switch (s[si]) {
        '-' => {
            neg = true;
            si += 1;
        },
        '+' => si += 1,
        else => {},
    }
    while (si < s.len and isNumber(s[si])) : (si += 1) {
        n = 10 * n - (@intCast(i32, s[si]) - '0');
    }
    if (neg) {
        return n;
    } else {
        return (-1 * n);
    }
}

fn stringLiteralEnd(str: [*:0]const u8, index: usize) usize {
    var h = index;
    var c = str[h];
    while (c != '"') : (c = str[h]) {
        const cs = [_:0]u8{c};
        if (c == '\n' or c == 0)
            errorAt(index, null, "文字列リテラルが閉じられていません");
        if (c == '\\') {
            h += 2;
        } else {
            h += 1;
        }
    }
    return h;
}

fn readStringLiteral(tokens: ArrayList(Token), str: [:0]u8, index: *usize) !*Token {
    const start = index.*;
    const end = stringLiteralEnd(str, start + 1);
    var buf: []u8 = try getAllocator().alloc(u8, end - start);
    var len: usize = 0;
    var i = start + 1;
    while (i < end) {
        if (str[i] == '\\') {
            var j = i + 1;
            buf[len] = readEscapedChar(str, &j);
            i = j;
        } else {
            buf[len] = str[i];
            i += 1;
        }
        len += 1;
    }
    index.* = end + 1;
    const tokenVal = try allocPrint0(getAllocator(), "{}", .{buf[0..len]});
    var tok = try getAllocator().create(Token);
    tok.* = try newToken(.TkStr, tokenVal, i, str);
    // 文字列は終端文字の都合上、長さが +1 になる
    tok.*.ty = Type.arrayOf(Type.typeChar(), len + 1);
    return tok;
}

fn readEscapedChar(str: [*:0]const u8, index: *usize) u8 {
    var j = index.*;
    var n: usize = 0;
    var c = str[j];
    while (n < 3 and '0' <= str[j] and str[j] <= '7') {
        if (n == 0) {
            c = str[j] - '0';
        } else {
            c = (c << 3) + (str[j] - '0');
        }
        j += 1;
        n += 1;
    }
    if (n > 0) {
        index.* = j;
        return c;
    }

    index.* += 1;
    return switch (c) {
        'a' => '\x07',
        'b' => '\x08',
        't' => '\t',
        'n' => '\n',
        'v' => 11,
        'f' => 12,
        'r' => 13,
        'e' => 27,
        'x' => readHex(str, index),
        else => c,
    };
}

fn readHex(str: [*:0]const u8, index: *usize) u8 {
    if (!isXdigit(str[index.*]))
        errorAt(index.*, null, "16進数ではありません");

    var j = index.*;
    var c: u8 = 0;
    while (isXdigit(str[j])) : (j += 1) {
        c = (c << 4) + fromHex(str[j]);
    }
    index.* = j + 1;
    return c;
}

fn fromHex(c: u8) u8 {
    if ('0' <= c and c <= '9') {
        return c - '0';
    } else if ('a' <= c and c <= 'f') {
        return c - 'a' + 10;
    }
    return c - 'A' + 10;
}

fn isXdigit(c: u8) bool {
    return ('0' <= c and c <= '9') or ('a' <= c and c <= 'f') or ('A' <= c and c <= 'F');
}

fn readFile(filename: [:0]u8) ![:0]u8 {
    var file: fs.File = undefined;
    if (streq(filename, "-")) {
        // - のときは標準入力から読み込み
        file = std.io.getStdIn();
    } else {
        const cwd = fs.cwd();
        file = cwd.openFile(filename, .{}) catch |e| {
            std.debug.panic("Unable to open file: {}\n", .{@errorName(e)});
        };
    }
    defer file.close();

    var buf: [1024 * 4]u8 = undefined;
    var result = try ArrayListSentineled(u8, 0).init(getAllocator(), "");
    defer result.deinit();
    while (true) {
        const bytes_read = file.read(buf[0..]) catch |e| {
            std.debug.panic("Unable to read from stream: {}\n", .{@errorName(e)});
        };

        if (bytes_read == 0) {
            break;
        }

        try result.appendSlice(buf[0..bytes_read]);
    }
    if (!result.endsWith("\n"))
        try result.appendSlice("\n");
    return result.toOwnedSlice();
}

pub fn tokenizeFile(filename: [:0]u8) !ArrayList(Token) {
    return try tokenize(filename, try readFile(filename));
}

pub fn getLineNo(str: [:0]const u8, loc: usize) usize {
    var i: usize = 0;
    var n: usize = 1;

    while (i < str.len) : (i += 1) {
        if (loc == i) {
            return n;
        }
        if (str[i] == '\n')
            n += 1;
    }
    return 0;
}
