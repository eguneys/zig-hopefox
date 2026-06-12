const std = @import("std");
const testing = std.testing;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const Table = @import("table.zig").Table;
const Tree = @import("tree.zig").Tree;
const chess = @import("chess/types.zig");
const lx = @import("lexer2.zig");
const par = @import("parser2.zig");
const Matcher = @import("matcher2.zig").Matcher;
const log = @import("logs.zig");

pub const History = struct {
    program: par.ParsedProgram,
    table: Table(lx.SymbolIdentity, chess.Bitboard),
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
        var symbols: ArrayList(par.SymbolNameId) = .empty;
        errdefer symbols.deinit(allocator);

        var empty_row: ArrayList(chess.Bitboard) = .empty;
        errdefer empty_row.deinit(allocator);

        for (program.symbols) |ref| {
            try symbols.append(allocator, ref.nameId);
            try empty_row.append(allocator, chess.Bitboard.All);
        }

        var self: History = undefined;
        self.table = try Table(par.SymbolNameId, chess.Bitboard).init(allocator, try symbols.toOwnedSlice(allocator), capacity);
        self.tree = try Tree(chess.Move).init(allocator);
        self.nodes = .empty
        self.program = program;
        self.empty_row = try empty_row.toOwnedSlice(allocator);
        return self;
    }

    pub fn getPosition(self: History, off: usize) chess.Position {
        var position = self.position;
        const reversed_moves = self.tree.getHistoryReversed(off);

        for (0..reversed_moves.len) |i| {
            const move = self.tree.getNode(reversed_moves[reversed_moves.len - 1 - i]).value;
            _ = position.make_move(move);
            position.flipTurn();
        }
        return position;
    }

    pub fn addMove(self: *History, allocator: Allocator, off: usize, move: chess.Move) !void {
        try self.nodes.append(allocator, try self.tree.addChild(allocator, off, move));
    }

    pub fn load_position(self: *History, allocator: Allocator, position: chess.Position) !void {
        try self.tree.clearRetainingCapacity(allocator);

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

    pub fn runOnPosition(self: *Runner, allocator: Allocator, position: chess.Position) !void {
        try self.history.load_position(allocator, position);

        self.slices.clearRetainingCapacity();

        var slice = Matcher.Slice{ .len = 1, .off = 0 };
        for (0..self.history.program.instructions.len) |i| {
            const instruction = self.history.program.instructions[i];
            const begin_off = self.history.nodes.items.len;
            switch (instruction) {
                .becomes => {
                    try Matcher.run_dot(allocator, self.history, slice, self.history.program.becomes[instruction.becomes]);
                },
                .sideEffects => {
                    try Matcher.run_star(allocator, &self.history, slice, self.history.program.side_effects[instruction.sideEffects]);
                    const end_off = self.history.nodes.items.len;
                    try self.slices.append(allocator, .{ .off = begin_off, .len = end_off - begin_off, .instruction = i });
                },
            }
            slice.off = begin_off;
            slice.len = self.history.nodes.items.len - begin_off;
        }
    }

    pub fn getLineNo(self: Runner, off_instruction: usize) usize {
        const instruction = self.history.program.instructions[off_instruction];
        const star = self.history.program.stars[instruction.star];
        const token = self.history.program.tokens[star.starword];
        return token.line_no;
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

    try runner.runOnPosition(ally, chess.Parses.white(
        \\........
        \\........
        \\........
        \\........
        \\........
        \\........
        \\........
        \\........
    ));

    const slices = runner.slices.items;
    try std.testing.expectEqual(0, slices.len);
}
