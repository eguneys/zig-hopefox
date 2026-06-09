const std = @import("std");
const file = @import("file.zig");

pub fn main(init: std.process.Init) !void {
    var stdout = std.Io.File.stdout().writer(init.io, &.{});
    try stdout.interface.print("GofChess Meta v0.0.0\n", .{});
    //try file.BuildDb.read_csv_to_build_db_if_doesnt_exists(init.io, "data/athousand_sorted.csv", "data/athousand.pos.db", "data/athousand.meta.db");
}

test "imports" {
    //_ = @import("file.zig");
}
