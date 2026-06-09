const std = @import("std");
const testing = std.testing;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const AutoHashMapUnmanaged = std.AutoHashMapUnmanaged;
const chess = @import("chess/types.zig");
const lx = @import("lexer.zig");

const errors = error{ NoBecomesAfterAction, ExpectingStarOrDot };

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
pub const Ref = usize;
pub const Symbol = Ref;
pub const Dot = struct { owner: SymbolOrStar, extra: ?Symbol };
pub const Star = struct { owner: Symbol, becomes: Symbol, extra: ?Symbol };
pub const SymbolOrStarTag = enum { symbol, star };
pub const SymbolOrStar = union(SymbolOrStarTag) { symbol: Symbol, star: Star };
pub const DotOrStar = union { dot: Ref, star: Ref };

pub const ProgramBuilder = struct {
    tokens: Tokens,
    dots: std.ArrayList(Dot) = .empty,
    stars: std.ArrayList(Star) = .empty,
    symbols: std.ArrayList(Symbol) = .empty,
    instructions: std.ArrayList(DotOrStar) = .empty,

    const Slice = struct { off: usize, len: usize };
    const GetSlice = struct { token: []lx.Token, slice: Slice };
    const Get = struct { token: lx.Token, ref: Ref };
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

            var line_no: usize = 1;
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

                try result.by_line.put(allocator, line_no, .{ .off = off, .len = len });
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

        for (0..tokens[tokens.len - 1].line_no) |line_no| {
            if (result.tokens.get(line_no)) |get| {
                for (get.token, get.slice.off..get.slice.off + get.slice.len) |token, ref| {
                    if (token.begin_column_no == 1) {
                        try result.addRootToken(allocator, token, ref);
                        break;
                    }
                }
            }
        }
        return result;
    }

    fn getFirstTokenBetween(self: *ProgramBuilder, begin_column_no: usize, end_column_no: usize, line_no: usize) ?Get {
        if (self.tokens.get(line_no)) |get| {
            for (get.token, get.slice.off..get.slice.off + get.slice.len) |token, ref| {
                if (token.begin_column_no <= begin_column_no and token.end_column_no <= end_column_no) {
                    return .{ .token = token, .ref = ref };
                }
            }
        }
        return null;
    }

    fn getFirstTokenAfter(self: *ProgramBuilder, end_column_no: usize, line_no: usize) ?Get {
        if (self.tokens.get(line_no)) |get| {
            for (get.token, get.slice.off..get.slice.off + get.slice.len) |token, ref| {
                if (token.begin_column_no > end_column_no) {
                    return .{ .token = token, .ref = ref };
                }
            }
        }
        return null;
    }

    fn addRootToken(self: *ProgramBuilder, allocator: Allocator, token: lx.Token, ref: Ref) !void {
        if (token.kind == lx.TokenKind.SymbolWord) {
            try self.symbols.append(allocator, ref);

            if (self.getFirstTokenBetween(token.begin_column_no, token.end_column_no, token.line_no + 1)) |get| {
                if (get.token.kind == lx.TokenKind.Dot) {
                    const extra = if (self.getFirstTokenAfter(token.end_column_no, token.line_no)) |e| e.ref else null;
                    try self.dots.append(allocator, .{ .owner = .{ .symbol = ref }, .extra = extra });
                } else if (get.token.kind == lx.TokenKind.Star) {
                    if (self.getFirstTokenAfter(token.end_column_no, token.line_no)) |becomes| {
                        if (becomes.token.kind == lx.TokenKind.StarWord and becomes.token.identity.starword == lx.StarWordId.becomes) {
                            const extra = if (self.getFirstTokenAfter(token.end_column_no, token.line_no)) |e| e.ref else null;
                            try self.stars.append(allocator, .{ .owner = ref, .becomes = becomes.ref, .extra = extra });
                            return;
                        }
                    }
                    return errors.NoBecomesAfterAction;
                } else {
                    return errors.ExpectingStarOrDot;
                }
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
}
