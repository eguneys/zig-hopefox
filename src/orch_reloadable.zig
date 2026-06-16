const std = @import("std");
const Allocator = std.mem.Allocator;
const OrchFile = @import("orch_file.zig").OrchFile;

pub const LiveFileW = struct {
    io: std.Io,
    orch_file: OrchFile,
    orch_path: []const u8,

    const Self = @This();

    pub fn deinit(self: *Self, allocator: Allocator) void {
        self.orch_file.deinit(allocator);
        allocator.free(self.orch_path);
    }

    fn reloadOrchFile(self: *Self, allocator: Allocator) !void {
        const orch_file = try OrchFile.init(self.io, allocator, self.orch_path);
        self.orch_file = orch_file;
    }

    pub fn reload(self: *Self, allocator: Allocator) !void {
        var new_orch = try OrchFile.init(
            self.io,
            allocator,
            self.orch_path,
        );
        errdefer new_orch.deinit(allocator);

        self.orch_file.deinit(allocator);
        self.orch_file = new_orch;
    }

    pub fn open(io: std.Io, allocator: Allocator, path: []const u8) !Self {
        const orch_path = try std.mem.join(allocator, "/", &[2][]const u8{ path, "analysis.orch" });

        var self = LiveFileW{ .io = io, .orch_path = orch_path, .orch_file = undefined };

        try self.reloadOrchFile(allocator);

        return self;
    }

    pub fn step(self: *LiveFileW, allocator: Allocator) !void {
        try self.orch_file.step(allocator);
    }
};

test "basic usage 2" {
    const ally = std.testing.allocator;

    var live_w = try LiveFileW.open(std.testing.io, ally, "scripts");
    defer live_w.deinit(ally);

    try live_w.step(ally);

    try live_w.reloadOrchFile(ally);
}
