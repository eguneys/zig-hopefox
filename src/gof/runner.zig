const std = @import("std");
const cp = @import("compilation.zig");
const chess = @import("chess/types.zig");
const atomic = @import("atomic_filters.zig");
const tre = @import("chess/tree.zig");

pub const Runner = struct {
    compilation: cp.Compilation,
    compiled: cp.CompiledProgram,
    history: std.ArrayList(*tre.PositionNode),
    empty_row: []const chess.Bitboard,

    pub fn init(allocator: std.mem.Allocator, text: []const u8) !Runner {
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

    pub fn deinit(self: *Runner, allocator: std.mem.Allocator) void {
        self.compilation.deinit();
        if (self.history.items.len > 0) {
            self.history.items[0].deinit(allocator);
        }
        self.history.deinit(allocator);
        allocator.free(self.empty_row);
        self.compiled.deinit(allocator);
    }

    pub fn movesFor(self: Runner, allocator: std.mem.Allocator, range: Range) ![]tre.Line {
        var lines = try std.ArrayList(tre.Line).initCapacity(allocator, range.end - range.start);
        errdefer lines.deinit(allocator);

        for (range.start..range.end) |i| {
            if (try self.history.items[i].movesToRoot(allocator)) |line|
                try lines.append(allocator, line);
        }

        return try lines.toOwnedSlice(allocator);
    }

    const RunputNodeBuilder = struct {
        depth: usize,
        children: std.ArrayList(RunputNodeBuilder),
        runput: Runput,

        fn init(depth: usize, runput: Runput) !RunputNodeBuilder {
            return .{
                .depth = depth,
                .runput = runput,
                .children = .empty,
            };
        }

        fn getParentRangeForDepth(self: RunputNodeBuilder, depth: usize) Range {
            if (self.children.getLastOrNull()) |last| {
                if (last.depth < depth) {
                    return last.getParentRangeForDepth(depth);
                }
            }
            return self.runput.range;
        }

        fn appendAtDepth(self: *RunputNodeBuilder, allocator: std.mem.Allocator, depth: usize, runput: Runput) !void {
            if (self.children.items.len > 0) {
                const last = &self.children.items[self.children.items.len - 1];
                if (last.depth == depth) {
                    try self.children.append(allocator, try RunputNodeBuilder.init(depth, runput));
                } else {
                    try last.appendAtDepth(allocator, depth, runput);
                    std.debug.print("After last append {d}", .{last.children.items.len});
                    std.debug.print("After last append self.children {d}", .{self.children.items.len});
                    std.debug.print("After last append self.children[0] {d}", .{self.children.items[0].children.items.len});
                }
            } else {
                try self.children.append(allocator, try RunputNodeBuilder.init(depth, runput));
            }
        }

        const MapBuilder = struct {
            pub fn mapAllocator(allocator: std.mem.Allocator, builder: *RunputNodeBuilder) !?RunputNode {
                const children = here: {
                    var list = builder.children;
                    var result = try std.ArrayList(RunputNode).initCapacity(allocator, list.items.len);
                    for (list.items) |*item| {
                        if (try MapBuilder.mapAllocator(allocator, item)) |result_item|
                            try result.append(allocator, result_item);
                    }
                    list.deinit(allocator);
                    break :here try result.toOwnedSlice(allocator);
                };

                return .{
                    .depth = builder.depth,
                    .put = builder.runput,
                    .children = children,
                };
            }
        };

        fn toOwnedPut(self: *RunputNodeBuilder, allocator: std.mem.Allocator) !RunputNode {
            const children = here: {
                var list = &self.children;
                var result = try std.ArrayList(RunputNode).initCapacity(allocator, list.items.len);
                for (list.items) |*item| {
                    if (try MapBuilder.mapAllocator(allocator, item)) |result_item|
                        try result.append(allocator, result_item);
                }
                list.deinit(allocator);
                break :here try result.toOwnedSlice(allocator);
            };
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

    pub fn runOnPosition(self: *Runner, allocator: std.mem.Allocator, position: chess.Position) !RunputNode {
        if (self.history.items.len > 0) {
            self.history.items[0].deinit(allocator);
        }
        self.history.clearAndFree(allocator);
        self.compiled.table.clearAndFree(allocator);

        const root = try tre.PositionNode.root(allocator, position);
        errdefer root.deinit(allocator);
        try self.history.append(allocator, root);
        try self.compiled.table.appendRow(allocator, self.empty_row);

        var runput_builder = try RunputNodeBuilder.init(0, .{ .range = .{ .start = 0, .end = 1 }, .line_no = 0 });
        errdefer runput_builder.deinit();

        for (self.compiled.blocks) |block| {
            for (block.descriptions) |description| {
                try self.run_description(allocator, &runput_builder, description);
            }
        }

        return try runput_builder.toOwnedPut(allocator);
    }

    fn run_description(self: *Runner, allocator: std.mem.Allocator, runput_builder: *RunputNodeBuilder, description: cp.CompiledDescription) !void {
        const range = runput_builder.getParentRangeForDepth(description.depth);
        const new_range = try self.run_lines_on_range(allocator, description.bound_lines, range);
        if (new_range.start == new_range.end) {
            return;
        }
        // 0 1
        // if aasdf 1 5
        //   if aflksaf
        //   if asldfkj
        // if asldkf
        std.debug.print("\nAppend at depth: {d}\n", .{description.depth});
        try runput_builder.appendAtDepth(allocator, description.depth, .{ .range = new_range, .line_no = description.line_no });
        std.debug.print("\n{d} nb children {d}\n", .{ runput_builder.children.items[0].depth, runput_builder.children.items[0].children.items.len });

        if (description.children) |children| {
            for (children) |child| {
                try self.run_description(allocator, runput_builder, child);
            }
        }
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

pub const RunputNode = struct {
    depth: usize,
    put: Runput,
    children: []RunputNode,

    pub fn deinit(self: RunputNode, allocator: std.mem.Allocator) void {
        for (self.children) |child| child.deinit(allocator);
        allocator.free(self.children);
    }
};

pub const Runput = struct { range: Range, line_no: usize };

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

    const res = try runner.runOnPosition(ally, chess.Position.empty());
    defer res.deinit(ally);
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

    try std.testing.expectEqual(1, res.children.len);
    try std.testing.expectEqual(1, res.children[0].put.range.start);
    try std.testing.expectEqual(2, res.children[0].put.range.end);

    try std.testing.expectEqualStrings(
        \\........
        \\........
        \\........
        \\........
        \\........
        \\........
        \\........
        \\.k......
    , &chess.Prints.position(runner.history.items[1].position));
}
