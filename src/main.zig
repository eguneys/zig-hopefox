const std = @import("std");
const chess = @import("chess/types.zig");
const file = @import("file.zig");
const gof = @import("gof/types.zig");

pub fn main(init: std.process.Init) !void {
    var stdout = std.Io.File.stdout().writer(init.io, &.{});
    try stdout.interface.print("GofChess Meta v0.0.0\n", .{});
    //try file.BuildDb.read_csv_to_build_db_if_doesnt_exists(init.io, "data/athousand_sorted.csv", "data/athousand.pos.db", "data/athousand.meta.db");

    var gpa: std.heap.DebugAllocator(.{}) = .init;
    try gof.Usage.usage("hello world", gpa.allocator());
}
