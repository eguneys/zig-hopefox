const std = @import("std");
const cp = @import("compilation.zig");
const chess = @import("chess/types.zig");
const atomic = @import("atomic_filters.zig");

const Runner = struct {
    compiled: cp.CompiledProgram,

    history: std.ArrayList(chess.Position),

    empty_row: []const chess.Bitboard,

    fn init(allocator: std.mem.Allocator, text: []const u8) !Runner {
        var compilation = cp.Compilation.init(allocator);
        defer compilation.deinit();
        try compilation.parse(text);
        const compiled = try compilation.compile(allocator);
        var empty_row_list = try std.ArrayList(chess.Bitboard)
            .initCapacity(allocator, compiled.table.columns.len);
        errdefer empty_row_list.deinit(allocator);
        for (0..empty_row_list.capacity) |i| {
            _ = i;
            try empty_row_list.append(allocator, chess.Bitboard.All);
        }
        const empty_row = try empty_row_list.toOwnedSlice(allocator);
        return .{
            .compiled = compiled,
            .history = .empty,
            .empty_row = empty_row,
        };
    }

    fn deinit(self: *Runner, allocator: std.mem.Allocator) void {
        self.history.deinit(allocator);
        allocator.free(self.empty_row);
        self.compiled.deinit(allocator);
    }

    const RunputNodeBuilder = struct {
        depth: usize,
        children: ?std.ArrayList(RunputNodeBuilder),
        nodes: std.ArrayList(RunputNode),

        fn init(allocator: std.mem.Allocator, depth: usize, node: RunputNode) !RunputNodeBuilder {
            var nodes = try std.ArrayList(RunputNode).initCapacity(allocator, 1);
            errdefer nodes.deinit(allocator);

            try nodes.append(allocator, node);

            return .{
                .depth = depth,
                .nodes = nodes,
                .children = null,
            };
        }

        fn toOwnedPut() !?RunputNode {
            return null;
        }

        fn deinit() void {}
    };

    fn runOnPosition(self: *Runner, allocator: std.mem.Allocator, position: chess.Position) !RunputNode {
        self.history.clearAndFree(allocator);
        self.compiled.table.clearAndFree(allocator);

        self.history.append(allocator, position);
        try self.compiled.table.appendRow(allocator, self.empty_row);

        const runput_builder = RunputNodeBuilder.init(allocator);
        errdefer runput_builder.deinit();

        var range = .{ .start = 0, .end = 1 };
        for (self.compiled.blocks) |block| {
            for (block.descriptions) |description| {
                range = try self.run_lines_on_range(allocator, description.bound_lines, range);

                if (range.start == range.end) {
                    break;
                }
            }
        }

        return runput_builder.toOwnedPut();
    }

    fn run_lines_on_range(self: *Runner, allocator: std.mem.Allocator, bound_lines: [][]const atomic.AtomicCall, range: Range) !Range {
        const start = self.history.items.len;
        for (bound_lines) |line| {
            for (line) |call| {
                try atomic.CallRunner.call(allocator, self.history, self.table, range, call);
            }
        }
        const end = self.history.items.len;
        return .{ .start = start, .end = end };
    }
};

const Range = struct { start: usize, end: usize };

const RunputNode = struct { depth: usize, put: Runput, children: ?[]RunputNode };

const Runput = struct { range: Range };

test "basic usage" {
    const ally = std.testing.allocator;

    const script =
        \\ ###
        \\
        \\if hello(king, queen)
        \\ve hello2(king, queen, bishop_rook)
        \\
        \\ def hello(From, To)
        \\   captures(From)
        \\
        \\def hello2(From, To, Captured_X)
    ;
    var runner = try Runner.init(ally, script);
    defer runner.deinit(ally);
}
