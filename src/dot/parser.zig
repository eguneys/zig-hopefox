const std = @import("std");
const testing = std.testing;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const chess = @import("chess/types.zig");

const TokenKind = enum { Dot, Star, DotWord, SymbolWord, StarWord, Eof };

const IdentityTag = enum { role, file, rank, direction, directionplus, square, char, dotword, starword };
const TokenIdentity = union(IdentityTag) { role: RoleId, file: FileId, rank: RankId, direction: DirectionId, directionplus: DirectionPlusId, square: SquareId, char: CharId, dotword: DotWordId, starword: StarWordId };

const SquareId = chess.Square;
const RoleId = struct { role: chess.Role, id: usize };
const FileId = chess.File;
const RankId = chess.Rank;
const DirectionId = chess.Direction;
const DirectionPlusId = chess.DirectionPlus;
const CharId = u8;

const DotWordId = enum {
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
};

const StarWordId = enum {
    Sacrificeson,
    becomes,
};

const Token = struct { kind: TokenKind, line_no: usize, column_no: usize, identity: TokenIdentity };

const RoleNames: [6][]const u8 = .{ "king", "queen", "rook", "bishop", "knight", "pawn" };

const Lexer = struct {
    text: ArrayList(u8) = .empty,

    line_no: usize = 1,
    column_no: usize = 1,
    inext: usize = 0,

    const DotWordFields = std.meta.fields(DotWordId);
    const StarWordFields = std.meta.fields(StarWordId);

    fn deinit(self: *Self, allocator: Allocator) void {
        self.text.deinit(allocator);
    }

    const Self = @This();

    fn appendScript(self: *Self, allocator: Allocator, script: []const u8) !void {
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
                .column_no = self.column_no - 1,
                .identity = .{ .char = 0 },
            };
        }

        if (self.text.items[self.inext] == '.') {
            self.inext += 1;
            self.column_no += 1;
            return .{
                .kind = TokenKind.Dot,
                .line_no = self.line_no,
                .column_no = self.column_no - 1,
                .identity = .{ .char = '.' },
            };
        }

        if (self.text.items[self.inext] == '*') {
            self.inext += 1;
            self.column_no += 1;
            return .{
                .kind = TokenKind.Dot,
                .line_no = self.line_no,
                .column_no = self.column_no - 1,
                .identity = .{ .char = '*' },
            };
        }

        const column_no = self.column_no;

        inline for (StarWordFields, 0..) |starword, i| {
            if (std.mem.startsWith(u8, self.text.items[self.inext..], starword.name)) {
                self.inext += starword.name.len;
                self.column_no += starword.name.len;

                return .{
                    .kind = TokenKind.StarWord,
                    .line_no = self.line_no,
                    .column_no = column_no,
                    .identity = .{ .starword = @enumFromInt(i) },
                };
            }
        }

        inline for (DotWordFields, 0..) |dotword, i| {
            if (std.mem.startsWith(u8, self.text.items[self.inext..], dotword.name)) {
                self.inext += dotword.name.len;
                self.column_no += dotword.name.len;

                return .{
                    .kind = TokenKind.DotWord,
                    .line_no = self.line_no,
                    .column_no = column_no,
                    .identity = .{ .dotword = @enumFromInt(i) },
                };
            }
        }

        for (RoleNames, 0..) |roleName, i| {
            if (std.mem.startsWith(u8, self.text.items[self.inext..], roleName)) {
                self.inext += roleName.len;
                self.column_no += roleName.len;
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
                    .kind = TokenKind.DotWord,
                    .line_no = self.line_no,
                    .column_no = column_no,
                    .identity = .{
                        .role = RoleId{ .role = @enumFromInt(i), .id = id },
                    },
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

    fn toOwnedTokens(self: *Self, allocator: Allocator) ![]Token {
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

    const tokens = try lexer.toOwnedTokens(ally);
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

    const tokens = try lexer.toOwnedTokens(ally);
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

    const tokens = try lexer.toOwnedTokens(ally);
    defer ally.free(tokens);

    try testing.expectEqual(15, tokens.len);
}
