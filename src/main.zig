const std = @import("std");
const orun = @import("orch_runner.zig");
const LiveOrchRunner = @import("orch_runner.zig").LiveOrchRunner;

pub fn main(init: std.process.Init) !void {
    var stderr = std.Io.File.stderr().writer(init.io, &.{});
    var stdout = std.Io.File.stdout().writer(init.io, &.{});
    try stdout.interface.print("GofChess Meta v0.0.0\n", .{});

    var gpa: std.heap.DebugAllocator(.{}) = .init;
    const allocator = gpa.allocator();

    const args: std.process.Args = undefined;
    var iterator = try args.iterateAllocator(allocator);
    defer iterator.deinit();

    const scripts_path = iterator.next() orelse "scripts";

    var liveOrch = LiveOrchRunner.init(init.io, allocator, scripts_path, "analysis.orch") catch |err| {
        switch (err) {
            orun.errors.OrchFileNotFound => {
                try stderr.interface.print("scripts/analysis.orch file not found.\n", .{});
            },
            orun.errors.ScriptsDirectoryNotFound => {
                try stderr.interface.print("'scripts/' folder not found. Please create a 'scripts/' folder and place analysis.orch in there.\n", .{});
            },
            else => {
                try stderr.interface.print("An error occured, please check your scripts folder.\n", .{});
            },
        }
        return err;
    };
    defer liveOrch.deinit(allocator);

    liveOrch.passStep(allocator) catch |err| {
        try stderr.interface.print("An error occured, please check your scripts folder.\n", .{});
        return err;
    };

    try stdout.interface.print("bye\n", .{});
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
