const std = @import("std");
const testing = std.testing;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const chess = @import("chess/types.zig");
const Runner = @import("runner.zig").Runner;
const lx = @import("lexer.zig");
const par = @import("parser.zig");

pub const DotUsage = struct {
    runner: Runner,

    pub fn deinit(self: *DotUsage, allocator: Allocator) void {
        self.runner.deinit(allocator);
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

        return .{ .runner = try Runner.init(
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

    const slices = try usage.runner.runOnPosition(ally, chess.Parses.white(
        \\........
        \\........
        \\........
        \\........
        \\....P...
        \\...p....
        \\........
        \\........
    ));

    try testing.expectEqual(1, slices.len);
}
