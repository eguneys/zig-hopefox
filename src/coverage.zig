const std = @import("std");
const DotUsage = @import("dot/usage.zig").DotUsage;
const chess = @import("dot/chess/types.zig");
const DbReader = @import("db_file.zig").DbReader;

pub const DotCoverageOutput = struct {
    pub fn write(allocator: std.mem.Allocator, db_reader: *DbReader, dot: *DotUsage, writer: *std.Io.File.Writer) !void {
        const position = try db_reader.readPosition(0);
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
};
