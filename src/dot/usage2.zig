const std = @import("std");
const testing = std.testing;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const chess = @import("chess/types.zig");
const san = @import("chess/san.zig");
const Runner = @import("runner2.zig").Runner;
const lx = @import("lexer2.zig");
const par = @import("parser2.zig");
const log = @import("logs.zig");

const Visual = struct {
    builder: san.PrintBuilder,
    buffer: ArrayList(u8),

    fn deinit(self: *Visual, allocator: Allocator) void {
        self.builder.deinit(allocator);
        self.buffer.deinit(allocator);
    }

    fn init(allocator: Allocator) !Visual {
        return .{
            .builder = try san.PrintBuilder.init(allocator),
            .buffer = try ArrayList(u8).initCapacity(allocator, 0),
        };
    }

    fn resetPosition(self: *Visual, position: chess.Position) void {
        self.builder.resetPosition(position);
        self.buffer.clearRetainingCapacity();
    }

    fn beginLine(self: *Visual, allocator: Allocator, position: chess.Position) !void {
        self.builder.resetPosition(position);
        try self.buffer.append(allocator, '{');
    }

    fn appendMove(self: *Visual, allocator: Allocator, move: chess.Move) !void {
        try self.builder.appendMove(allocator, move);
    }

    fn endLine(self: *Visual, allocator: Allocator) !void {
        try self.buffer.appendSlice(allocator, self.builder.string.items);
        try self.buffer.append(allocator, '}');
    }
};

test "visual" {
    const ally = testing.allocator;

    var visual = try Visual.init(ally);
    defer visual.deinit(ally);

    const position = chess.Fen.parse(chess.Fen.Initial);
    visual.resetPosition(position);

    try visual.beginLine(ally, position);
    try visual.appendMove(ally, san.Uci.move("e2e4").toMove(position));
    try visual.appendMove(ally, san.Uci.move("e7e5").toMove(position));
    try visual.appendMove(ally, san.Uci.move("b1f3").toMove(position));
    try visual.endLine(ally);
    try visual.beginLine(ally, position);
    try visual.appendMove(ally, san.Uci.move("e2e4").toMove(position));
    try visual.appendMove(ally, san.Uci.move("e7e5").toMove(position));
    try visual.appendMove(ally, san.Uci.move("b1f3").toMove(position));
    try visual.endLine(ally);

    try testing.expectEqualSlices(u8, "{e4 e5 Nf3}{e4 e5 Nf3}", visual.buffer.items);
}

pub const DotUsage = struct {
    runner: Runner,
    visual: Visual,
    buffer: ArrayList(u8),

    move_buffer: ArrayList(chess.Move),

    pub fn deinit(self: *DotUsage, allocator: Allocator) void {
        self.runner.deinit(allocator);
        self.visual.deinit(allocator);
        self.buffer.deinit(allocator);
        self.move_buffer.deinit(allocator);
    }

    pub fn init(allocator: Allocator, script: []const u8) !DotUsage {
        var builder = try par.Parser.init(allocator, script);
        defer builder.deinit(allocator);

        const program = try builder.toOwnedProgram(allocator);

        return .{
            .move_buffer = .empty,
            .buffer = try std.ArrayList(u8).initCapacity(allocator, 1024),
            .runner = try Runner.init(allocator, program),
            .visual = try Visual.init(allocator),
        };
    }

    pub fn printInstructionLine(self: *DotUsage, allocator: Allocator, slice: Runner.Slice) ![]const u8 {
        self.visual.resetPosition(self.runner.history.position);

        for (slice.off..slice.off + slice.len) |i| {
            const history = self.runner.history.tree.getHistoryReversed(i);
            try self.visual.beginLine(allocator, self.runner.history.position);
            for (0..history.len) |j| {
                const move = self.runner.history.tree.getNode(history[history.len - 1 - j]).value;
                try self.visual.appendMove(allocator, move);
            }
            try self.visual.endLine(allocator);
        }
        try self.buffer.appendSlice(allocator, self.visual.buffer.items);

        return self.buffer.items;
    }

    pub fn clearBuffer(self: *DotUsage) void {
        self.buffer.clearRetainingCapacity();
    }

    pub fn printLines(self: *DotUsage, allocator: Allocator) ![]const u8 {
        self.clearBuffer();
        for (self.runner.slices.items) |slice| {
            if (self.buffer.items.len > 0) {
                try self.buffer.append(allocator, '\n');
            }

            var buf: [64]u8 = undefined;

            const str_line_no = try std.fmt.bufPrint(&buf, "{d}: ", .{self.runner.getLineNo(slice.instruction)});
            try self.buffer.appendSlice(allocator, str_line_no);
            _ = try self.printInstructionLine(allocator, slice);
        }
        return self.buffer.items;
    }

    pub fn getLastLine(self: *DotUsage, allocator: Allocator) ![]const chess.Move {
        self.move_buffer.clearRetainingCapacity();
        for (0..self.runner.slices.items.len) |i| {
            const slice = self.runner.slices.items[self.runner.slices.items.len - 1 - i];
            if (slice.len > 0) {
                const history = self.runner.history.tree.getHistoryReversed(slice.off);
                for (0..history.len) |j| {
                    const move = self.runner.history.tree.getNode(history[history.len - 1 - j]).value;
                    if (move.isNone()) continue;
                    try self.move_buffer.append(allocator, move);
                }
                break;
            }
        }
        return self.move_buffer.items;
    }

    const Slice = struct { off: usize, len: usize };
    pub fn getLastLines(self: *DotUsage, allocator: Allocator) ![]Slice {
        var result: ArrayList(Slice) = .empty;
        errdefer result.deinit(allocator);

        self.move_buffer.clearRetainingCapacity();
        for (0..self.runner.slices.items.len) |i| {
            const slice = self.runner.slices.items[self.runner.slices.items.len - 1 - i];
            if (slice.len > 0) {
                for (slice.off..slice.off + slice.len) |k| {
                    const result_off = self.move_buffer.items.len;
                    const history = self.runner.history.tree.getHistoryReversed(k);
                    for (0..history.len) |j| {
                        const move = self.runner.history.tree.getNode(history[history.len - 1 - j]).value;
                        if (move.isNone()) continue;
                        try self.move_buffer.append(allocator, move);
                    }
                    const len = self.move_buffer.items.len - result_off;
                    try result.append(allocator, .{ .off = result_off, .len = len });
                }
                break;
            }
        }
        return result.toOwnedSlice(allocator);
    }

    pub fn isFull(self: *DotUsage) bool {
        return self.runner.slices.items[self.runner.slices.items.len - 1].len > 0;
    }
};

test "basic usage" {
    const ally = testing.allocator;

    var usage = try DotUsage.init(ally,
        \\
        \\pawn *Captures pawn2 *becomes pawn3
        \\
    );

    defer usage.deinit(ally);

    try usage.runner.runOnPosition(ally, chess.Parses.white(
        \\........
        \\........
        \\........
        \\........
        \\....p...
        \\...P....
        \\........
        \\........
    ));

    const slices = usage.runner.slices.items;
    try testing.expectEqual(1, slices.len);

    try testing.expectEqual(1, slices.len);
    try testing.expectEqual(1, slices[0].off);
    try testing.expectEqual(2, slices[0].len);
    try testing.expectEqual(1, usage.runner.history.nodes.items[slices[0].off]);

    try testing.expectEqualSlices(u8, "{dxe4}{exd3}", try usage.printInstructionLine(ally, slices[0]));

    try testing.expectEqualSlices(u8, "2: {dxe4}{exd3}", try usage.printLines(ally));
}

test "multi line" {
    const ally = testing.allocator;

    var usage = try DotUsage.init(ally,
        \\
        \\bishop *Captures pawn *becomes bishop2
        \\pawn2 *Captures bishop2 *becomes pawn3
        \\
    );

    defer usage.deinit(ally);

    try usage.runner.runOnPosition(ally, chess.Parses.white(
        \\........
        \\........
        \\..b.....
        \\........
        \\....p...
        \\...P....
        \\........
        \\........
    ));

    const slices = usage.runner.slices.items;
    try testing.expectEqual(2, slices.len);

    try testing.expectEqual(1, slices[0].off);
    try testing.expectEqual(1, slices[0].len);
    try testing.expectEqual(1, usage.runner.history.nodes.items[slices[0].off]);

    try testing.expectEqualSlices(u8, "{Bxe4}", try usage.printInstructionLine(ally, slices[0]));

    try testing.expectEqual(1, slices[1].len);

    try testing.expectEqualSlices(u8,
        \\2: {Bxe4}
        \\3: {Bxe4 dxe4}
    , try usage.printLines(ally));
}
