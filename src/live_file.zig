const std = @import("std");

pub const FileWatcher = struct {
    filename: []const u8,
    last_mtime: i128 = 0,

    const poll_interval_ms: u64 = 1000;

    pub fn init(filename: []const u8) FileWatcher {
        return .{ .filename = filename };
    }

    pub fn loop(self: FileWatcher, allocator: std.mem.Allocator) !void {
        const stdout = std.io.getStdOut().writer();
        try stdout.print("Watching '{s}' for changes...\n", .{self.filename});

        // 2. Continuous loop
        while (true) {
            // 3. Stat the file to check metadata
            const stat = std.fs.cwd().statFile(self.filename) catch |err| {
                // Handle error (e.g., file doesn't exist yet)
                if (err == error.FileNotFound) {
                    std.time.sleep(poll_interval_ms * std.time.ns_per_ms);
                    continue;
                }
                return err;
            };

            // 4. If the modification time changes, process the file
            if (stat.mtime != self.last_mtime) {
                self.last_mtime = stat.mtime;
                try self.processFile(allocator);
            }

            // 5. Sleep between checks
            std.time.sleep(poll_interval_ms * std.time.ns_per_ms);
        }
    }

    fn processFile(self: FileWatcher, allocator: std.mem.Allocator, stdout: *std.Writer) !void {
        // 6. Open and read the whole file
        const file = try std.fs.cwd().openFile(self.filename, .{ .mode = .read_only });
        defer file.close();

        // Read the file entirely (adjust size limit as needed)
        const content = try file.readToEndAlloc(allocator, 1024 * 1024);
        defer allocator.free(content);

        // 7. Do something on change
        try stdout.print("\n--- File updated at ---\n{s}\n", .{content});
    }
};

test "basic usage" {}
