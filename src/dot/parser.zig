const std = @import("std");
const testing = std.testing;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const AutoHashMapUnmanaged = std.AutoHashMapUnmanaged;
const chess = @import("chess/types.zig");
const lx = @import("lexer.zig");

const errors = error{
    NoBecomesAfterSymbol,
    ExpectingStarOrDot,
    ExpectingStarWord,
    ExpectingDotWord,
    StarOwnerMustBeSymbol,
    ExpectingStarBecomes,
    NoSymbolAfterStar,
};

///
/// knight
///  .center
///  .attackedby pawn3
///                .ffile
///                .blocksescapesquaresof king
///
/// dot .owner symbol or star
///     .extra symbol
///
/// star .owner symbol
///      .becomes symbol
///      .extra symbol
///
///
/// .dots
/// .stars
/// .symbols
///
/// instruction dot or star
///
/// .instructions
///
///
///
pub const TokenRef = usize;
pub const SymbolRef = usize;
pub const StarRef = usize;
pub const DotRef = usize;

pub const Symbol = TokenRef;
pub const OwnerTag = enum { symbol, dot, star };
pub const Owner = union(OwnerTag) { symbol: SymbolRef, dot: DotRef, star: StarRef };
pub const Dot = struct { dotword: TokenRef, owner: Owner, extra: ?Symbol };
pub const Star = struct { starword: TokenRef, owner: Owner, becomes: Symbol, one: Symbol, two: ?Symbol };
pub const InstructionTag = enum { dot, star };
pub const DotOrStar = union(InstructionTag) { dot: DotRef, star: StarRef };

pub const ProgramBuilder = struct {
    tokens: Tokens,
    dots: std.ArrayList(Dot) = .empty,
    stars: std.ArrayList(Star) = .empty,
    symbols: std.ArrayList(Symbol) = .empty,
    instructions: std.ArrayList(DotOrStar) = .empty,

    const Slice = struct { off: usize, len: usize };
    const GetSlice = struct { token: []lx.Token, slice: Slice };
    const TokenGet = struct { token: lx.Token, ref: TokenRef };
    const DotGet = struct { token: lx.Token, ref: DotRef };
    const StarGet = struct { token: lx.Token, ref: StarRef };
    const SymbolGet = struct { token: lx.Token, ref: SymbolRef };
    const Tokens = struct {
        by_line_flat: ArrayList(lx.Token),
        by_line: AutoHashMapUnmanaged(usize, Slice),

        fn deinit(self: *Tokens, allocator: Allocator) void {
            self.by_line_flat.deinit(allocator);
            self.by_line.deinit(allocator);
        }

        fn init(allocator: Allocator, tokens: []lx.Token) !Tokens {
            var result: Tokens = .{ .by_line_flat = .empty, .by_line = .empty };
            errdefer result.by_line_flat.deinit(allocator);
            errdefer result.by_line.deinit(allocator);

            var line_no: usize = 0;
            var list: ArrayList(lx.Token) = .empty;
            errdefer list.deinit(allocator);
            for (tokens) |token| {
                if (token.line_no != line_no) {
                    const off = result.by_line_flat.items.len;
                    const len = list.items.len;
                    if (len > 0) {
                        try result.by_line_flat.appendSlice(allocator, list.items);
                        list.deinit(allocator);
                        list = .empty;
                        errdefer list.deinit(allocator);

                        try result.by_line.put(allocator, line_no, .{ .off = off, .len = len });
                    }
                }
                line_no = token.line_no;
                try list.append(allocator, token);
            }
            const off = result.by_line_flat.items.len;
            const len = list.items.len;
            if (len > 0) {
                try result.by_line_flat.appendSlice(allocator, list.items);

                try result.by_line.put(allocator, list.items[0].line_no, .{ .off = off, .len = len });
            }
            list.deinit(allocator);

            return result;
        }

        fn get(self: *Tokens, line_no: usize) ?GetSlice {
            return if (self.by_line.get(line_no)) |slice|
                .{ .token = self.by_line_flat.items[slice.off .. slice.off + slice.len], .slice = slice }
            else
                null;
        }

        fn toOwnedSlice(self: *Tokens, allocator: Allocator) ![]lx.Token {
            return self.by_line_flat.toOwnedSlice(allocator);
        }
    };

    pub fn deinit(self: *ProgramBuilder, allocator: Allocator) void {
        self.tokens.deinit(allocator);
        self.dots.deinit(allocator);
        self.stars.deinit(allocator);
        self.symbols.deinit(allocator);
        self.instructions.deinit(allocator);
    }

    pub fn init(allocator: Allocator, tokens: []lx.Token) !ProgramBuilder {
        var result: ProgramBuilder = .{ .tokens = try Tokens.init(allocator, tokens) };
        errdefer result.deinit(allocator);

        for (1..tokens[tokens.len - 1].line_no + 1) |line_no| {
            if (result.tokens.get(line_no)) |get| {
                for (get.token, get.slice.off..get.slice.off + get.slice.len) |token, ref| {
                    if (token.begin_column_no == 1 and token.kind != lx.TokenKind.Eof) {
                        try result.addSymbol(allocator, token, ref);
                        break;
                    }
                }
            }
        }
        return result;
    }

    fn getFirstTokenBetween(self: *ProgramBuilder, begin_column_no: usize, end_column_no: usize, line_no: usize) ?TokenGet {
        if (self.tokens.get(line_no)) |get| {
            for (get.token, get.slice.off..get.slice.off + get.slice.len) |token, ref| {
                if (token.begin_column_no >= begin_column_no and token.begin_column_no <= end_column_no) {
                    return .{ .token = token, .ref = ref };
                }
            }
        }
        return null;
    }

    fn getFirstTokenAfter(self: *ProgramBuilder, end_column_no: usize, line_no: usize) ?TokenGet {
        if (self.tokens.get(line_no)) |get| {
            for (get.token, get.slice.off..get.slice.off + get.slice.len) |token, ref| {
                if (token.begin_column_no >= end_column_no) {
                    return .{ .token = token, .ref = ref };
                }
            }
        }
        return null;
    }

    fn addDotWord(self: *ProgramBuilder, allocator: Allocator, dot: TokenGet, owner: Owner) anyerror!void {
        if (dot.token.kind == lx.TokenKind.Dot) {
            if (self.getFirstTokenAfter(dot.token.end_column_no, dot.token.line_no)) |dotword| {
                if (dotword.token.kind == lx.TokenKind.DotWord) {
                    for (self.dots.items) |existing| if (existing.dotword == dotword.ref) return;
                    var extra: ?Symbol = null;
                    if (self.getFirstTokenAfter(dotword.token.end_column_no, dotword.token.line_no)) |e| {
                        try self.addSymbol(allocator, e.token, e.ref);
                        extra = e.ref;
                    }

                    const dotref = self.dots.items.len;
                    try self.dots.append(allocator, .{ .dotword = dotword.ref, .owner = owner, .extra = extra });

                    try self.instructions.append(allocator, .{ .dot = dotref });

                    if (self.getFirstTokenAfter(0, dotword.token.line_no + 1)) |get| {
                        try self.addDotWord(allocator, get, owner);
                        try self.addStarWord(allocator, get, owner);
                    }

                    return;
                }
            }

            std.debug.print("{d} {d}", .{ dot.token.begin_column_no, dot.token.line_no });

            return errors.ExpectingDotWord;
        }
    }

    fn addStarWord(self: *ProgramBuilder, allocator: Allocator, star: TokenGet, owner: Owner) anyerror!void {
        switch (owner) {
            .symbol => {},
            else => {
                return errors.StarOwnerMustBeSymbol;
            },
        }
        if (star.token.kind != lx.TokenKind.Star) {
            return;
        }

        const starword = findstarword: {
            if (self.getFirstTokenAfter(star.token.end_column_no, star.token.line_no)) |starword| {
                if (starword.token.kind == lx.TokenKind.StarWord) {
                    break :findstarword starword;
                }
            }
            return errors.ExpectingStarWord;
        };

        const symbol = findsymbol: {
            if (self.getFirstTokenAfter(starword.token.end_column_no, starword.token.line_no)) |symbol| {
                if (symbol.token.kind == lx.TokenKind.SymbolWord) {
                    break :findsymbol symbol;
                }
            }
            return errors.ExpectingStarWord;
        };

        const starbecomes = findstar: {
            if (self.getFirstTokenAfter(symbol.token.end_column_no, symbol.token.line_no)) |starbecomes| {
                if (star.token.kind == lx.TokenKind.Star) {
                    break :findstar starbecomes;
                }
            }
            return errors.ExpectingStarBecomes;
        };

        const becomes = findbecomes: {
            if (self.getFirstTokenAfter(starbecomes.token.end_column_no, starbecomes.token.line_no)) |becomes| {
                if (becomes.token.kind == lx.TokenKind.StarWord and becomes.token.identity.starword == lx.StarWordId.becomes) {
                    if (self.getFirstTokenAfter(becomes.token.end_column_no, becomes.token.line_no)) |becomessymbol| {
                        if (becomessymbol.token.kind == lx.TokenKind.SymbolWord) {
                            break :findbecomes becomessymbol;
                        }
                    }
                }
            }
            return errors.ExpectingStarBecomes;
        };

        const extra = undefined;

        const starref = self.stars.items.len;
        try self.stars.append(allocator, .{ .starword = starword.ref, .owner = owner, .becomes = becomes.ref, .one = symbol.ref, .two = extra });

        try self.instructions.append(allocator, .{ .star = starref });

        if (self.getFirstTokenAfter(0, starword.token.line_no + 1)) |get| {
            try self.addDotWord(allocator, get, owner);
            try self.addStarWord(allocator, get, owner);
        }
    }

    fn addSymbol(self: *ProgramBuilder, allocator: Allocator, token: lx.Token, ref: TokenRef) !void {
        if (token.kind == lx.TokenKind.SymbolWord) {
            try self.symbols.append(allocator, ref);

            if (self.getFirstTokenAfter(token.end_column_no, token.line_no)) |get| {
                try self.addDotWord(allocator, get, Owner{ .symbol = ref });
                try self.addStarWord(allocator, get, Owner{ .symbol = ref });
            }
            if (self.getFirstTokenBetween(token.begin_column_no, token.end_column_no, token.line_no + 1)) |get| {
                try self.addDotWord(allocator, get, Owner{ .symbol = ref });
                try self.addStarWord(allocator, get, Owner{ .symbol = ref });
            }
        }
    }

    pub fn build(self: *ProgramBuilder, allocator: Allocator) !Program {
        var program: Program = undefined;

        program.tokens = try self.tokens.toOwnedSlice(allocator);
        errdefer allocator.free(program.tokens);

        program.dots = try self.dots.toOwnedSlice(allocator);
        errdefer allocator.free(program.dots);

        program.stars = try self.stars.toOwnedSlice(allocator);
        errdefer allocator.free(program.stars);

        program.symbols = try self.symbols.toOwnedSlice(allocator);
        errdefer allocator.free(program.symbols);

        program.instructions = try self.instructions.toOwnedSlice(allocator);
        errdefer allocator.free(program.instructions);

        return program;
    }
};

pub const Program = struct {
    tokens: []lx.Token,
    dots: []Dot,
    stars: []Star,
    symbols: []Symbol,
    instructions: []DotOrStar,

    pub fn deinit(self: Program, allocator: Allocator) void {
        allocator.free(self.tokens);
        allocator.free(self.dots);
        allocator.free(self.stars);
        allocator.free(self.symbols);
        allocator.free(self.instructions);
    }
};

test "basic usage" {
    const ally = testing.allocator;

    var lexer: lx.Lexer = .{};
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

    var builder = try ProgramBuilder.init(ally, tokens);
    defer builder.deinit(ally);

    const program = try builder.build(ally);
    defer program.deinit(ally);

    try std.testing.expectEqual(3, program.symbols.len);
    try std.testing.expectEqual(2, program.dots.len);
    try std.testing.expectEqual(2, program.instructions.len);
}

test "extended" {
    const ally = testing.allocator;

    var lexer: lx.Lexer = .{};
    defer lexer.deinit(ally);

    try lexer.appendScript(ally,
        \\
        \\
        \\king
        \\   .home .near rook
        \\
        \\queen
        \\    .pins pawn2 .to king
        \\
    );

    const tokens = try lexer.toOwnedSlice(ally);
    defer ally.free(tokens);

    var builder = try ProgramBuilder.init(ally, tokens);
    defer builder.deinit(ally);

    const program = try builder.build(ally);
    defer program.deinit(ally);
}

test "gaps" {
    const ally = testing.allocator;

    var lexer: lx.Lexer = .{};
    defer lexer.deinit(ally);

    try lexer.appendScript(ally,
        \\
        \\knight
        \\     .center
        \\     .attackedby pawn3
        \\                     .ffile
        \\     .blocksescapesquaresof king
        \\
    );

    const tokens = try lexer.toOwnedSlice(ally);
    defer ally.free(tokens);

    var builder = try ProgramBuilder.init(ally, tokens);
    defer builder.deinit(ally);

    const program = try builder.build(ally);
    defer program.deinit(ally);

    try std.testing.expectEqual(4, program.dots.len);
}

test "final" {
    const ally = testing.allocator;

    var lexer: lx.Lexer = .{};
    defer lexer.deinit(ally);

    try lexer.appendScript(ally,
        \\
        \\bishop
        \\     *Sacrificeson pawn *becomes bishop2
        \\     .checks king
        \\           .cannotbecaptured
        \\           .cannotbeblocked
        \\
        \\king
        \\   .haslegalmoveto sq
        \\                    .corner
        \\    .cancapture bishop
        \\                     .hanging
        \\
        \\king *Captures bishop2 *becomes king2
        \\
    );
    const tokens = try lexer.toOwnedSlice(ally);
    defer ally.free(tokens);

    var builder = try ProgramBuilder.init(ally, tokens);
    defer builder.deinit(ally);

    const program = try builder.build(ally);
    defer program.deinit(ally);

    try std.testing.expectEqual(9, program.instructions.len);
}

test "regression 1" {
    const ally = testing.allocator;

    var lexer: lx.Lexer = .{};
    defer lexer.deinit(ally);

    try lexer.appendScript(ally,
        \\
        \\pawn *Captures pawn2 *becomes pawn3
        \\
    );
    const tokens = try lexer.toOwnedSlice(ally);
    defer ally.free(tokens);

    var builder = try ProgramBuilder.init(ally, tokens);
    defer builder.deinit(ally);

    const program = try builder.build(ally);
    defer program.deinit(ally);

    try std.testing.expectEqual(1, program.instructions.len);
}

test "regression 2" {
    const ally = testing.allocator;

    var lexer: lx.Lexer = .{};
    defer lexer.deinit(ally);

    try lexer.appendScript(ally,
        \\
        \\bishop *Captures pawn2 *becomes bishop3
        \\
    );
    const tokens = try lexer.toOwnedSlice(ally);
    defer ally.free(tokens);

    var builder = try ProgramBuilder.init(ally, tokens);
    defer builder.deinit(ally);

    const program = try builder.build(ally);
    defer program.deinit(ally);

    try std.testing.expectEqual(1, program.instructions.len);
}
