const std = @import("std");
const OrchFile = @import("orch_file.zig").OrchFile;

pub const LiveOrchFile = struct {
    file_path: []const u8,

    orch_file: OrchFile,

    last_mtime: i128 = 0,

    const poll_interval_ms: u64 = 1000;

    pub fn deinit(self: *LiveOrchFile, allocator: std.mem.Allocator) void {
        self.orch_file.deinit(allocator);
    }

    pub fn open(io: std.Io, allocator: std.mem.Allocator, path: []const u8) !LiveOrchFile {
        const orch_path = try std.mem.join(allocator, "/", &[2][]const u8{ path, "analysis.orch" });
        const orch_file = try OrchFile.init(io, allocator, orch_path);

        return LiveOrchFile{ .file_path = path, .orch_file = orch_file };
    }

    const Self = @This();

    pub fn loop(self: *Self, io: std.Io, allocator: std.mem.Allocator) !void {
        // 2. Continuous loop
        while (true) {
            // 3. Stat the file to check metadata
            const stat = std.Io.Dir.cwd().statFile(io, self.file_path, .{}) catch |err| {
                // Handle error (e.g., file doesn't exist yet)
                if (err == error.FileNotFound) {
                    try std.Io.sleep(io, std.Io.Duration.fromMilliseconds(Self.poll_interval_ms), std.Io.Clock.awake);
                    continue;
                }
                return err;
            };

            // 4. If the modification time changes, process the file
            const mtime = stat.mtime.toMilliseconds();
            if (mtime != self.last_mtime) {
                self.last_mtime = mtime;

                try self.orch_file.step(allocator);
            }

            // 5. Sleep between checks
            try std.Io.sleep(io, std.Io.Duration.fromMilliseconds(Self.poll_interval_ms), std.Io.Clock.awake);
        }
    }
};

test "basic usage" {}
