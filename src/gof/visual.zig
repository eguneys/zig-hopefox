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
    children: []VisualNode,

    pub fn deinit(self: VisualNode, allocator: std.mem.Allocator) void {
        for (self.children) |child| child.deinit(allocator);
        allocator.free(self.children);
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
        for (node.children) |child| {
            try builder.add_runput(allocator, runner, child);
        }
        return try builder.toOwnedVisual(allocator);
    }

    const VisualNodeBuilder = struct {
        depth: usize,
        children: std.ArrayList(VisualNodeBuilder),
        visual: Visual,

        fn init(depth: usize, visual: Visual) VisualNodeBuilder {
            return .{
                .depth = depth,
                .visual = visual,
                .children = .empty,
            };
        }

        fn add_runput(self: *VisualNodeBuilder, allocator: std.mem.Allocator, runner: rr.Runner, node: rr.RunputNode) !void {
            try self.appendAtDepth(allocator, node.depth, try VisualNodeBuilder.visual_for(allocator, runner, node.put));
            for (node.children) |child| {
                try self.add_runput(allocator, runner, child);
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
            if (self.children.items.len > 0) {
                const last = &self.children.items[self.children.items.len - 1];

                if (last.depth == depth) {
                    try self.children.append(allocator, VisualNodeBuilder.init(depth, visual));
                } else {
                    try last.appendAtDepth(allocator, depth, visual);
                }
            } else {
                self.children = try std.ArrayList(VisualNodeBuilder).initCapacity(allocator, 1);
                try self.children.append(allocator, VisualNodeBuilder.init(depth, visual));
            }
        }

        const MapBuilder = struct {
            pub fn mapAllocator(allocator: std.mem.Allocator, builder: *VisualNodeBuilder) !?VisualNode {
                const children =
                    here: {
                        const list = &builder.children;
                        var result = try std.ArrayList(VisualNode).initCapacity(allocator, list.items.len);
                        for (list.items) |*item| {
                            if (try MapBuilder.mapAllocator(allocator, item)) |result_item|
                                try result.append(allocator, result_item);
                        }
                        break :here try result.toOwnedSlice(allocator);
                    };

                return .{
                    .depth = builder.depth,
                    .visual = builder.visual,
                    .children = children,
                };
            }
        };

        fn toOwnedVisual(self: *VisualNodeBuilder, allocator: std.mem.Allocator) !VisualNode {
            const children = here: {
                const list = &self.children;
                var result = try std.ArrayList(VisualNode).initCapacity(allocator, list.items.len);
                for (list.items) |*item| {
                    if (try MapBuilder.mapAllocator(allocator, item)) |result_item|
                        try result.append(allocator, result_item);
                }
                list.deinit(allocator);
                break :here try result.toOwnedSlice(allocator);
            };
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

        if (visual_node.depth > 0) {
            try list.appendNTimes(allocator, ' ', visual_node.depth - 1);
        }
        try list.appendSlice(allocator, visual);
        for (visual_node.children) |child| {
            try list.append(allocator, '\n');
            const nested = try Prints.fromVisualNode(allocator, child);
            defer allocator.free(nested);
            try list.appendSlice(allocator, nested);
        }

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
            sep = " }{ ";
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

test "basic usage" {
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

    const node = try VisualBuilder.build(ally, runner, runput.children[0]);
    defer node.deinit(ally);

    const res = try Prints.fromVisualNode(ally, node);
    defer ally.free(res);
    try std.testing.expectEqualStrings(
        \\if captures(pawn, pawn2_pawn3) { dxe4 }{ exd3 }
    , res);
}
test "captures" {
    const script =
        \\ ###
        \\
        \\if captures(pawn, pawn2_pawn3)
        \\ if captures(pawn4, pawn3_pawn5)
        \\
        \\ def captures(From, Captured_To)
        \\   captures(From, To, Captured)
        \\
    ;

    try expectVisuals(
        \\if captures(pawn, pawn2_pawn3) { dxe4 }{ exd3 }{ exf5 }{ fxe4 }
        \\ if captures(pawn4, pawn3_pawn5)
    , script,
        \\........
        \\........
        \\........
        \\.....P..
        \\....p...
        \\...P....
        \\........
        \\........
    );
}
fn expectVisuals(expected: []const u8, script: []const u8, position: *const [71:0]u8) !void {
    const ally = std.testing.allocator;

    var runner = try rr.Runner.init(ally, script);
    defer runner.deinit(ally);

    const runput = try runner.runOnPosition(ally, chess.Parses.white(position));
    defer runput.deinit(ally);

    const node = try VisualBuilder.build(ally, runner, runput.children[0]);
    defer node.deinit(ally);

    const res = try Prints.fromVisualNode(ally, node);
    defer ally.free(res);
    try std.testing.expectEqualStrings(expected, res);
}
