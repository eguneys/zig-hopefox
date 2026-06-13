const std = @import("std");
const DotUsage = @import("dot/usage2.zig").DotUsage;
const chess = @import("dot/chess/types.zig");
const DbReader = @import("db_file.zig").DbReader;

pub const DotCoverageOutput = struct {
    pub fn write(allocator: std.mem.Allocator, db_reader: *DbReader, dot: *DotUsage, writer: *std.Io.File.Writer) !void {
        for (0..db_reader.header.count) |i| {
            if (i > 0) _ = try writer.interface.write("\n");

            const position = try db_reader.readPosition(i);
            const meta = try db_reader.readMeta(i);
            const meta_id: [5]u8 = @bitCast(meta.id);
            _ = try writer.interface.write("https://lichess.org/training/");
            _ = try writer.interface.write(&meta_id);
            _ = try writer.interface.write("\n");
            dot.runner.runOnPosition(allocator, position) catch {
                _ = try writer.interface.write("Error running position");
                return;
            };

            const output = dot.printLines(allocator) catch {
                _ = try writer.interface.write("Error writing output");
                return;
            };
            _ = try writer.interface.write(output);
        }
    }
};
