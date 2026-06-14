const std = @import("std");

pub const ReadFile = struct {
    buffer: []const u8,
    content: []const u8,

    pub fn readCapacity(io: std.Io, path: []const u8, capacity: usize) ReadFile {
        const buffer = [capacity]u8;
        var result: ReadFile = .{ .buffer = buffer, .content = undefined };
        const script_file = try std.Io.Dir.cwd().openFile(io, path, .{ .mode = .read_only });
        const script_reader = script_file.reader(io, result.buffer);

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
