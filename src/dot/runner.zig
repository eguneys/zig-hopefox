const std = @import("std");
const testing = std.testing;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const Table = @import("table.zig").Table;
const lx = @import("lexer.zig");
const par = @import("parser.zig");
const sym = @import("symbols.zig");
const Tree = @import("tree.zig");
const chess = @import("chess/types.zig");

pub const History = struct {
    program: par.Program,
    table: Table(lx.Symbol),
    tree: Tree(chess.Move),
    nodes: ArrayList(usize),

    pub fn deinit(self: *History, allocator: Allocator) void {
        self.table.deinit(allocator);
        self.tree.deinit(allocator);
        self.nodes.deinit(allocator);
    }

    pub fn init(allocator: Allocator, program: par.Program, capacity: usize) !History {
        const symbols = try ArrayList(sym.DescriptionSymbol).initCapacity(10);
        errdefer symbols.deinit(allocator);

        for (program.symbols) |ref| {
            const symbol = program.tokens[ref];
            symbols.append(allocator, symbol.identity.symbol);
        }

        var self: History = undefined;
        self.table = try Table(sym.DescriptionSymbol).init(allocator, try symbols.toOwnedSlice(allocator), capacity);
        self.tree = .{};
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

    pub fn init(allocator: Allocator, capacity: usize, program: par.Program) !Runner {
        return .{ .history = History.init(allocator, program, capacity) };
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

test "basic usage" {}
