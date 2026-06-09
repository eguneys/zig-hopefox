const std = @import("std");
const testing = std.testing;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const Table = @import("table.zig").Table;
const Tree = @import("tree.zig").Tree;
const chess = @import("chess/types.zig");
const lx = @import("lexer.zig");
const par = @import("parser.zig");
const Matcher = @import("matcher.zig").Matcher;

pub const History = struct {
    program: par.Program,
    table: Table(lx.Symbol, chess.Bitboard),
    tree: Tree(chess.Move),
    nodes: ArrayList(usize),

    pub fn deinit(self: *History, allocator: Allocator) void {
        self.table.deinit(allocator);
        self.tree.deinit(allocator);
        self.nodes.deinit(allocator);
    }

    pub fn init(allocator: Allocator, program: par.Program, capacity: usize) !History {
        var symbols = try ArrayList(lx.Symbol).initCapacity(allocator, 10);
        errdefer symbols.deinit(allocator);

        for (program.symbols) |ref| {
            const symbol = program.tokens[ref];
            try symbols.append(allocator, symbol.identity.symbol);
        }

        var self: History = undefined;
        self.table = try Table(lx.Symbol, chess.Bitboard).init(allocator, try symbols.toOwnedSlice(allocator), capacity);
        self.tree = try Tree(chess.Move).init(allocator);
        self.nodes = try ArrayList(usize).initCapacity(allocator, capacity);
        self.program = program;
        return self;
    }

    pub fn addMove(self: *History, allocator: Allocator, off: usize, move: chess.Move) !void {
        try self.nodes.append(allocator, try self.tree.addChild(allocator, off, move));
    }
};

pub const Runner = struct {
    history: History,

    pub fn deinit(self: *Runner, allocator: Allocator) void {
        self.history.deinit(allocator);
    }

    pub fn init(allocator: Allocator, program: par.Program, capacity: usize) !Runner {
        return .{ .history = try History.init(allocator, program, capacity) };
    }

    pub fn runOnPosition(self: *Runner, allocator: Allocator, position: chess.Position) !void {
        self.history.load_position(position);

        for (self.program.instructions) |dotorstar| {
            switch (dotorstar) {
                .dot => {
                    Matcher.run_dot(allocator, self.history, dotorstar.dot);
                },
                .star => {
                    Matcher.run_star(allocator, self.history, dotorstar.star);
                },
            }
        }
    }
};

test "basic usage" {
    const ally = std.testing.allocator;

    var lexer = lx.Lexer{};
    defer lexer.deinit(ally);
    try lexer.appendScript(ally,
        \\
        \\
        \\
    );
    const tokens = try lexer.toOwnedSlice(ally);
    defer ally.free(tokens);
    var builder = try par.ProgramBuilder.init(ally, tokens);
    defer builder.deinit(ally);

    const program = try builder.build(ally);
    defer program.deinit(ally);

    var runner = try Runner.init(
        ally,
        program,
        1024,
    );
    defer runner.deinit(ally);
}
