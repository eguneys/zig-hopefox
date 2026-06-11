const std = @import("std");
//const file = @import("file.zig");
const live_file = @import("live_file.zig");

pub fn main(init: std.process.Init) !void {
    var stdout = std.Io.File.stdout().writer(init.io, &.{});
    try stdout.interface.print("GofChess Meta v0.0.0\n", .{});
    //try file.BuildDb.read_csv_to_build_db_if_doesnt_exists(init.io, "data/athousand_sorted.csv", "data/athousand.pos.db", "data/athousand.meta.db");

    var gpa: std.heap.DebugAllocator(.{}) = .init;
    const allocator = gpa.allocator();

    var live = live_file.FileWatcher("scripts/script1.gof", "scripts/script1.output"){};

    try live.loop(init.io, allocator, &stdout);
}

test "imports" {
    _ = @import("dot/table.zig");
    _ = @import("dot/tree.zig");
    _ = @import("dot/chess/types.zig");
    _ = @import("dot/chess/san.zig");
    _ = @import("dot/lexer.zig");
    _ = @import("dot/parser.zig");
    _ = @import("dot/runner.zig");
    _ = @import("dot/usage.zig");
    _ = @import("dot/usage_tests1.zig");
}
