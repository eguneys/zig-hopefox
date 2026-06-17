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
const chess = @import("dot/chess/types.zig");
const san = @import("dot/chess/san.zig");
const log = @import("dot/logs.zig");

const errors = error{InvalidPath};

pub const OrchFile = struct {
    pub const OrchFileCapacity: usize = 200048;
    pub const ScriptFileCapacity: usize = 400096;
    pub const OutputFileCapacity: usize = 9000096;

    mainline_script_path: []const u8,
    orch_file: ReadFile,
    orch: Orch,
    io: std.Io,

    pub fn deinit(self: *Self, allocator: Allocator) void {
        self.orch.deinit(allocator);
        self.orch_file.deinit(allocator);
    }

    pub fn init(io: std.Io, allocator: Allocator, orch_path: []const u8) !Self {
        const orch_file = try files.ReadFile.readCapacity(io, allocator, orch_path, OrchFile.OrchFileCapacity);

        var orch_parser = try orch.Parser.init(allocator, orch_file.content);
        defer orch_parser.deinit(allocator);

        try orch_parser.parse(allocator);

        const script_path = orch_parser.variations.items[0].script_path;

        return .{ .io = io, .orch_file = orch_file, .orch = try orch_parser.toOwnedParse(allocator), .mainline_script_path = script_path };
    }

    const Self = @This();

    pub fn step(self: *Self, allocator: Allocator) !void {
        for (self.orch.dbs) |db| {
            for (db.variation) |variation| {
                try DbVariationWriter.write(self.io, allocator, db, variation);
            }
        }
    }
};

pub const DbVariationWriter = struct {
    fn write(io: std.Io, allocator: Allocator, db: orch.Db, variation: orch.Variation) !void {
        var script_file = try ReadFile.readCapacity(io, allocator, variation.script_path, OrchFile.ScriptFileCapacity);
        defer script_file.deinit(allocator);

        var db_reader = try AllDbReaders.initFromPath(io, allocator, db.db_path);

        if (variation.output) |outputs| {
            for (outputs) |output| {
                try DbVariationWriter.writeOutput(io, allocator, &db_reader, script_file, output, variation.name);
            }
        }
        for (db.output) |output| {
            try DbVariationWriter.writeOutput(io, allocator, &db_reader, script_file, output, variation.name);
        }
    }

    fn writeOutput(io: std.Io, allocator: Allocator, db_reader: *dfile.DbReader, script_file: ReadFile, output: orch.Output, variation_name: []const u8) !void {
        const output_path = try DbVariationWriter.outputFormatPathJoin(allocator, output.basePath orelse "", output.format, variation_name);
        defer allocator.free(output_path);

        var output_buffer: [OrchFile.OutputFileCapacity]u8 = undefined;
        const output_file = try std.Io.Dir.cwd().createFile(io, output_path, .{});
        var output_writer = output_file.writer(io, &output_buffer);

        try DbVariationWriter
            .processContent(io, allocator, db_reader, script_file.content, output, &output_writer);

        std.debug.print("{s} written.\n", .{output_path});
    }

    fn processContent(io: std.Io, allocator: Allocator, db_reader: *dfile.DbReader, script: []const u8, output: orch.Output, writer: *std.Io.File.Writer) !void {
        var dot = DotUsage.init(allocator, script) catch {
            std.debug.print("couldn't parse gof script", .{});
            _ = try writer.interface.write("couldn't parse gof script");
            try writer.end();
            return;
        };
        defer dot.deinit(allocator);

        var start: usize = 0;
        var end = db_reader.header.count;

        if (output.skip) |s| start = s;
        if (output.take) |t| end = start + t;

        var iVisual: usize = 0;

        var vStart: usize = 0;
        var vEnd: usize = db_reader.header.count;

        if (output.visualSkip) |s| vStart = s;
        if (output.visualTake) |t| vEnd = vStart + t;

        var append_newline = false;

        const total = db_reader.header.count;

        const ftotal: f64 = @floatFromInt(total);

        const totalStep: f64 = @mod(ftotal, 100);

        var header = try CoverageHeader.init(allocator, std.Io.Timestamp.now(io, .awake), ftotal);
        defer header.deinit(allocator);

        for (start..end) |i| {
            const fi: f64 = @floatFromInt(i);
            if (@mod(fi, totalStep) == 0) {
                header.setNbPuzzles(fi + 1);
                std.debug.print("\rProgress: %{d:.0}", .{fi / ftotal * 100});
                try header.write(io, writer, false);
            }
            var meta = try db_reader.readMeta(i);
            const meta_id: [5]u8 = @bitCast(meta.id);

            if (output.filterSingle) |single_id| {
                if (!std.mem.containsAtLeast(u8, single_id, 1, &meta_id)) {
                    continue;
                }
            }

            const position = try db_reader.readPosition(i);
            dot.runner.runOnPosition(allocator, position) catch {
                _ = try writer.interface.write("Error running position ");
                _ = try writer.interface.write(&meta_id);
                _ = try writer.interface.write("\n");
                return;
            };

            if (true) {
                if (output.filter) |filter| {
                    if (filter == orch_lx.FilterKind.fullMatch) {
                        if (dot.runner.slices.items[dot.runner.slices.items.len - 1].len == 0) {
                            continue;
                        }
                    } else if (filter == orch_lx.FilterKind.negativeMatch) {
                        if (dot.runner.slices.items[dot.runner.slices.items.len - 1].len > 0) {
                            continue;
                        }
                    }
                }

                const played = try dot.getLastLine(allocator);
                const solution = meta.moves()[0..meta.size];

                const solution_match_type = PuzzleSolutionMatchType.fromSolution(solution, played);

                header.incPuzzleMatch(solution_match_type);

                if (output.filter == orch_lx.FilterKind.firstMoveMatch) {
                    if (solution_match_type != PuzzleSolutionMatchType.firstMoveMatch) {
                        continue;
                    }
                }
                if (output.filter == orch_lx.FilterKind.trueMatch) {
                    if (solution_match_type != PuzzleSolutionMatchType.trueMatch) {
                        continue;
                    }
                }

                if (iVisual < vStart or iVisual >= vEnd) {
                    continue;
                }

                iVisual += 1;

                if (append_newline) _ = try writer.interface.write("\n");
                append_newline = true;
                _ = try writer.interface.write("https://lichess.org/training/");
                _ = try writer.interface.write(&meta_id);
                _ = try writer.interface.write("\n");

                var builder = try san.PrintBuilder.init(allocator);
                defer builder.deinit(allocator);
                builder.resetPosition(position);

                for (meta.moves()[0..meta.size]) |move| {
                    try builder.appendMove(allocator, move);
                }

                const sanMoves = builder.string.items;

                _ = try writer.interface.write("[");
                _ = try writer.interface.write(sanMoves);
                _ = try writer.interface.write("] ");
                _ = try writer.interface.write(solution_match_type.string());
                _ = try writer.interface.write("\n");

                const out_string = dot.printLines(allocator) catch {
                    _ = try writer.interface.write("Error writing output ");
                    _ = try writer.interface.write(&meta_id);
                    _ = try writer.interface.write("\n");
                    return;
                };

                _ = try writer.interface.write(out_string);
            }
        }

        try header.write(io, writer, true);

        std.debug.print("\r\x1b[KDone!\n", .{});

        try writer.end();
    }
    fn outputFormatPathJoin(allocator: Allocator, base_path: []const u8, format: orch_lx.OutputFormat, variation_name: []const u8) ![]const u8 {
        var result = try ArrayList(u8).initCapacity(allocator, base_path.len + variation_name.len + 30);
        errdefer result.deinit(allocator);

        try result.appendSlice(allocator, base_path);
        try result.appendSlice(allocator, variation_name);
        switch (format) {
            orch_lx.OutputFormat.csv => try result.appendSlice(allocator, ".csv"),
            orch_lx.OutputFormat.db => try result.appendSlice(allocator, ".db"),
            orch_lx.OutputFormat.preview => try result.appendSlice(allocator, ".output"),
        }
        return try result.toOwnedSlice(allocator);
    }
};

pub const CoverageHeader = struct {
    start: std.Io.Timestamp,
    totalPuzzles: f64,
    nbPuzzles: f64,
    buffer: []u8,

    nbFirstMatch: f64 = 0,
    nbFullMatch: f64 = 0,
    nbNegativeMatch: f64 = 0,
    nbFalseMatch: f64 = 0,

    const BufferSize = 200;

    const Self = @This();

    pub fn deinit(self: *Self, allocator: Allocator) void {
        allocator.free(self.buffer);
    }

    pub fn init(allocator: Allocator, start: std.Io.Timestamp, totalPuzzles: f64) !Self {
        const empty_header = [_]u8{' '} ** CoverageHeader.BufferSize;
        return .{ .start = start, .nbPuzzles = 0, .totalPuzzles = totalPuzzles, .buffer = try allocator.dupe(u8, &empty_header) };
    }

    pub fn setNbPuzzles(self: *Self, i: f64) void {
        self.nbPuzzles = i;
    }

    pub fn incPuzzleMatch(self: *Self, match_type: PuzzleSolutionMatchType) void {
        switch (match_type) {
            PuzzleSolutionMatchType.firstMoveMatch => self.nbFirstMatch += 1,
            PuzzleSolutionMatchType.trueMatch => self.nbFullMatch += 1,
            PuzzleSolutionMatchType.negative => self.nbNegativeMatch += 1,
            PuzzleSolutionMatchType.falseMatch => self.nbFalseMatch += 1,
        }
    }

    pub fn write(self: *Self, io: std.Io, writer: *std.Io.File.Writer, isEnd: bool) !void {
        for (0..self.buffer.len) |i| {
            self.buffer[i] = ' ';
        }

        const pos = writer.logicalPos();
        try writer.seekTo(0);
        const totalMs: f64 = @floatFromInt(self.start.untilNow(io, .awake).toMilliseconds());
        const progress = self.nbPuzzles / self.totalPuzzles * 100;
        var left: usize = 0;
        if (isEnd) {
            left += (try std.fmt.bufPrint(self.buffer[left..], "{d:.2} ms per puzzle, took {d:.0}ms\n", .{ totalMs / self.totalPuzzles, totalMs })).len;
        } else {
            left += (try std.fmt.bufPrint(self.buffer[left..], "Progress: {d:.2} {d:.2} ms per puzzle\n", .{ progress, totalMs / self.totalPuzzles })).len;
        }

        const Coverage = (1 - self.nbNegativeMatch / self.totalPuzzles) * 100;
        const Accuracy = (self.nbFullMatch + self.nbFirstMatch) / self.totalPuzzles * 100;
        left += (try std.fmt.bufPrint(self.buffer[left..], "FirstM:{d} N:{d} F:{d} T:{d}\n", .{ self.nbFirstMatch, self.nbNegativeMatch, self.nbFalseMatch, self.nbFullMatch })).len;
        left += (try std.fmt.bufPrint(self.buffer[left..], "Coverage:{d:.2}% Accuracy:{d:.2}%\n", .{ Coverage, Accuracy })).len;
        left += (try std.fmt.bufPrint(self.buffer[left..], "Total:{d}", .{self.totalPuzzles})).len;
        _ = try writer.interface.write(self.buffer);
        _ = try writer.interface.write("\n");
        try writer.seekTo(@max(pos, CoverageHeader.BufferSize + 1));
        //try writer.flush();
    }
};

pub const PuzzleSolutionMatchType = enum {
    firstMoveMatch,
    trueMatch,
    negative,
    falseMatch,

    pub fn string(self: PuzzleSolutionMatchType) []const u8 {
        return switch (self) {
            PuzzleSolutionMatchType.firstMoveMatch => "firstMoveMatch",
            PuzzleSolutionMatchType.trueMatch => "trueMatch",
            PuzzleSolutionMatchType.negative => "negative",
            PuzzleSolutionMatchType.falseMatch => "falseMatch",
        };
    }

    pub fn fromSolution(solution: []const chess.Move, lines: []const chess.Move) PuzzleSolutionMatchType {
        var result = PuzzleSolutionMatchType.negative;
        for (0..solution.len) |j| {
            if (j >= lines.len) {
                return result;
            }
            if (solution[j].equals(lines[j])) {
                if (result == PuzzleSolutionMatchType.negative) {
                    result = PuzzleSolutionMatchType.firstMoveMatch;
                }
                if (j == solution.len - 1) {
                    result = PuzzleSolutionMatchType.trueMatch;
                }
            } else {
                if (result == PuzzleSolutionMatchType.negative) {
                    result = PuzzleSolutionMatchType.falseMatch;
                    break;
                }
            }
        }
        return result;
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

        const db_file = try std.mem.join(allocator, ".", &[2][]const u8{ name, "db" });
        defer allocator.free(db_file);
        const meta_file = try std.mem.join(allocator, ".", &[2][]const u8{ name, "meta" });
        defer allocator.free(meta_file);

        if (std.mem.eql(u8, "csv", extension)) {
            const csv_file = path;
            try dfile.BuildDb.read_csv_to_build_db_if_doesnt_exists(io, csv_file, db_file, meta_file);
        }
        if (std.mem.eql(u8, "db", extension)) {}
        return dfile.DbReader.open(io, db_file, meta_file);
    }
};

test "basic usage" {
    const ally = std.testing.allocator;
    var file = try OrchFile.init(std.testing.io, ally, "scripts/analysis.orch");
    defer file.deinit(ally);

    try file.step(ally);
}

test "castling regression" {
    const ally = std.testing.allocator;
    var file = try OrchFile.init(std.testing.io, ally, "scripts/one.orch");
    defer file.deinit(ally);

    try file.step(ally);
}
