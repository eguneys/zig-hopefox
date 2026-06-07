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

    pub fn deinit(self: VisualNode, allocator: std.mem.Allocator) void {
        if (self.children) |children|
            allocator.free(children);
        self.visual.deinit(allocator);
    }
};

const Visual: type = struct {
    tags: []parser.SemanticDescriptionTag,
    line: parser.DescriptionLine,
    lines: []tre.Line,

    pub fn deinit(self: Visual, allocator: std.mem.Allocator) void {
        allocator.free(self.tags);
        for (self.lines) |line| line.deinit(allocator);
        allocator.free(self.lines);
    }
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
                .line = runner.compilation.linesFor(put.line_no),
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

pub const Prints = struct {
    pub fn fromVisualNode(allocator: std.mem.Allocator, visual_node: VisualNode) ![]const u8 {
        var list = try std.ArrayList(u8).initCapacity(allocator, 300);
        errdefer list.deinit(allocator);
        const visual = try Prints.fromVisual(allocator, visual_node.visual);
        defer allocator.free(visual);

        try list.appendSlice(allocator, visual);

        return try list.toOwnedSlice(allocator);
    }

    pub fn fromVisual(allocator: std.mem.Allocator, visual: Visual) ![]const u8 {
        var list = try std.ArrayList(u8).initCapacity(allocator, 300);
        errdefer list.deinit(allocator);
        const dline = try Prints.fromDescriptionLine(allocator, visual.line);
        defer allocator.free(dline);
        try list.appendSlice(allocator, dline);

        if (visual.lines.len > 0) {
            try list.appendSlice(allocator, " { ");
        }
        var sep: []const u8 = "";
        for (visual.lines) |line| {
            const str_line = try tre.Prints.fromLine(allocator, line);
            defer allocator.free(str_line);

            try list.appendSlice(allocator, sep);
            try list.appendSlice(allocator, str_line);
            sep = " ";
        }
        if (visual.lines.len > 0) {
            try list.appendSlice(allocator, " }");
        }

        return try list.toOwnedSlice(allocator);
    }

    pub fn fromDescriptionLine(allocator: std.mem.Allocator, line: parser.DescriptionLine) ![]const u8 {
        var list = try std.ArrayList(u8).initCapacity(allocator, 300);
        errdefer list.deinit(allocator);

        // if
        try list.appendSlice(allocator, line.binding.value);
        try list.append(allocator, ' ');
        try list.appendSlice(allocator, line.name.value);
        try list.append(allocator, '(');
        var sep: []const u8 = "";
        for (line.arguments) |argument| {
            if (argument.kind == parser.TokenType.Underscore) {
                try list.append(allocator, '_');
                sep = "";
                continue;
            }
            try list.appendSlice(allocator, sep);
            try list.appendSlice(allocator, argument.value);
            sep = ", ";
        }
        try list.append(allocator, ')');

        return try list.toOwnedSlice(allocator);
    }
};

test "hello" {
    const ally = std.testing.allocator;

    const script =
        \\ ###
        \\
        \\if captures(pawn, pawn2_pawn3)
        \\
        \\ def captures(From, Captured_To)
        \\   captures(From, To, Captured)
        \\
    ;
    var runner = try rr.Runner.init(ally, script);
    defer runner.deinit(ally);

    const runput = try runner.runOnPosition(ally, chess.Parses.white(
        \\........
        \\........
        \\........
        \\........
        \\....p...
        \\...P....
        \\........
        \\........
    ));
    defer runput.deinit(ally);

    try std.testing.expect(runput.children != null);
    const node = try VisualBuilder.build(ally, runner, runput.children.?[0]);
    defer node.deinit(ally);

    const res = try Prints.fromVisualNode(ally, node);
    defer ally.free(res);
    try std.testing.expectEqualStrings(
        \\if captures(pawn, pawn2_pawn3) { dxe4 exd3 }
    , res);
}
