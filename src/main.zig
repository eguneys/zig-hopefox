const std = @import("std");
const LiveOrchRunner = @import("orch_runner.zig").LiveOrchRunner;

pub fn main(init: std.process.Init) !void {
    var stdout = std.Io.File.stdout().writer(init.io, &.{});
    try stdout.interface.print("GofChess Meta v0.0.0\n", .{});

    var gpa: std.heap.DebugAllocator(.{}) = .init;
    const allocator = gpa.allocator();

    const liveOrch = try LiveOrchRunner.init(init.io, allocator, "analysis.orch");
    defer liveOrch.deinit(allocator);
}

test "imports" {
    _ = @import("dot/table.zig");
    _ = @import("dot/tree.zig");
    _ = @import("dot/chess/types.zig");
    _ = @import("dot/chess/san.zig");
    _ = @import("dot/lexer2.zig");
    _ = @import("dot/parser2.zig");
    _ = @import("dot/runner2.zig");
    _ = @import("dot/usage2.zig");

    _ = @import("orch2/lexer.zig");
    _ = @import("orch2/parser.zig");

    _ = @import("db_file.zig");
}
