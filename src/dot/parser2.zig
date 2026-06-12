const std = @import("std");
const testing = std.testing;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const AutoHashMapUnmanaged = std.AutoArrayHashMapUnmanaged;
const chess = @import("chess/types.zig");
const lx = @import("lexer2.zig");

pub const errors = error{
    ExpectingSymbolBeforeStar,
    ExpectingDotOrSymbolAfterSymbol,
    ExpectingSymbolAfterStar,
    ExpectingSymbolAfterStarAction,
    ExpectingDotOrStarAfterSymbol,
    ExpectingBecomesAfterStarAction,
    ExpectingSymbolAfterDot,
    ExpectingSymbolAfterDotAction,
    ExpectingBeginSymbolBeforeDot,
};

pub const TokenRef = usize;
pub const SymbolRef = usize;

pub const Symbol = struct {
    identity: lx.SymbolIdentity,
    props: lx.SymbolProperties,
    token: TokenRef,
};

pub const BecomesAction = struct {
    tag: SymbolRef,
    one: SymbolRef,
    two: SymbolRef,
};

pub const Becomes = struct {
    action: BecomesAction,
    from: SymbolRef,
    to: SymbolRef,
};

pub const BecomesRef = usize;
pub const SideEffects = struct {
    action: BecomesAction,
    from: SymbolRef,
};

pub const SideEffectsRef = usize;
pub const InstructionTag = enum {
    becomes,
    sideEffects,
};
pub const Instruction = union(InstructionTag) {
    becomes: BecomesRef,
    sideEffects: SideEffectsRef,
};

pub const ParsedProgram = struct {
    tokens: []lx.Token,
    becomes: []Becomes,
    side_effects: []SideEffects,
    instructions: []Instruction,
    symbols: []Symbol,

    pub fn deinit(self: ParsedProgram, allocator: Allocator) void {
        allocator.free(self.tokens);
        allocator.free(self.becomes);
        allocator.free(self.side_effects);
        allocator.free(self.instructions);
        allocator.free(self.symbols);
    }
};

pub const Parser = struct {
    tokens: Tokens,
    becomes: ArrayList(Becomes),
    side_effects: ArrayList(SideEffects),
    instructions: ArrayList(Instruction),
    symbols: ArrayList(Symbol),

    pub fn deinit(self: *Parser, allocator: Allocator) void {
        self.tokens.deinit(allocator);
        self.becomes.deinit(allocator);
        self.side_effects.deinit(allocator);
        self.instructions.deinit(allocator);
        self.symbols.deinit(allocator);
    }

    pub fn init(allocator: Allocator, script: []const u8) !Parser {
        var lexer = try lx.Lexer.init(allocator, script);
        defer lexer.deinit(allocator);

        const tokens = try lexer.toOwnedSlice(allocator);
        defer allocator.free(tokens);

        var parser: Parser = .{
            .tokens = try Tokens.init(allocator, tokens),
            .becomes = .empty,
            .side_effects = .empty,
            .instructions = .empty,
            .symbols = .empty,
        };
        errdefer parser.deinit(allocator);

        if (tokens.len == 0) return parser;

        for (1..tokens[tokens.len - 1].line_no + 1) |line_no| {
            if (parser.tokens.getLine(line_no)) |get| {
                try parser.beginToken(allocator, get.token[0], get.slice.off);
            }
        }

        return parser;
    }

    fn beginToken(self: *Parser, allocator: Allocator, token: lx.Token, ref: TokenRef) !void {
        switch (token.tag) {
            lx.TokenTag.Dot => try self.beginDot(allocator, token.line_no, token.begin_column_no),
            lx.TokenTag.Star => return errors.ExpectingSymbolBeforeStar,
            lx.TokenTag.Symbol => try self.beginSymbol(allocator, ref),
            lx.TokenTag.Eof => {},
        }
    }

    fn getFirstSymbolBefore(self: *Parser, allocator: Allocator, line_no: usize, column_no: usize) !?GetSymbol {
        if (self.tokens.getLine(line_no)) |slice| {
            for (0..slice.slice.len) |i| {
                const reverse = slice.slice.len - 1 - i;
                if (slice.token[reverse].end_column_no > column_no) {
                    return try self.addOrGetSymbolForTokenRef(allocator, slice.slice.off + reverse);
                }
            }
        }
        return null;
    }

    fn beginDot(self: *Parser, allocator: Allocator, line_no: usize, column_no: usize) !void {
        if (try self.getFirstSymbolBefore(allocator, line_no, column_no) orelse
            try self.getFirstSymbolBefore(allocator, line_no - 1, column_no)) |from|
        {
            if (self.eatDotAfter(line_no, column_no)) |dot| {
                try self.takeDotFrom(allocator, from.ref, dot.token.line_no, dot.token.end_column_no);
            }
        } else {
            return errors.ExpectingBeginSymbolBeforeDot;
        }
    }

    fn beginSymbol(self: *Parser, allocator: Allocator, ref: TokenRef) !void {
        if (try self.addOrGetSymbolForTokenRef(allocator, ref)) |symbol| {
            if (self.eatStarAfter(symbol.token.line_no, symbol.token.end_column_no)) |star| {
                try self.takeStarFrom(allocator, ref, star.token.line_no, star.token.end_column_no);
            } else if (self.eatDotAfter(symbol.token.line_no, symbol.token.end_column_no)) |dot| {
                try self.takeDotFrom(allocator, ref, dot.token.line_no, dot.token.end_column_no);
            } else {
                return errors.ExpectingDotOrStarAfterSymbol;
            }
        }
    }

    fn eatStarAfter(self: *Parser, line_no: usize, column_no: usize) ?GetToken {
        if (self.tokens.getAfter(line_no, column_no)) |star| {
            if (star.token.tag == lx.TokenTag.Star) {
                return star;
            }
        }
        return null;
    }
    fn eatDotAfter(self: *Parser, line_no: usize, column_no: usize) ?GetToken {
        if (self.tokens.getAfter(line_no, column_no)) |dot| {
            if (dot.token.tag == lx.TokenTag.Dot) {
                return dot;
            }
        }
        return null;
    }

    fn takeSymbolAfter(self: *Parser, allocator: Allocator, line_no: usize, column_no: usize) !?GetSymbol {
        if (self.tokens.getAfter(line_no, column_no)) |symbol| {
            if (symbol.token.tag == lx.TokenTag.Symbol) {
                return self.addOrGetSymbolForTokenRef(allocator, symbol.ref);
            }
        }
        return null;
    }

    fn eatTokenAfterWithTag(self: *Parser, line_no: usize, column_no: usize, tag: lx.SymbolTag) !?GetToken {
        if (self.tokens.getAfter(line_no, column_no)) |token| {
            if (token.token.symbol) |symbol| {
                if (symbol.identity.tag == tag) {
                    return token;
                }
            }
        }
        return null;
    }

    fn getSymbolForTokenRef(self: *Parser, ref: TokenRef) ?GetSymbol {
        for (0..self.symbols.items.len) |i| {
            if (self.symbols.items[i].token == ref) {
                return .{ .token = self.tokens.by_line_flat.items[ref], .symbol = self.symbols.items[i], .ref = i };
            }
        }
        return null;
    }

    fn addOrGetSymbolForTokenRef(self: *Parser, allocator: Allocator, ref: TokenRef) !?GetSymbol {
        if (getSymbolForTokenRef(self, ref)) |result| {
            return result;
        }

        const symbol = self.tokens.by_line_flat.items[ref];

        if (symbol.tag == lx.TokenTag.Symbol) {
            const symbol_ref = self.symbols.items.len;
            const result_symbol = Symbol{
                .token = ref,
                .identity = symbol.symbol.?.identity,
                .props = symbol.symbol.?.props,
            };
            try self.symbols.append(allocator, result_symbol);
            return .{
                .token = symbol,
                .symbol = result_symbol,
                .ref = symbol_ref,
            };
        } else {
            return null;
        }
    }

    fn takeStarFrom(self: *Parser, allocator: Allocator, from: TokenRef, line_no: usize, column_no: usize) !void {
        const tag = try self.takeSymbolAfter(allocator, line_no, column_no) orelse
            return errors.ExpectingSymbolAfterStar;

        const one = try self.takeSymbolAfter(allocator, tag.token.line_no, tag.token.end_column_no) orelse
            return errors.ExpectingSymbolAfterStarAction;

        const two: ?GetSymbol = findtwo: {
            if (self.tokens
                .getAfter(one.token.line_no, one.token.end_column_no)) |star|
            {
                if (star.token.tag == lx.TokenTag.Star) {
                    if (try self.eatTokenAfterWithTag(star.token.line_no, star.token.end_column_no, lx.SymbolTag.and_)) |toand| {
                        break :findtwo try self.takeSymbolAfter(allocator, toand.token.line_no, toand.token.end_column_no);
                    }
                    if (try self.eatTokenAfterWithTag(star.token.line_no, star.token.end_column_no, lx.SymbolTag.to)) |toand| {
                        break :findtwo try self.takeSymbolAfter(allocator, toand.token.line_no, toand.token.end_column_no);
                    }
                }
            }
            break :findtwo null;
        };

        const next = two orelse one;

        const becomes = findbecomes: {
            if (self.tokens
                .getAfter(next.token.line_no, next.token.end_column_no)) |star|
            {
                if (star.token.tag == lx.TokenTag.Star) {
                    if (try self.eatTokenAfterWithTag(star.token.line_no, star.token.end_column_no, lx.SymbolTag.becomes)) |becomes| {
                        break :findbecomes becomes;
                    }
                }
            }
            return errors.ExpectingBecomesAfterStarAction;
        };

        const to =
            try self.takeSymbolAfter(allocator, becomes.token.line_no, becomes.token.end_column_no) orelse
            return errors.ExpectingSymbolAfterStarAction;

        const tworef = if (two) |ref| ref.ref else 0;

        const result = Becomes{
            .from = from,
            .to = to.ref,
            .action = .{ .tag = tag.ref, .one = one.ref, .two = tworef },
        };

        try self.instructions.append(allocator, .{ .becomes = self.becomes.items.len });
        try self.becomes.append(allocator, result);
    }

    fn takeDotFrom(self: *Parser, allocator: Allocator, from: TokenRef, line_no: usize, column_no: usize) !void {
        const tag = (try self.takeSymbolAfter(allocator, line_no, column_no)) orelse
            return errors.ExpectingSymbolAfterDot;

        const one = (try self.takeSymbolAfter(allocator, tag.token.line_no, tag.token.end_column_no)) orelse
            return errors.ExpectingSymbolAfterDotAction;

        const two: ?GetSymbol = findtwo: {
            if (self.tokens
                .getAfter(one.token.line_no, one.token.end_column_no)) |star|
            {
                if (star.token.tag == lx.TokenTag.Star) {
                    if (try self.eatTokenAfterWithTag(star.token.line_no, star.token.end_column_no, lx.SymbolTag.and_)) |toand| {
                        break :findtwo try self.takeSymbolAfter(allocator, toand.token.line_no, toand.token.end_column_no);
                    }
                    if (try self.eatTokenAfterWithTag(star.token.line_no, star.token.end_column_no, lx.SymbolTag.to)) |toand| {
                        break :findtwo try self.takeSymbolAfter(allocator, toand.token.line_no, toand.token.end_column_no);
                    }
                }
            }
            break :findtwo null;
        };

        const tworef = if (two) |ref| ref.ref else 0;

        const side_effect = SideEffects{
            .from = from,
            .action = .{ .tag = tag.ref, .one = one.ref, .two = tworef },
        };

        try self.instructions.append(allocator, .{ .sideEffects = self.side_effects.items.len });
        try self.side_effects.append(allocator, side_effect);
    }

    const Self = @This();

    pub fn toOwnedProgram(self: *Self, allocator: Allocator) !ParsedProgram {
        var program: ParsedProgram = undefined;

        program.tokens = try self.tokens.toOwnedSlice(allocator);
        errdefer allocator.free(program.tokens);

        program.becomes = try self.becomes.toOwnedSlice(allocator);
        errdefer allocator.free(program.becomes);

        program.side_effects = try self.side_effects.toOwnedSlice(allocator);
        errdefer allocator.free(program.side_effects);

        program.instructions = try self.instructions.toOwnedSlice(allocator);
        errdefer allocator.free(program.instructions);

        program.symbols = try self.symbols.toOwnedSlice(allocator);
        errdefer allocator.free(program.symbols);

        return program;
    }

    const Slice = struct { off: usize, len: usize };
    const GetSlice = struct { token: []lx.Token, slice: Slice };
    const GetToken = struct { token: lx.Token, ref: TokenRef };
    const GetSymbol = struct { token: lx.Token, symbol: Symbol, ref: SymbolRef };
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

        fn getLine(self: Tokens, line_no: usize) ?GetSlice {
            return if (self.by_line.get(line_no)) |slice|
                .{ .token = self.by_line_flat.items[slice.off .. slice.off + slice.len], .slice = slice }
            else
                null;
        }

        fn getAfter(self: *Tokens, line_no: usize, after_column: usize) ?GetToken {
            if (self.getLine(line_no)) |get| {
                for (0..get.slice.len) |i| {
                    if (get.token[i].begin_column_no >= after_column) {
                        return .{ .token = get.token[i], .ref = get.slice.off + i };
                    }
                }
            }
            return null;
        }

        fn toOwnedSlice(self: *Tokens, allocator: Allocator) ![]lx.Token {
            return self.by_line_flat.toOwnedSlice(allocator);
        }
    };
};

test "basic usage" {
    const ally = testing.allocator;
    const script =
        \\rook2 *Captures rook4 *becomes rook5
        \\      .Forks king .and queen
        \\rook *Blocks rook5 *to king *becomes rook6
    ;

    var parser = try Parser.init(ally, script);
    defer parser.deinit(ally);

    const program = try parser.toOwnedProgram(ally);
    defer program.deinit(ally);

    try testing.expectEqual(2, program.becomes.len);
    try testing.expectEqual(1, program.side_effects.len);
    try testing.expectEqual(3, program.instructions.len);
    try testing.expectEqual(12, program.symbols.len);
}

fn log_str(string: []const u8) void {
    std.debug.print("{s}", .{string});
}

fn log_token(token: lx.Token) void {
    std.debug.print("[Token.{d}", .{token.begin_column_no});
    if (token.symbol) |symbol| {
        std.debug.print("{t}{d}]", .{ symbol.identity.tag, symbol.identity.id });
    } else {
        std.debug.print("]", .{});
    }
}
