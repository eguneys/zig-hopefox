const std = @import("std");
//const file = @import("file.zig");
const LiveFile = @import("live_file.zig").LiveFile;

pub fn main(init: std.process.Init) !void {
    var stdout = std.Io.File.stdout().writer(init.io, &.{});
    try stdout.interface.print("GofChess Meta v0.0.0\n", .{});
    //try file.BuildDb.read_csv_to_build_db_if_doesnt_exists(init.io, "data/athousand_sorted.csv", "data/athousand.pos.db", "data/athousand.meta.db");

    var gpa: std.heap.DebugAllocator(.{}) = .init;
    const allocator = gpa.allocator();

    const db_path = "data/athousand.pos.db";
    const meta_path = "data/athousand.meta.db";
    const script_path = "scripts/script1.gof";
    const output_path = "scripts/script1.output";
    var live = try LiveFile.open(init.io, db_path, meta_path, script_path, output_path);

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
