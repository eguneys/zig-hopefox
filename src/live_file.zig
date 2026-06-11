const std = @import("std");

pub const FileWatcher = struct {
    filename: []const u8,
    last_mtime: i128 = 0,

    const poll_interval_ms: u64 = 1000;

    pub fn init(filename: []const u8) FileWatcher {
        return .{ .filename = filename };
    }

    pub fn loop(self: *FileWatcher, io: std.Io, allocator: std.mem.Allocator, stdout: *std.Io.File.Writer) !void {
        try stdout.interface.print("Watching '{s} for changes...\n", .{self.filename});

        // 2. Continuous loop
        while (true) {
            // 3. Stat the file to check metadata
            const stat = std.Io.Dir.cwd().statFile(io, self.filename, .{}) catch |err| {
                // Handle error (e.g., file doesn't exist yet)
                if (err == error.FileNotFound) {
                    try std.Io.sleep(io, std.Io.Duration.fromMilliseconds(FileWatcher.poll_interval_ms), std.Io.Clock.awake);
                    continue;
                }
                return err;
            };

            // 4. If the modification time changes, process the file
            const mtime = stat.mtime.toMilliseconds();
            if (mtime != self.last_mtime) {
                self.last_mtime = mtime;
                try self.processFile(io, allocator, stdout);
            }

            // 5. Sleep between checks
            try std.Io.sleep(io, std.Io.Duration.fromMilliseconds(FileWatcher.poll_interval_ms), std.Io.Clock.awake);
        }
    }

    fn processFile(self: FileWatcher, io: std.Io, allocator: std.mem.Allocator, stdout: *std.Io.File.Writer) !void {
        // 6. Open and read the whole file
        const file = try std.Io.Dir.cwd().openFile(io, self.filename, .{ .mode = .read_only });
        defer file.close(io);

        // Read the file entirely (adjust size limit as needed)
        var buffer: [1024]u8 = undefined;
        var reader = file.reader(io, &buffer);

        const content = try reader.interface.readAlloc(allocator, 3);
        defer allocator.free(content);

        // 7. Do something on change
        try stdout.interface.print("\n--- File updated at ---\n{s}\n", .{content});
    }
};

test "basic usage" {}
