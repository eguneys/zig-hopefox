const std = @import("std");
const dot_usage = @import("dot/usage.zig");
const chess = @import("dot/chess/types.zig");
const DbReader = @import("db_file.zig").DbReader;

pub const LiveFile = struct {
    script_path: []const u8,
    output_path: []const u8,

    script_file: std.Io.File,
    output_file: std.Io.File,

    script_reader: std.Io.File.Reader,
    output_writer: std.Io.File.Writer,

    output_buffer: [2048]u8,
    script_buffer: [2048]u8,

    db_reader: DbReader,
    last_mtime: i128 = 0,

    const poll_interval_ms: u64 = 1000;

    pub fn open(io: std.Io, db_path: []const u8, meta_path: []const u8, script_path: []const u8, output_path: []const u8) !LiveFile {
        var self: LiveFile = undefined;

        self.script_path = script_path;
        self.output_path = output_path;

        self.output_file = try std.Io.Dir.cwd().createFile(io, output_path, .{});

        self.output_writer = self.output_file.writer(io, &self.output_buffer);
        self.db_reader = try DbReader.open(io, db_path, meta_path);

        // 6. Open and read the whole file
        self.script_file = try std.Io.Dir.cwd().openFile(io, script_path, .{ .mode = .read_only });

        self.script_reader = self.script_file.reader(io, &self.script_buffer);

        return self;
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
        var dot = dot_usage.DotUsage.init(allocator, content) catch {
            try self.writeContent("couldn't parse gof script");
            return;
        };

        const position = try self.db_reader.readPosition(0);
        dot.runner.runOnPosition(allocator, position) catch {
            try self.writeContent("Error running position");
            return;
        };

        const output = dot.printLines(allocator) catch {
            try self.writeContent("Error writing output");
            return;
        };

        try self.writeContent(output);
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
