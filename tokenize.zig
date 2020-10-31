const std = @import("std");
const List = std.ArrayList;
const allocPrint0 = std.fmt.allocPrint0;
const Allocator = std.mem.Allocator;

const KEYWORDS = "+-";

pub const TokenKind = enum {
    Punct, // 区切り記号
    Num, // 数値
};

pub const Token = struct {
    kind: TokenKind,
    val: [:0]u8,
};

pub fn newToken(allocator: *Allocator, kind: TokenKind, val: []const u8) !Token {
    return Token{ .kind = kind, .val = try allocPrint0(allocator, "{}", .{val}) };
}

pub fn tokenize(allocator: *Allocator, str: [*:0]const u8) !List(Token) {
    var tokens = List(Token).init(allocator);
    var i: usize = 0;
    while (str[i] != 0) {
        const c = str[i];
        if (is_space(c)) {
            i += 1;
        } else if (is_number(c)) {
            const h = i;
            i = consume_number(str, i);
            const num = try newToken(allocator, .Num, str[h..i]);
            try tokens.append(num);
        } else if (is_keyword(c)) {
            const punct = try newToken(allocator, .Punct, str[i .. i + 1]);
            try tokens.append(punct);
            i += 1;
        } else {
            std.debug.panic("トークナイズできませんでした {}", .{str[i .. i + 1]});
        }
    }
    return tokens;
}

fn is_number(c: u8) bool {
    return '0' <= c and c <= '9';
}

fn is_space(c: u8) bool {
    return c == ' ';
}

fn is_keyword(c: u8) bool {
    for (KEYWORDS) |k| {
        if (c == k) {
            return true;
        }
    }
    return false;
}

fn expect_number(ptr: [*:0]const u8, index: usize) usize {
    if (is_number(ptr[index])) {
        return consume_number(ptr, index);
    } else {
        std.debug.panic("数値ではありません {}", .{ptr[index .. index + 1]});
    }
}

fn consume_number(ptr: [*:0]const u8, index: usize) usize {
    var end = index;
    while (is_number(ptr[end])) {
        end += 1;
    }
    return end;
}
