const std = @import("std");
const LiveReloadable = @import("orch_live.zig").LiveOrchFile;

pub fn main(init: std.process.Init) !void {
    var stdout = std.Io.File.stdout().writer(init.io, &.{});
    try stdout.interface.print("GofChess Meta v0.0.0\n", .{});

    var gpa: std.heap.DebugAllocator(.{}) = .init;
    const allocator = gpa.allocator();

    var live_r = try LiveReloadable.open(init.io, allocator, "scripts");
    defer live_r.deinit(allocator);

    try live_r.loop(init.io, allocator);
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

    _ = @import("orch/parser.zig");

    _ = @import("db_file.zig");
}
