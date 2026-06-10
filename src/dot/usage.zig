const std = @import("std");
const testing = std.testing;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const chess = @import("chess/types.zig");
const san = @import("chess/san.zig");
const Runner = @import("runner.zig").Runner;
const lx = @import("lexer.zig");
const par = @import("parser.zig");

pub const DotUsage = struct {
    runner: Runner,
    prints: san.Prints,

    pub fn deinit(self: *DotUsage, allocator: Allocator) void {
        self.runner.deinit(allocator);
        self.prints.deinit(allocator);
    }

    pub fn init(allocator: Allocator, script: []const u8) !DotUsage {
        var lexer = lx.Lexer{};
        defer lexer.deinit(allocator);
        try lexer.appendScript(allocator, script);
        const tokens = try lexer.toOwnedSlice(allocator);
        defer allocator.free(tokens);

        var builder = try par.ProgramBuilder.init(allocator, tokens);
        defer builder.deinit(allocator);

        const program = try builder.build(allocator);

        return .{ .prints = try san.Prints.init(allocator, 1024), .runner = try Runner.init(
            allocator,
            program,
            1024,
        ) };
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

    try testing.expectEqualSlices(usize, &[_]usize{1}, usage.runner.history.tree.getHistoryReversed(1));
    const move = san.San.fromMove(usage.runner.history.position, usage.runner.history.tree.flat.items[1].value);
    try testing.expectEqualSlices(u8, "dxe4", usage.prints.fromSan(move));
}
