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
    program: par.Program,
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

    pub fn init(allocator: Allocator, program: par.Program) !History {
        var empty_row: ArrayList(chess.Bitboard) = .empty;
        errdefer empty_row.deinit(allocator);

        var table = try Table(lx.SymbolIdentity, chess.Bitboard).init(allocator);
        errdefer table.deinit(allocator);

        for (program.symbols) |ref| {
            if (try table.addColumn(allocator, ref.identity)) {
                try empty_row.append(allocator, chess.Bitboard.All);
            }
        }

        var tree = try Tree(chess.Move).init(allocator);
        errdefer tree.deinit(allocator);

        const empty_row_slice = try empty_row.toOwnedSlice(allocator);
        errdefer allocator.free(empty_row_slice);

        return .{ .table = table, .tree = tree, .nodes = .empty, .program = program, .empty_row = empty_row_slice, .position = undefined };
    }

    pub fn getPosition(self: History, off: usize) chess.Position {
        var position = self.position;
        const reversed_moves = self.tree.getHistoryReversed(off);

        for (0..reversed_moves.len) |i| {
            const move = self.tree.getNode(reversed_moves[reversed_moves.len - 1 - i]).value;
            if (move.isNone()) {
                continue;
            }
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

    pub fn init(allocator: Allocator, program: par.Program) !Runner {
        return .{
            .slices = try ArrayList(Slice).initCapacity(allocator, 10),
            .history = try History.init(allocator, program),
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
                .sideEffects => {
                    try Matcher.run_dot(allocator, &self.history, slice, self.history.program.side_effects[instruction.sideEffects]);

                    const end_off = self.history.nodes.items.len;
                    try self.slices.append(allocator, .{ .off = begin_off, .len = end_off - begin_off, .instruction = i });
                },
                .becomes => {
                    try Matcher.run_star(allocator, &self.history, slice, self.history.program.becomes[instruction.becomes]);
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
        const action_tag = switch (instruction) {
            .sideEffects => self.history.program.side_effects[instruction.sideEffects].action.tag,
            .becomes => self.history.program.becomes[instruction.becomes].action.tag,
        };
        const symbol = self.history.program.symbols[action_tag];
        const token = self.history.program.tokens[symbol.token];
        return token.line_no;
    }
};

test "basic usage" {
    const ally = testing.allocator;

    var parser = try par.Parser.init(ally, "");
    defer parser.deinit(ally);

    const program = try parser.toOwnedProgram(ally);

    var runner = try Runner.init(
        ally,
        program,
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
