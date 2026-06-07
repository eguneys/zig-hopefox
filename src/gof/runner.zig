const std = @import("std");
const cp = @import("compilation.zig");
const chess = @import("chess/types.zig");
const atomic = @import("atomic_filters.zig");

const Runner = struct {
    compilation: cp.Compilation,
    compiled: cp.CompiledProgram,
    history: std.ArrayList(chess.Position),
    empty_row: []const chess.Bitboard,

    fn init(allocator: std.mem.Allocator, text: []const u8) !Runner {
        var compilation = cp.Compilation.init(allocator);
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
            .compilation = compilation,
            .compiled = compiled,
            .history = .empty,
            .empty_row = empty_row,
        };
    }

    fn deinit(self: *Runner, allocator: std.mem.Allocator) void {
        self.compilation.deinit();
        self.history.deinit(allocator);
        allocator.free(self.empty_row);
        self.compiled.deinit(allocator);
    }

    const RunputNodeBuilder = struct {
        depth: usize,
        children: ?std.ArrayList(RunputNodeBuilder),
        runput: Runput,

        fn init(depth: usize, runput: Runput) !RunputNodeBuilder {
            return .{
                .depth = depth,
                .runput = runput,
                .children = null,
            };
        }

        fn getParentRangeForDepth(self: RunputNodeBuilder, depth: usize) Range {
            if (self.children) |children| {
                const last = children.getLast();
                if (last.depth < depth) {
                    return last.getParentRangeForDepth(depth);
                }
            }
            return self.runput.range;
        }

        fn appendAtDepth(self: *RunputNodeBuilder, allocator: std.mem.Allocator, depth: usize, runput: Runput) !void {
            if (self.children) |*children| {
                var last = children.getLast();

                if (last.depth == depth) {
                    try children.append(allocator, try RunputNodeBuilder.init(depth, runput));
                } else {
                    try last.appendAtDepth(allocator, depth, runput);
                }
            } else {
                self.children = try std.ArrayList(RunputNodeBuilder).initCapacity(allocator, 1);
                try self.children.?.append(allocator, try RunputNodeBuilder.init(depth, runput));
            }
        }

        const MapBuilder = struct {
            pub fn mapAllocator(allocator: std.mem.Allocator, builder: *RunputNodeBuilder) !?RunputNode {
                const children =
                    if (builder.children) |list| here: {
                        var result = try std.ArrayList(RunputNode).initCapacity(allocator, list.items.len);
                        for (list.items) |*item| {
                            if (try MapBuilder.mapAllocator(allocator, item)) |result_item|
                                try result.append(allocator, result_item);
                        }
                        break :here try result.toOwnedSlice(allocator);
                    } else null;

                return .{
                    .depth = builder.depth,
                    .put = builder.runput,
                    .children = children,
                };
            }
        };

        fn toOwnedPut(self: *RunputNodeBuilder, allocator: std.mem.Allocator) !RunputNode {
            const children =
                if (self.children) |*list| here: {
                    var result = try std.ArrayList(RunputNode).initCapacity(allocator, list.items.len);
                    for (list.items) |*item| {
                        if (try MapBuilder.mapAllocator(allocator, item)) |result_item|
                            try result.append(allocator, result_item);
                    }
                    list.deinit(allocator);
                    break :here try result.toOwnedSlice(allocator);
                } else null;
            return .{
                .depth = self.depth,
                .put = self.runput,
                .children = children,
            };
        }

        fn deinit(self: RunputNodeBuilder) void {
            _ = self;
        }
    };

    fn runOnPosition(self: *Runner, allocator: std.mem.Allocator, position: chess.Position) !RunputNode {
        self.history.clearAndFree(allocator);
        self.compiled.table.clearAndFree(allocator);

        try self.history.append(allocator, position);
        try self.compiled.table.appendRow(allocator, self.empty_row);

        var runput_builder = try RunputNodeBuilder.init(0, .{ .range = .{ .start = 0, .end = 1 }, .line_no = 0 });
        errdefer runput_builder.deinit();

        for (self.compiled.blocks) |block| {
            for (block.descriptions) |description| {
                const range = runput_builder.getParentRangeForDepth(description.depth);
                const new_range = try self.run_lines_on_range(allocator, description.bound_lines, range);
                if (new_range.start == new_range.end) {
                    break;
                }
                // 0 1
                // if aasdf 1 5
                //   if aflksaf
                //   if asldfkj
                // if asldkf
                try runput_builder.appendAtDepth(allocator, description.depth, .{ .range = new_range, .line_no = description.line_no });
            }
        }

        return try runput_builder.toOwnedPut(allocator);
    }

    fn run_lines_on_range(self: *Runner, allocator: std.mem.Allocator, bound_lines: [][]const cp.AtomicCall, range: Range) !Range {
        const start = self.history.items.len;
        for (bound_lines) |line| {
            for (line) |call| {
                try atomic.CallRunner.atomic_call(allocator, &self.history, &self.compiled.table, range, call);
            }
        }
        const end = self.history.items.len;
        return .{ .start = start, .end = end };
    }
};

pub const Range = struct { start: usize, end: usize };

const RunputNode = struct {
    depth: usize,
    put: Runput,
    children: ?[]RunputNode,

    pub fn deinit(self: RunputNode, allocator: std.mem.Allocator) void {
        if (self.children) |children| {
            for (children) |child| child.deinit(allocator);
            allocator.free(children);
        }
    }
};

const Runput = struct { range: Range, line_no: usize };

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

    _ = try runner.runOnPosition(ally, chess.Position.empty());
}

test "check 1" {
    const ally = std.testing.allocator;

    const script =
        \\ ###
        \\
        \\if captures(king, queen_king2)
        \\
        \\ def captures(From, Captured_To)
        \\   captures(From, To, Captured)
        \\
    ;
    var runner = try Runner.init(ally, script);
    defer runner.deinit(ally);

    const res = try runner.runOnPosition(ally, chess.Parses.white(
        \\........
        \\........
        \\........
        \\........
        \\........
        \\........
        \\........
        \\kq......
    ));
    defer res.deinit(ally);

    try std.testing.expect(res.children != null);
    try std.testing.expectEqual(1, res.children.?.len);
    try std.testing.expectEqual(1, res.children.?[0].put.range.start);
    try std.testing.expectEqual(2, res.children.?[0].put.range.end);

    try std.testing.expectEqualStrings(
        \\........
        \\........
        \\........
        \\........
        \\........
        \\........
        \\........
        \\.k......
    , &chess.Prints.position(runner.history.items[1]));
}
