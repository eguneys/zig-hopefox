const std = @import("std");

pub const LiveFile = struct {
    file_path: []const u8,

    last_mtime: i128 = 0,

    const poll_interval_ms: u64 = 1000;

    pub fn open(path: []const u8) !LiveFile {
        return LiveFile{ .file_path = path };
    }

    const Self = @This();

    pub fn loop(self: *Self, io: std.Io, allocator: std.mem.Allocator, stdout: *std.Io.File.Writer) !void {
        try stdout.interface.print("Watching '{s} for changes...\n", .{self.script_path});

        // 2. Continuous loop
        while (true) {
            // 3. Stat the file to check metadata
            const stat = std.Io.Dir.cwd().statFile(io, self.script_path, .{}) catch |err| {
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
                try self.processFile(allocator, stdout);
            }

            // 5. Sleep between checks
            try std.Io.sleep(io, std.Io.Duration.fromMilliseconds(Self.poll_interval_ms), std.Io.Clock.awake);
        }
    }

    fn processFile(self: *Self, allocator: std.mem.Allocator, stdout: *std.Io.File.Writer) !void {
        try self.script_reader.seekTo(0);
        if (try self.script_reader.interface.takeDelimiter(0)) |content| {
            try stdout.interface.print("{s} changed\n", .{self.script_path});
            try self.processContent(allocator, content);
        }
    }

    fn processContent(self: *Self, allocator: std.mem.Allocator, content: []const u8) !void {
        try self.output_writer.seekTo(0);
        var dot = DotUsage.init(allocator, content) catch {
            std.debug.print("coludn't parse gof script", .{});
            try self.writeContent("couldn't parse gof script");
            try self.flush_output();
            return;
        };

        try DotCoverageOutput.write(allocator, &self.db_reader, &dot, &self.output_writer);

        try self.flush_output();
    }

    fn writeContent(self: *Self, content: []const u8) !void {
        _ = try self.output_writer.interface.write(content);
    }

    fn flush_output(self: *Self) !void {
        try self.output_writer.end();
    }
};

test "basic usage" {}
