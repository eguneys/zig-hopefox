const std = @import("std");
const dot_usage = @import("dot/usage.zig");
const chess = @import("dot/chess/types.zig");

pub fn FileWatcher(script_path: []const u8, output_path: []const u8) type {
    return struct {
        last_mtime: i128 = 0,

        const poll_interval_ms: u64 = 1000;

        const Self = @This();

        pub fn loop(self: *Self, io: std.Io, allocator: std.mem.Allocator, stdout: *std.Io.File.Writer) !void {
            try stdout.interface.print("Watching '{s} for changes...\n", .{script_path});

            // 2. Continuous loop
            while (true) {
                // 3. Stat the file to check metadata
                const stat = std.Io.Dir.cwd().statFile(io, script_path, .{}) catch |err| {
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
                    try Self.processFile(io, allocator, stdout);
                }

                // 5. Sleep between checks
                try std.Io.sleep(io, std.Io.Duration.fromMilliseconds(Self.poll_interval_ms), std.Io.Clock.awake);
            }
        }

        fn processFile(io: std.Io, allocator: std.mem.Allocator, stdout: *std.Io.File.Writer) !void {
            // 6. Open and read the whole file
            const file = try std.Io.Dir.cwd().openFile(io, script_path, .{ .mode = .read_only });
            defer file.close(io);

            // Read the file entirely (adjust size limit as needed)
            var buffer: [1024]u8 = undefined;
            var reader = file.reader(io, &buffer);

            if (try reader.interface.takeDelimiter(0)) |content| {
                try stdout.interface.print("{s} changed\n", .{script_path});
                try Self.processContent(io, allocator, content);
            }
        }

        fn processContent(io: std.Io, allocator: std.mem.Allocator, content: []const u8) !void {
            var dot = dot_usage.DotUsage.init(allocator, content) catch {
                try Self.writeContent(io, "couldn't parse gof script");
                return;
            };

            dot.runner.runOnPosition(allocator, chess.Parses.white(
                \\........
                \\...b....
                \\........
                \\.p...p..
                \\........
                \\...b....
                \\........
                \\........
            )) catch {
                try Self.writeContent(io, "Error running position");
                return;
            };

            const output = dot.printLines(allocator) catch {
                try Self.writeContent(io, "Error writing output");
                return;
            };
            try Self.writeContent(io, output);
        }

        fn writeContent(io: std.Io, content: []const u8) !void {
            const file = try std.Io.Dir.cwd().createFile(io, output_path, .{});
            defer file.close(io);

            var buffer: [1024]u8 = undefined;
            var writer = file.writer(io, &buffer);

            _ = try writer.interface.write(content);
            try writer.flush();
        }
    };
}

test "basic usage" {}
