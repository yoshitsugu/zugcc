const std = @import("std");
const ArrayList = std.ArrayList;
const allocPrint0 = std.fmt.allocPrint0;
const err = @import("error.zig");
const errorAt = err.errorAt;
const globals = @import("globals.zig");
const stdout = std.io.getStdOut().outStream();
const print = stdout.print;

const PUNCT_CHARS = "+-*/()<>;={}&,[]";
const PUNCT_STRS = [_][:0]const u8{ "==", "!=", "<=", ">=" };
const KEYWORDS = [_][:0]const u8{ "return", "if", "else", "for", "while" };

pub const TokenKind = enum {
    TkIdent, // 識別子
    TkPunct, // 区切り記号
    TkKeyword, // キーワード
    TkNum, // 数値
};

pub const Token = struct {
    kind: TokenKind, // トークン種別
    val: [:0]u8, // トークン文字列
    loc: usize, // 元の文字列上の場所
};

pub fn newToken(kind: TokenKind, val: []const u8, loc: usize) !Token {
    return Token{ .kind = kind, .val = try allocPrint0(globals.allocator, "{}", .{val}), .loc = loc };
}

pub fn tokenize(str: [*:0]const u8) !ArrayList(Token) {
    var tokens = ArrayList(Token).init(globals.allocator);
    var i: usize = 0;
    while (str[i] != 0) {
        const c = str[i];
        if (isSpace(c)) {
            i += 1;
            continue;
        }
        if (isNumber(c)) {
            const h = i;
            i = expectNumber(str, i);
            const num = try newToken(.TkNum, str[h..i], i);
            try tokens.append(num);
            continue;
        }
        if (isIdentHead(c)) {
            const h = i;
            i = readIdent(str, i);
            var tk = try newToken(.TkIdent, str[h..i], i);
            if (isKeyword(str, h, i)) {
                tk = try newToken(.TkKeyword, str[h..i], i);
            }
            try tokens.append(tk);
            continue;
        }
        const puncts_end = readPuncts(str, i);
        if (puncts_end > i) {
            const punct = try newToken(.TkPunct, str[i..puncts_end], i);
            try tokens.append(punct);
            i = puncts_end;
            continue;
        }
        if (isPunct(c)) {
            const punct = try newToken(.TkPunct, str[i .. i + 1], i);
            try tokens.append(punct);
            i += 1;
            continue;
        }
        errorAt(i, "トークナイズできませんでした");
    }
    return tokens;
}

fn isNumber(c: u8) bool {
    return '0' <= c and c <= '9';
}

fn isSpace(c: u8) bool {
    return c == ' ';
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
    const pstr = allocPrint0(globals.allocator, "{}", .{str[startIndex..endIndex]}) catch "";
    for (KEYWORDS) |kwd| {
        if (streq(kwd, pstr)) {
            return true;
        }
    }
    return false;
}

fn readPuncts(str: [*:0]const u8, i: usize) usize {
    for (PUNCT_STRS) |pstr| {
        const cut_str = allocPrint0(globals.allocator, "{}", .{str[i .. i + pstr.len]}) catch "";
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
        errorAt(index, "数値ではありません");
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
