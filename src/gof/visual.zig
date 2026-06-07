const std = @import("std");
const chess = @import("chess/types.zig");
const tre = @import("chess/tree.zig");
const san = @import("chess/san.zig");

const parser = @import("parser.zig");
const rr = @import("runner.zig");
const cc = @import("compilation.zig");

const VisualNode = struct {
    depth: usize,
    visual: Visual,
    children: ?[]VisualNode,
};

const Visual: type = struct {
    tags: []parser.SemanticDescriptionTag,
    line: []parser.Token,
    lines: ?[]tre.Line,
};

const VisualBuilder = struct {
    pub fn build(allocator: std.mem.Allocator, runner: rr.Runner, node: rr.RunputNode) !VisualNode {
        var builder = VisualNodeBuilder.init(0, try VisualNodeBuilder.visual_for(allocator, runner, node.put));
        errdefer builder.deinit(allocator);
        if (node.children) |children| {
            for (children) |child| {
                try builder.add_runput(allocator, runner, child);
            }
        }
        return try builder.toOwnedVisual(allocator);
    }

    const VisualNodeBuilder = struct {
        depth: usize,
        children: ?std.ArrayList(VisualNodeBuilder),
        visual: Visual,

        fn init(depth: usize, visual: Visual) VisualNodeBuilder {
            return .{
                .depth = depth,
                .visual = visual,
                .children = null,
            };
        }

        fn add_runput(self: *VisualNodeBuilder, allocator: std.mem.Allocator, runner: rr.Runner, node: rr.RunputNode) !void {
            try self.appendAtDepth(allocator, node.depth, try VisualNodeBuilder.visual_for(allocator, runner, node.put));
            if (node.children) |children| {
                for (children) |child| {
                    try self.add_runput(allocator, runner, child);
                }
            }
        }

        fn visual_for(allocator: std.mem.Allocator, runner: rr.Runner, put: rr.Runput) !Visual {
            const lines = try runner.movesFor(allocator, put.range);
            return .{
                .tags = runner.compilation.tagsFor(put.line_no),
                .line = try runner.compilation.linesFor(allocator, put.line_no),
                .lines = lines,
            };
        }

        fn appendAtDepth(self: *VisualNodeBuilder, allocator: std.mem.Allocator, depth: usize, visual: Visual) !void {
            if (self.children) |*children| {
                var last = children.getLast();

                if (last.depth == depth) {
                    try children.append(allocator, VisualNodeBuilder.init(depth, visual));
                } else {
                    try last.appendAtDepth(allocator, depth, visual);
                }
            } else {
                self.children = try std.ArrayList(VisualNodeBuilder).initCapacity(allocator, 1);
                try self.children.?.append(allocator, VisualNodeBuilder.init(depth, visual));
            }
        }

        const MapBuilder = struct {
            pub fn mapAllocator(allocator: std.mem.Allocator, builder: *VisualNodeBuilder) !?VisualNode {
                const children =
                    if (builder.children) |list| here: {
                        var result = try std.ArrayList(VisualNode).initCapacity(allocator, list.items.len);
                        for (list.items) |*item| {
                            if (try MapBuilder.mapAllocator(allocator, item)) |result_item|
                                try result.append(allocator, result_item);
                        }
                        break :here try result.toOwnedSlice(allocator);
                    } else null;

                return .{
                    .depth = builder.depth,
                    .visual = builder.visual,
                    .children = children,
                };
            }
        };

        fn toOwnedVisual(self: *VisualNodeBuilder, allocator: std.mem.Allocator) !VisualNode {
            const children =
                if (self.children) |*list| here: {
                    var result = try std.ArrayList(VisualNode).initCapacity(allocator, list.items.len);
                    for (list.items) |*item| {
                        if (try MapBuilder.mapAllocator(allocator, item)) |result_item|
                            try result.append(allocator, result_item);
                    }
                    list.deinit(allocator);
                    break :here try result.toOwnedSlice(allocator);
                } else null;
            return .{
                .depth = self.depth,
                .visual = self.visual,
                .children = children,
            };
        }

        fn deinit(self: VisualNodeBuilder, allocator: std.mem.Allocator) void {
            _ = self;
            _ = allocator;
        }
    };
};

test "hello" {
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
    var runner = try rr.Runner.init(ally, script);
    defer runner.deinit(ally);

    const runput = try runner.runOnPosition(ally, chess.Position.empty());

    try std.testing.expect(runput.children != null);
    const node = try VisualBuilder.build(ally, runner, runput.children.?[0]);

    _ = node;
}
