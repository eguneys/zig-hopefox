const std = @import("std");
const OrchFile = @import("orch_file.zig").OrchFile;

pub const LiveOrchFile = struct {
    file_path: []const u8,

    orch_path: []const u8,
    watch_file_path1: ?[]const u8 = null,
    watch_file_path2: ?[]const u8 = null,

    io: std.Io,
    orch_file: OrchFile,

    last_mtime: i128 = 0,
    last_mtime2: i128 = 0,

    const poll_interval_ms: u64 = 1000;

    pub fn deinit(self: *LiveOrchFile, allocator: std.mem.Allocator) void {
        self.orch_file.deinit(allocator);
        allocator.free(self.orch_path);
    }

    fn reloadOrchFile(self: *LiveOrchFile, allocator: std.mem.Allocator) !void {
        //self.orch_file.deinit(allocator);

        const orch_file = try OrchFile.init(self.io, allocator, self.orch_path);
        self.orch_file = orch_file;
        self.watch_file_path2 = orch_file.mainline_script_path;
    }

    pub fn open(io: std.Io, allocator: std.mem.Allocator, path: []const u8) !LiveOrchFile {
        const orch_path = try std.mem.join(allocator, "/", &[2][]const u8{ path, "analysis.orch" });

        return LiveOrchFile{
            .io = io,
            .file_path = path,
            .orch_path = try allocator.dupe(u8, orch_path),
            .orch_file = undefined,
            .watch_file_path1 = orch_path,
        };
    }

    const Self = @This();

    pub fn loop(self: *Self, io: std.Io, allocator: std.mem.Allocator) !void {
        std.debug.print("Watching {?s} and {?s}..\n", .{ self.watch_file_path1, self.watch_file_path2 });
        // 2. Continuous loop
        while (true) {
            var should_run_step = false;
            // 3. Stat the file to check metadata
            if (self.watch_file_path1) |watch_file_path1| {
                const stat = std.Io.Dir.cwd().statFile(io, watch_file_path1, .{}) catch |err| {
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

                    std.debug.print("{s} changed, updating.\n", .{watch_file_path1});
                    try self.reloadOrchFile(allocator);
                    should_run_step = true;
                }
            }

            if (self.watch_file_path2) |watch_file_path2| {
                const stat = std.Io.Dir.cwd().statFile(io, watch_file_path2, .{}) catch |err| {
                    // Handle error (e.g., file doesn't exist yet)
                    if (err == error.FileNotFound) {
                        try std.Io.sleep(io, std.Io.Duration.fromMilliseconds(Self.poll_interval_ms), std.Io.Clock.awake);
                        continue;
                    }
                    return err;
                };

                // 4. If the modification time changes, process the file
                const mtime = stat.mtime.toMilliseconds();
                if (mtime != self.last_mtime2) {
                    self.last_mtime2 = mtime;

                    should_run_step = true;
                }
            }

            if (should_run_step) try self.orch_file.step(allocator);
            // 5. Sleep between checks
            try std.Io.sleep(io, std.Io.Duration.fromMilliseconds(Self.poll_interval_ms), std.Io.Clock.awake);
        }
    }
};

test "basic usage" {}
