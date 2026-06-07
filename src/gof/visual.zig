const std = @import("std");
const chess = @import("chess/types.zig");
const parser = @import("parser.zig");
const runner = @import("runner.zig");
const cc = @import("compilation.zig");


const VisualNode = struct {
    depth: usize,
    visual: Visual,
    children: ?[]VisualNode,
};

const Visual: type = struct {
    tags: []parser.SemanticDefinitionTag,
    line: []parser.Token,
    position: chess.Position,
    moves: ?[][]chess.SAN,
};

const VisualBuilder = struct {

    pub fn build(allocator: std.mem.Allocator, compilation: cc.Compilation, node: runner.RunputNode) !VisualBuilder {
        var builder = VisualNodeBuilder.init(0, VisualBuilder.visual_for(cc, node.put));
        for (node.children) |child| {
            add_runput(allocator, builder, compilation, child);
        }
        return builder.toOwnedVisual(allocator);
    }

    fn add_runput(allocator: std.mem.Allocator, builder: *VisualNodeBuilder, compilation: cc.Compilation, node: runner.RunputNode) {
        try builder.appendAtDepth(allocator, node.depth, VisualBuilder.visual_for(cc, node.put));
        for (node.children) |child| {
            add_runput(builder, child);
        }
    }

    fn visual_for(allocator: std.mem.Allocator, compilation: cc.Compilation, put: runner.Runput, position: Position) {
        const moves = VisualBuilder.find_moves_for_range(position, put.range);
        return .{
            .tags = compilation.tagsFor(put.line_no),
            .line = compilation.linesFor(put.line_no),
            .position = position,
            .moves = moves,
        };
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

    !VisualNodeBuilder {
        return .{
            .depth = depth,
            .visual = visual,
            .children = null,
        };
    }

    fn appendAtDepth(self: *VisualNodeBuilder, allocator: std.mem.Allocator, depth: usize, visual: Visual) !void {
        if (self.children) |*children| {
            var last = children.getLast();

            if (last.depth == depth) {
                try children.append(allocator, try VisualNodeBuilder.init(depth, visual));
            } else {
                try last.appendAtDepth(allocator, depth, visual);
            }
        } else {
            self.children = try std.ArrayList(VisualNodeBuilder).initCapacity(allocator, 1);
            try self.children.?.append(allocator, try VisualNodeBuilder.init(depth, visual));
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

    fn deinit(self: VisualNodeBuilder) void {
        _ = self;
    }
};
};