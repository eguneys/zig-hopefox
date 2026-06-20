const std = @import("std");

pub fn FileWatcher(ChangeHandler: type) type {
    return struct {
        file_path: []const u8,

        io: std.Io,
        dir: std.Io.Dir,

        last_mtime: i128 = 0,

        handler: ChangeHandler,

        const poll_interval_ms: u64 = 1000;

        pub fn init(io: std.Io, dir: std.Io.Dir, path: []const u8, handler: ChangeHandler) Self {
            return .{ .io = io, .dir = dir, .file_path = path, .handler = handler };
        }

        const Self = @This();

        pub fn loop(self: *Self, allocator: std.mem.Allocator) !void {
            // 2. Continuous loop
            while (true) {
                var should_run_step = false;
                // 3. Stat the file to check metadata
                const stat = self.dir.statFile(self.io, self.file_path, .{}) catch |err| {
                    // Handle error (e.g., file doesn't exist yet)
                    if (err == error.FileNotFound) {
                        try std.Io.sleep(self.io, std.Io.Duration.fromMilliseconds(Self.poll_interval_ms), std.Io.Clock.awake);
                        continue;
                    }
                    return err;
                };

                // 4. If the modification time changes, process the file
                const mtime = stat.mtime.toMilliseconds();
                if (mtime != self.last_mtime) {
                    self.last_mtime = mtime;

                    should_run_step = true;
                }

                if (should_run_step) {
                    try self.handler.step(allocator);
                }
                // 5. Sleep between checks
                try std.Io.sleep(self.io, std.Io.Duration.fromMilliseconds(Self.poll_interval_ms), std.Io.Clock.awake);
            }
        }
    };
}
