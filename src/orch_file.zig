const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const orch_lx = @import("orch/lexer.zig");
const orch = @import("orch/parser.zig");
const Orch = orch.Orch;
const files = @import("file_api.zig");
const ReadFile = files.ReadFile;
const WriteFile = files.WriteFile;
const DotUsage = @import("dot/usage2.zig").DotUsage;
const dfile = @import("db_file.zig");

const errors = error{InvalidPath};

pub const OrchFile = struct {
    pub const OrchFileCapacity = 2048;
    pub const ScriptFileCapacity = 4096;
    pub const OutputFileCapacity = 4096;

    orch: Orch,
    io: std.Io,

    pub fn deinit(self: *Self, allocator: Allocator) void {
        self.orch.deinit(allocator);
    }

    pub fn init(io: std.Io, allocator: Allocator, orch_path: []const u8) Self {
        const orch_file = files.ReadFile.readCapacity(io, orch_path, OrchFile.OrchFileCapacity);
        const orch_parser = try orch.Parser.init(allocator, orch_file.contents);
        orch_parser.parse(allocator);

        return .{ .io = io, .orch = orch_parser.toOwnedParse(allocator) };
    }

    const Self = @This();

    pub fn step(self: *Self, allocator: Allocator) !void {
        for (self.orch.dbs) |db| {
            for (db.variation) |variation| {
                DbVariationWriter.write(self.io, allocator, db, variation);
            }
        }
    }
};

pub const DbVariationWriter = struct {
    fn write(io: std.Io, allocator: Allocator, db: orch.Db, variation: orch.Variation) !void {
        const script_file = ReadFile.readCapacity(io, variation.script_path, OrchFile.ScriptFileCapacity);
        const db_reader = AllDbReaders.initFromPath(io, allocator, db.db_path);

        if (variation.output) |outputs| {
            for (outputs) |output| {
                try DbVariationWriter.writeOutput(io, allocator, db_reader, script_file, output);
            }
        } else {
            for (db.output) |output| {
                try DbVariationWriter.writeOutput(io, allocator, db_reader, script_file, output);
            }
        }
    }

    fn writeOutput(io: std.Io, allocator: Allocator, db_reader: dfile.DbReader, script_file: ReadFile, output: orch.Output) !void {
        const output_path = DbVariationWriter.outputFormatPathJoin(allocator, output.basePath, output.format);

        const output_buffer: [OrchFile.OutputFileCapacity]u8 = undefined;
        const output_file = try std.Io.Dir.cwd().createFile(io, output_path, .{});
        const output_writer = output_file.writer(io, &output_buffer);

        try DbVariationWriter.processContent(allocator, db_reader, script_file.content, output.skip, output.take, output.filterSingle, output_writer);
    }

    fn processContent(allocator: Allocator, db_reader: dfile.DbReader, script: []const u8, skip: ?usize, take: ?usize, single: ?[]const u8, writer: *std.Io.Writer) !void {
        const usage = try DotUsage.init(allocator, script);

        var dot = DotUsage.init(allocator, script) catch {
            std.debug.print("couldn't parse gof script", .{});
            try writer.write("couldn't parse gof script");
            try writer.end();
            return;
        };

        var start: usize = 0;
        var end = db_reader.header.count;

        if (skip) |s| start = s;
        if (take) |t| end = start + t;

        for (start..end) |i| {
            const meta = try db_reader.readMeta(i);
            const meta_id: [5]u8 = @bitCast(meta.id);

            if (single) {
                if (!std.mem.containsAtLeast(u8, single, 1, meta_id, single)) {
                    continue;
                }
            }

            const position = try db_reader.readPosition(i);
            usage.runner.runOnPosition(allocator, position) catch {
                _ = try writer.interface.write("Error running position ");
                _ = try writer.interface.write(meta_id);
                _ = try writer.interface.write("\n");
                return;
            };

            const output = dot.printLines(allocator) catch {
                _ = try writer.interface.write("Error writing output ");
                _ = try writer.interface.write(meta_id);
                _ = try writer.interface.write("\n");
                return;
            };

            _ = try writer.interface.write(output);
        }
    }
    fn outputFormatPathJoin(allocator: Allocator, base_path: []const u8, format: orch_lx.OutputFormat) []const u8 {
        const result = try ArrayList(u8).initCapacity(base_path.len + 10);

        errdefer result.deinit(allocator);
        result.appendSlice(base_path);
        switch (format) {
            orch_lx.OutputFormat.csv => result.appendSlice(".csv"),
            orch_lx.OutputFormat.db => result.appendSlice(".db"),
            orch_lx.OutputFormat.preview => result.appendSlice(".output"),
        }
        return result.toOwnedSlice(allocator);
    }
};

pub const AllDbReaders = struct {
    pub fn initFromPath(io: std.Io, allocator: Allocator, path: []const u8) !dfile.DbReader {
        // todo move to parser
        const extension_start = find: {
            for (0..path.len) |i| {
                if (path[path.len - 1 - i] == '.') {
                    break :find path.len - 1 - i;
                }
            }
            return errors.InvalidPath;
        };

        const name = path[0..extension_start];
        const extension = path[extension_start + 1 ..];

        const db_file = try std.mem.join(allocator, ".", name, "db");
        const meta_file = try std.mem.join(allocator, ".", name, "meta");

        if (std.mem.eql("csv", extension)) {
            const csv_file = path;
            dfile.BuildDb.read_csv_to_build_db_if_doesnt_exists(io, csv_file, db_file, meta_file);
        }
        if (std.mem.eql("db", extension)) {}
        return dfile.DbReader.open(io, db_file, meta_file);
    }
};

test "basic usage" {}
