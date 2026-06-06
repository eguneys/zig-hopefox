const std = @import("std");
const chess = @import("gof/chess/types.zig");
const file = @import("file.zig");
const parser = @import("gof/parser.zig");

pub fn main(init: std.process.Init) !void {
    var stdout = std.Io.File.stdout().writer(init.io, &.{});
    try stdout.interface.print("GofChess Meta v0.0.0\n", .{});
    //try file.BuildDb.read_csv_to_build_db_if_doesnt_exists(init.io, "data/athousand_sorted.csv", "data/athousand.pos.db", "data/athousand.meta.db");
}

test "imports" {
    _ = @import("gof/chess/types.zig");
    //_ = @import("file.zig");
    _ = @import("gof/parser.zig");
    _ = @import("gof/compilation.zig");
    _ = @import("gof/runner.zig");
}
