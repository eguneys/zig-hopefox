const std = @import("std");
const Allocator = std.mem.Allocator;
const OrchFile = @import("orch_file.zig").OrchFile;

fn watcherCallback(context: ?*anyopaque, event: fzwatch.Event) void {
    _ = context;
    _ = event;
}

fn watcherThread(watcher: *fzwatch.Watcher) !void {
    try watcher.start(.{});
}

pub const LiveOrchFile = struct {
    watcher: fzwatch.Watcher,

    orch_file: OrchFile,

    pub fn deinit(self: LiveOrchFile, allocator: Allocator) void {
        self.watcher.deinit();
        self.orch_file.deinit(allocator);
    }

    pub fn open(io: std.Io, allocator: Allocator, path: []const u8) LiveOrchFile {
        var watcher = try fzwatch.Watcher.init(allocator);

        const orch_file = OrchFile.init(io, allocator, path);
        watcher.setCallback(watcherCallback, orch_file);

        watcherThread(watcher);

        return .{ .watcher = watcher, .orch_file = orch_file };
    }
};

test "basic usage" {}
