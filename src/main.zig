const std = @import("std");
const types = @import("types.zig");

pub fn main() !void {
    std.debug.print("All your {s} are belong to us.\n", .{"codebase"});

    _ = types.Fen.parse(types.Fen.Initial);
}
