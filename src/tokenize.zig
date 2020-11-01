const std = @import("std");
const ArrayList = std.ArrayList;
const allocPrint0 = std.fmt.allocPrint0;
const err = @import("error.zig");
const errorAt = err.errorAt;
const globals = @import("globals.zig");

const KEYWORDS = "+-*/";

pub const TokenKind = enum {
    TkPunct, // 区切り記号
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
        } else if (isNumber(c)) {
            const h = i;
            i = expectNumber(str, i);
            const num = try newToken(.TkNum, str[h..i], i);
            try tokens.append(num);
        } else if (isKeyword(c)) {
            const punct = try newToken(.TkPunct, str[i .. i + 1], i);
            try tokens.append(punct);
            i += 1;
        } else {
            errorAt(i, "トークナイズできませんでした");
        }
    }
    return tokens;
}

fn isNumber(c: u8) bool {
    return '0' <= c and c <= '9';
}

fn isSpace(c: u8) bool {
    return c == ' ';
}

fn isKeyword(c: u8) bool {
    for (KEYWORDS) |k| {
        if (c == k) {
            return true;
        }
    }
    return false;
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
