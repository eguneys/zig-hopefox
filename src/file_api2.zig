const std = @import("std");
const Allocator = std.mem.Allocator;

pub const FileReader = struct {
    pub fn readFileAlloc(io: std.Io, dir: std.Io.Dir, allocator: Allocator, sub_path: []const u8, limit: usize) ![]const u8 {
        const result = try std.Io.Dir.readFileAlloc(dir, io, sub_path, allocator, std.Io.Limit.limited(limit));
        return result;
    }
};

pub const FileWriter = struct {
    buffer: []u8,
    writer: std.Io.File.Writer,

    pub fn deinit(self: *FileWriter, allocator: Allocator) void {
        allocator.free(self.buffer);
    }

    pub fn end(self: *FileWriter) !void {
        try self.writer.end();
    }

    pub fn init(io: std.Io, dir: std.Io.Dir, allocator: Allocator, sub_path: []const u8, bufferSize: usize) !FileWriter {
        const buffer = try allocator.alloc(u8, bufferSize);
        var result = FileWriter{ .writer = undefined, .buffer = buffer };
        const output_file = try dir.createFile(io, sub_path, .{});
        result.writer = output_file.writer(io, result.buffer);
        return result;
    }

    pub fn seekTo(self: *FileWriter, offset: u64) !void {
        try self.writer.seekTo(offset);
    }

    pub fn write(self: *FileWriter, content: []const u8) !usize {
        return try self.writer.interface.write(content);
    }

    pub fn flush(self: *FileWriter) !void {
        try self.writer.interface.flush();
    }

    pub fn writeToFile(io: std.Io, dir: std.Io.Dir, allocator: Allocator, sub_path: []const u8, content: []const u8) !void {
        var writer = try FileWriter.init(io, dir, allocator, sub_path, content.len);
        defer writer.deinit(allocator);

        _ = try writer.write(content);
        try writer.end();
    }
};
