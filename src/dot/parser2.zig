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

pub const BecomesAction = struct {
    tag: TokenRef,
    one: TokenRef,
    two: TokenRef,
};

pub const Becomes = struct {
    action: BecomesAction,
    from: TokenRef,
    to: TokenRef,
};

pub const BecomesRef = usize;
pub const SideEffects = struct {
    action: BecomesAction,
    from: TokenRef,
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

    pub fn deinit(self: ParsedProgram, allocator: Allocator) void {
        allocator.free(self.tokens);
        allocator.free(self.becomes);
        allocator.free(self.side_effects);
        allocator.free(self.instructions);
    }
};

pub const Parser = struct {
    tokens: Tokens,
    becomes: ArrayList(Becomes),
    side_effects: ArrayList(SideEffects),
    instructions: ArrayList(Instruction),

    pub fn deinit(self: *Parser, allocator: Allocator) void {
        self.tokens.deinit(allocator);
        self.becomes.deinit(allocator);
        self.side_effects.deinit(allocator);
        self.instructions.deinit(allocator);
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
        switch (token.kind) {
            lx.TokenTag.Dot => try self.beginDot(allocator, token.line_no, token.end_column_no),
            lx.TokenTag.Star => return errors.ExpectingSymbolBeforeStar,
            lx.TokenTag.Symbol => try self.beginSymbol(allocator, token, ref),
            lx.TokenTag.Eof => {},
        }
    }

    fn getFirstSymbolBefore(self: Parser, line_no: usize, column_no: usize) ?Get {
        if (self.tokens.getLine(line_no)) |slice| {
            for (0..slice.slice.len) |i| {
                const reverse = slice.slice.len - 1 - i;
                if (slice.token[reverse].end_column_no > column_no) {
                    return Get{ .token = slice.token[reverse], .ref = slice.slice.off + reverse };
                }
            }
        }
        return null;
    }

    fn beginDot(self: *Parser, allocator: Allocator, line_no: usize, column_no: usize) !void {
        if (self.getFirstSymbolBefore(line_no - 1, column_no)) |from| {
            try self.takeDotFrom(allocator, from.ref, line_no, column_no);
        } else {
            return errors.ExpectingBeginSymbolBeforeDot;
        }
    }

    fn beginSymbol(self: *Parser, allocator: Allocator, token: lx.Token, ref: TokenRef) !void {
        if (self.tokens
            .getAfter(token.line_no, token.end_column_no)) |aftersymbol|
        {
            switch (aftersymbol.token.kind) {
                lx.TokenTag.Dot => {
                    try self.takeDotFrom(allocator, ref, aftersymbol.token.line_no, aftersymbol.token.end_column_no);
                },
                lx.TokenTag.Star => {
                    try self.takeStarFrom(allocator, ref, aftersymbol.token.line_no, aftersymbol.token.end_column_no);
                },
                else => return errors.ExpectingDotOrStarAfterSymbol,
            }
        }
    }

    fn takeSymbolAfter(self: *Parser, line_no: usize, column_no: usize) ?Get {
        if (self.tokens.getAfter(line_no, column_no)) |symbol| {
            if (symbol.token.kind == lx.TokenTag.Symbol) {
                return symbol;
            }
        }
        return null;
    }

    fn takeSymbolAfterWithTag(self: *Parser, line_no: usize, column_no: usize, tag: lx.SymbolTag) ?Get {
        if (self.takeSymbolAfter(line_no, column_no)) |symbol| {
            if (symbol.token.tag == tag) {
                return symbol;
            }
        }
        return null;
    }

    fn takeStarFrom(self: *Parser, allocator: Allocator, from: TokenRef, line_no: usize, column_no: usize) !void {
        const tag = self.takeSymbolAfter(line_no, column_no) orelse
            return errors.ExpectingSymbolAfterStar;

        const one = self.takeSymbolAfter(tag.token.line_no, tag.token.end_column_no) orelse
            return errors.ExpectingSymbolAfterStarAction;

        const two: ?Get = findtwo: {
            if (self.tokens
                .getAfter(one.token.line_no, one.token.end_column_no)) |star|
            {
                if (star.token.kind == lx.TokenTag.Star) {
                    if (self.takeSymbolAfter(star.token.line_no, star.token.end_column_no)) |toand| {
                        if (toand.token.tag == lx.SymbolTag.and_) {
                            break :findtwo self.takeSymbolAfter(toand.token.line_no, toand.token.end_column_no);
                        }
                        if (toand.token.tag == lx.SymbolTag.to) {
                            break :findtwo self.takeSymbolAfter(toand.token.line_no, toand.token.end_column_no);
                        }
                    }
                }
            }
            break :findtwo null;
        };

        var next = two orelse one;

        next = findbecomes: {
            if (self.tokens
                .getAfter(next.token.line_no, next.token.end_column_no)) |star|
            {
                if (star.token.kind == lx.TokenTag.Star) {
                    if (self.takeSymbolAfterWithTag(star.token.line_no, star.token.end_column_no, lx.SymbolTag.becomes)) |becomes|
                        break :findbecomes becomes;
                }
            }
            return errors.ExpectingBecomesAfterStarAction;
        };

        const to =
            self.takeSymbolAfter(next.token.line_no, next.token.end_column_no) orelse
            return errors.ExpectingSymbolAfterStarAction;

        const tworef = if (two) |ref| ref.ref else 0;

        const becomes = Becomes{
            .from = from,
            .to = to.ref,
            .action = .{ .tag = tag.ref, .one = one.ref, .two = tworef },
        };

        try self.instructions.append(allocator, .{ .becomes = self.becomes.items.len });
        try self.becomes.append(allocator, becomes);
    }

    fn takeDotFrom(self: *Parser, allocator: Allocator, from: TokenRef, line_no: usize, column_no: usize) !void {
        const tag = self.takeSymbolAfter(line_no, column_no) orelse
            return errors.ExpectingSymbolAfterDot;

        const one = self.takeSymbolAfter(tag.token.line_no, tag.token.end_column_no) orelse
            return errors.ExpectingSymbolAfterDotAction;

        const two: ?Get = findtwo: {
            if (self.tokens
                .getAfter(one.token.line_no, one.token.end_column_no)) |star|
            {
                if (star.token.kind == lx.TokenTag.Star) {
                    if (self.takeSymbolAfter(star.token.line_no, star.token.end_column_no)) |toand| {
                        if (toand.token.tag == lx.SymbolTag.and_) {
                            break :findtwo self.takeSymbolAfter(toand.token.line_no, toand.token.end_column_no);
                        }
                        if (toand.token.tag == lx.SymbolTag.to) {
                            break :findtwo self.takeSymbolAfter(toand.token.line_no, toand.token.end_column_no);
                        }
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

        return program;
    }

    const Slice = struct { off: usize, len: usize };
    const GetSlice = struct { token: []lx.Token, slice: Slice };
    const Get = struct { token: lx.Token, ref: TokenRef };
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

        fn getAfter(self: *Tokens, line_no: usize, after_column: usize) ?Get {
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
}
