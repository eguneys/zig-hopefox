const std = @import("std");
const testing = std.testing;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const chess = @import("chess/types.zig");

pub const TokenKind = enum { Dot, Star, DotWord, SymbolWord, StarWord, Eof };

const IdentityTag = enum { symbol, char, dotword, starword };
const TokenIdentity = union(IdentityTag) { symbol: Symbol, char: u8, dotword: DotWordId, starword: StarWordId };

pub const Symbol = struct { name: SymbolId, id: usize };
pub const SymbolId = enum { king, queen, rook, bishop, knight, pawn, sq };

pub const DotWordId = enum {
    eyes,
    defendedby,
    near,
    home,
    pins,
    to,
    center,
    attackedby,
    ffile,
    blocksescapesquaresof,
    checks,
    cannotbecaptured,
    cannotbeblocked,
    haslegalmoveto,
    hasonelegalmoveto,
    cancapture,
    corner,
    hanging,
};

pub const StarWordId = enum {
    Sacrificeson,
    becomes,
    Captures,
    Checks,
    forks,
    and_,
    Movesto,
    withcheck,
};

pub const Token = struct { kind: TokenKind, line_no: usize, end_column_no: usize, begin_column_no: usize, identity: TokenIdentity };

pub const Lexer = struct {
    text: ArrayList(u8) = .empty,

    line_no: usize = 1,
    column_no: usize = 1,
    inext: usize = 0,

    const DotWordFields = std.meta.fields(DotWordId);
    const StarWordFields = std.meta.fields(StarWordId);
    const SymbolFields = std.meta.fields(SymbolId);

    pub fn deinit(self: *Self, allocator: Allocator) void {
        self.text.deinit(allocator);
    }

    const Self = @This();

    pub fn appendScript(self: *Self, allocator: Allocator, script: []const u8) !void {
        try self.text.appendSlice(allocator, script);
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
                .kind = TokenKind.Eof,
                .line_no = self.line_no,
                .begin_column_no = self.column_no - 2,
                .end_column_no = self.column_no - 2,
                .identity = .{ .char = 0 },
            };
        }

        if (self.text.items[self.inext] == '.') {
            self.inext += 1;
            self.column_no += 1;
            return .{
                .kind = TokenKind.Dot,
                .line_no = self.line_no,
                .begin_column_no = self.column_no - 1,
                .end_column_no = self.column_no,
                .identity = .{ .char = '.' },
            };
        }

        if (self.text.items[self.inext] == '*') {
            self.inext += 1;
            self.column_no += 1;
            return .{
                .kind = TokenKind.Star,
                .line_no = self.line_no,
                .begin_column_no = self.column_no - 1,
                .end_column_no = self.column_no,
                .identity = .{ .char = '*' },
            };
        }

        const begin_column_no = self.column_no;

        inline for (StarWordFields, 0..) |starword, i| {
            if (std.mem.startsWith(u8, self.text.items[self.inext..], starword.name)) {
                self.inext += starword.name.len;
                self.column_no += starword.name.len;

                return .{
                    .kind = TokenKind.StarWord,
                    .line_no = self.line_no,
                    .begin_column_no = begin_column_no,
                    .end_column_no = self.column_no,
                    .identity = .{ .starword = @enumFromInt(i) },
                };
            }
        }
        if (std.mem.startsWith(u8, self.text.items[self.inext..], "and")) {
            self.inext += 3;
            self.column_no += 3;

            return .{
                .kind = TokenKind.StarWord,
                .line_no = self.line_no,
                .begin_column_no = begin_column_no,
                .end_column_no = self.column_no,
                .identity = .{ .starword = StarWordId.and_ },
            };
        }

        inline for (DotWordFields, 0..) |dotword, i| {
            if (std.mem.startsWith(u8, self.text.items[self.inext..], dotword.name)) {
                self.inext += dotword.name.len;
                self.column_no += dotword.name.len;

                return .{
                    .kind = TokenKind.DotWord,
                    .line_no = self.line_no,
                    .begin_column_no = begin_column_no,
                    .end_column_no = self.column_no,
                    .identity = .{ .dotword = @enumFromInt(i) },
                };
            }
        }

        inline for (SymbolFields) |symbol| {
            if (std.mem.startsWith(u8, self.text.items[self.inext..], symbol.name)) {
                self.inext += symbol.name.len;
                self.column_no += symbol.name.len;
                const id: usize = findid: {
                    var base: usize = 1;
                    var iid: usize = 0;
                    var char = self.text.items[self.inext];
                    while (std.ascii.isDigit(char)) {
                        iid += (char - '0') * base;
                        base *= 10;

                        self.inext += 1;
                        self.column_no += 1;
                        char = self.text.items[self.inext];
                    }

                    break :findid iid;
                };

                return .{
                    .kind = TokenKind.SymbolWord,
                    .line_no = self.line_no,
                    .begin_column_no = begin_column_no,
                    .end_column_no = self.column_no,
                    .identity = .{ .symbol = .{
                        .name = @enumFromInt(symbol.value),
                        .id = id,
                    } },
                };
            }
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

    var lexer: Lexer = .{};
    defer lexer.deinit(ally);

    try lexer.appendScript(ally,
        \\
        \\bishop
        \\     .eyes pawn
        \\     .defendedby king
        \\
    );

    const tokens = try lexer.toOwnedSlice(ally);
    defer ally.free(tokens);

    try testing.expectEqual(8, tokens.len);
}

test "more usage" {
    const ally = testing.allocator;

    var lexer: Lexer = .{};
    defer lexer.deinit(ally);

    try lexer.appendScript(ally,
        \\
        \\
        \\king
        \\    .home .near rook
        \\
        \\queen
        \\     .pins pawn2 .to king
        \\knight
        \\     .center
        \\     .attackedby pawn3
        \\                      .ffile
        \\     .blocksescapesquaresof king
        \\
        \\
        \\
    );

    const tokens = try lexer.toOwnedSlice(ally);
    defer ally.free(tokens);

    try testing.expectEqual(25, tokens.len);
}

test "star usage" {
    const ally = testing.allocator;

    var lexer: Lexer = .{};
    defer lexer.deinit(ally);

    try lexer.appendScript(ally,
        \\
        \\
        \\bishop
        \\      *Sacrificeson pawn *becomes bishop2
        \\      .checks king
        \\             .cannotbecaptured
        \\             .cannotbeblocked
        \\
        \\
    );

    const tokens = try lexer.toOwnedSlice(ally);
    defer ally.free(tokens);

    try testing.expectEqual(15, tokens.len);
}

test "final form" {
    const ally = testing.allocator;

    var lexer: Lexer = .{};
    defer lexer.deinit(ally);

    try lexer.appendScript(ally,
        \\
        \\ king
        \\     .haslegalmoveto sq
        \\                       .corner
        \\     .cancapture bishop
        \\                       .hanging
        \\ 
        \\ king *Captures bishop2 *becomes king2
        \\ 
        \\ queen *forks king2  *and                       pawn4 *becomes queen2
        \\                  .hasonelegalmoveto king           .hanging
        \\ 
        \\ king2 *Movesto king *becomes king3
        \\ 
        \\ queen2 *Captures pawn4 *withcheck *becomes queen3
        \\
        \\
    );

    const tokens = try lexer.toOwnedSlice(ally);
    defer ally.free(tokens);

    try testing.expectEqual(50, tokens.len);
}
