const std = @import("std");

pub const ReadFile = struct {
    buffer: []u8,
    content: []const u8,

    pub fn deinit(self: *ReadFile, allocator: std.mem.Allocator) void {
        allocator.free(self.buffer);
    }

    pub fn readCapacity(io: std.Io, allocator: std.mem.Allocator, path: []const u8, capacity: usize) !ReadFile {
        _ = capacity;
        const buffer = try allocator.alloc(u8, 4096);
        var result: ReadFile = .{ .buffer = buffer, .content = undefined };
        const script_file = try (std.Io.Dir.cwd()
            .openFile(io, path, .{ .mode = .read_only }));
        var script_reader = script_file.reader(io, result.buffer);

        if (try script_reader.interface.takeDelimiter(0)) |content| {
            result.content = content;
        }

        return result;
    }
};

pub const WriteFile = struct {
    pub fn write(io: std.Io, path: []const u8, capacity: usize) !void {
        const buffer = [capacity]u8;

        var output_file = try std.Io.Dir.cwd().createFile(io, path, .{});
        var output_writer = output_file.writer(io, &buffer);

        output_writer.seekTo(0);
        output_writer.end();
    }
};

test "basic usage" {}
