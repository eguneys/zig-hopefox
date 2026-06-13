const std = @import("std");
const testing = std.testing;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const chess = @import("chess/types.zig");

pub const TokenTag = enum { Dot, Star, Symbol, Eof };

pub const SymbolTag = enum {
    king,
    queen,
    rook,
    bishop,
    knight,
    pawn,
    sq,
    Checks,
    Captures,
    becomes,
    Forks,
    Blocks,
    and_,
    to,
};

pub const SymbolIdentity = struct { tag: SymbolTag, id: usize };

pub const SymbolProperties = struct {
    turn: bool = false,
    opponent: bool = false,
};

pub const Symbol = struct { identity: SymbolIdentity, props: SymbolProperties };

pub const Token = struct {
    tag: TokenTag,
    line_no: usize,
    end_column_no: usize,
    begin_column_no: usize,
    symbol: ?Symbol,
};

pub const Lexer = struct {
    text: ArrayList(u8) = .empty,

    line_no: usize = 1,
    column_no: usize = 1,
    inext: usize = 0,

    const TagFields = std.meta.fields(SymbolTag);

    pub fn deinit(self: *Self, allocator: Allocator) void {
        self.text.deinit(allocator);
    }

    const Self = @This();

    pub fn init(allocator: Allocator, script: []const u8) !Lexer {
        var result = Lexer{ .text = try ArrayList(u8).initCapacity(allocator, script.len) };
        try result.text.appendSlice(allocator, script);
        return result;
    }

    fn peekNextChar(self: *Self) ?u8 {
        if (self.text.items.len <= self.inext) {
            return null;
        }
        return self.text.items[self.inext];
    }

    fn nextToken(self: *Self) ?Token {
        self.skipWhitespace();

        if (self.inext > self.text.items.len) {
            return null;
        }

        if (self.inext == self.text.items.len) {
            self.inext += 1;
            self.column_no += 1;
            return .{
                .tag = TokenTag.Eof,
                .line_no = self.line_no,
                .begin_column_no = self.column_no - 2,
                .end_column_no = self.column_no - 2,
                .symbol = null,
            };
        }

        if (self.peekNextChar()) |char| {
            if (char == '.') {
                self.inext += 1;
                self.column_no += 1;
                return .{
                    .tag = TokenTag.Dot,
                    .line_no = self.line_no,
                    .begin_column_no = self.column_no - 1,
                    .end_column_no = self.column_no,
                    .symbol = null,
                };
            }

            if (char == '*') {
                self.inext += 1;
                self.column_no += 1;
                return .{
                    .tag = TokenTag.Star,
                    .line_no = self.line_no,
                    .begin_column_no = self.column_no - 1,
                    .end_column_no = self.column_no,
                    .symbol = null,
                };
            }
        }

        const begin_column_no = self.column_no;

        inline for (TagFields, 0..) |tag, i| {
            if (std.mem.startsWith(u8, self.text.items[self.inext..], tag.name)) {
                self.inext += tag.name.len;
                self.column_no += tag.name.len;

                const id: usize = findid: {
                    var base: usize = 1;
                    var iid: usize = 0;
                    while (self.peekNextChar()) |char| {
                        if (std.ascii.isDigit(char)) {
                            iid += (char - '0') * base;
                            base *= 10;

                            self.inext += 1;
                            self.column_no += 1;
                        } else {
                            break;
                        }
                    }

                    break :findid iid;
                };

                var props = SymbolProperties{};

                while (self.peekNextChar()) |char| {
                    if (char != '_') break;
                    self.inext += 1;
                    self.column_no += 1;

                    if (self.peekNextChar()) |turn| {
                        switch (turn) {
                            't' => {
                                props.turn = true;
                                self.inext += 1;
                                self.column_no += 1;
                            },
                            'o' => {
                                props.opponent = true;
                                self.inext += 1;
                                self.column_no += 1;
                            },
                            else => {
                                break;
                            },
                        }
                    }
                }

                return .{
                    .tag = TokenTag.Symbol,
                    .line_no = self.line_no,
                    .begin_column_no = begin_column_no,
                    .end_column_no = self.column_no,
                    .symbol = .{
                        .identity = .{ .id = id, .tag = @enumFromInt(i) },
                        .props = props,
                    },
                };
            }
        }

        if (std.mem.startsWith(u8, self.text.items[self.inext..], "and")) {
            self.inext += 3;
            self.column_no += 3;

            return .{ .tag = TokenTag.Symbol, .line_no = self.line_no, .begin_column_no = begin_column_no, .end_column_no = self.column_no, .symbol = .{
                .identity = .{
                    .id = 0,
                    .tag = SymbolTag.and_,
                },
                .props = undefined,
            } };
        }

        return null;
    }

    fn skipWhitespace(self: *Self) void {
        while (self.inext < self.text.items.len) {
            const c = self.text.items[self.inext];
            if (c == '\n') {
                self.inext += 1;
                self.line_no += 1;
                self.column_no = 1;
            } else if (std.ascii.isWhitespace(c)) {
                self.inext += 1;
                self.column_no += 1;
            } else {
                break;
            }
        }
    }

    pub fn toOwnedSlice(self: *Self, allocator: Allocator) ![]Token {
        var tokens: ArrayList(Token) = .empty;
        errdefer tokens.deinit(allocator);

        while (self.nextToken()) |token| try tokens.append(allocator, token);

        return tokens.toOwnedSlice(allocator);
    }
};

test "basic usage" {
    const ally = testing.allocator;
    const script =
        \\rook2 *Captures rook4 *becomes rook5
        \\      .Forks king .and queen
        \\rook *Blocks rook5 *to king *becomes rook6
    ;

    var lexer = try Lexer.init(ally, script);
    defer lexer.deinit(ally);

    const tokens = try lexer.toOwnedSlice(ally);
    defer ally.free(tokens);

    try std.testing.expectEqual(24, tokens.len);

    try std.testing.expectEqual(1, tokens[0].begin_column_no);
    try std.testing.expectEqual(7, tokens[1].begin_column_no);
    try std.testing.expectEqual(8, tokens[2].begin_column_no);
    try std.testing.expectEqual(17, tokens[3].begin_column_no);
    try std.testing.expectEqual(23, tokens[4].begin_column_no);
    try std.testing.expectEqual(24, tokens[5].begin_column_no);
    try std.testing.expectEqual(32, tokens[6].begin_column_no);
    try std.testing.expectEqual(7, tokens[7].begin_column_no);
}
