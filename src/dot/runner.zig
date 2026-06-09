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

    empty_row: []chess.Bitboard,
    position: chess.Position,

    pub fn deinit(self: *History, allocator: Allocator) void {
        self.program.deinit(allocator);
        self.table.deinit(allocator);
        self.tree.deinit(allocator);
        self.nodes.deinit(allocator);
        allocator.free(self.empty_row);
    }

    pub fn init(allocator: Allocator, program: par.Program, capacity: usize) !History {
        var symbols = try ArrayList(lx.Symbol).initCapacity(allocator, 10);
        errdefer symbols.deinit(allocator);

        var empty_row = try ArrayList(chess.Bitboard).initCapacity(allocator, 10);
        errdefer empty_row.deinit(allocator);

        for (program.symbols) |ref| {
            const symbol = program.tokens[ref];
            try symbols.append(allocator, symbol.identity.symbol);

            try empty_row.append(allocator, chess.Bitboard.All);
        }

        var self: History = undefined;
        self.table = try Table(lx.Symbol, chess.Bitboard).init(allocator, try symbols.toOwnedSlice(allocator), capacity);
        self.tree = try Tree(chess.Move).init(allocator);
        self.nodes = try ArrayList(usize).initCapacity(allocator, capacity);
        self.program = program;
        self.empty_row = try empty_row.toOwnedSlice(allocator);
        return self;
    }

    pub fn addMove(self: *History, allocator: Allocator, off: usize, move: chess.Move) !void {
        try self.nodes.append(allocator, try self.tree.addChild(allocator, off, move));
    }

    pub fn load_position(self: *History, allocator: Allocator, position: chess.Position) !void {
        self.table.clearRetainingCapacity();
        try self.table.appendRow(allocator, self.empty_row);
        self.nodes.clearRetainingCapacity();

        try self.nodes.append(allocator, 0);
        self.position = position;
    }
};

pub const Runner = struct {
    history: History,
    slices: ArrayList(Slice),

    pub const Slice = struct { off: usize, len: usize, instruction: usize };

    pub fn deinit(self: *Runner, allocator: Allocator) void {
        self.history.deinit(allocator);
        self.slices.deinit(allocator);
    }

    pub fn init(allocator: Allocator, program: par.Program, capacity: usize) !Runner {
        return .{
            .slices = try ArrayList(Slice).initCapacity(allocator, 10),
            .history = try History.init(allocator, program, capacity),
        };
    }

    pub fn runOnPosition(self: *Runner, allocator: Allocator, position: chess.Position) ![]Slice {
        try self.history.load_position(allocator, position);

        self.slices.clearRetainingCapacity();

        for (self.history.program.instructions, 0..self.history.program.instructions.len) |dotorstar, i| {
            switch (dotorstar) {
                .dot => {
                    try Matcher.run_dot(allocator, self.history, dotorstar.dot);
                },
                .star => {
                    std.debug.print("asf", .{});
                    var slice: Slice = undefined;
                    slice.off = self.history.nodes.items.len;
                    try Matcher.run_star(allocator, self.history, dotorstar.star);
                    slice.len = self.history.nodes.items.len - slice.off;
                    slice.instruction = i;
                    try self.slices.append(allocator, slice);
                },
            }
        }
        return self.slices.items;
    }
};

test "basic usage" {
    const ally = testing.allocator;

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
    errdefer program.deinit(ally);

    var runner = try Runner.init(
        ally,
        program,
        1024,
    );
    defer runner.deinit(ally);

    const slices = try runner.runOnPosition(ally, chess.Parses.white(
        \\........
        \\........
        \\........
        \\........
        \\........
        \\........
        \\........
        \\........
    ));

    try std.testing.expectEqual(0, slices.len);
}
