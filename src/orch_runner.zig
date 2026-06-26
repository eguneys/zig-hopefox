const std = @import("std");
const testing = std.testing;
const Allocator = std.mem.Allocator;
const AutoHashMap = std.AutoHashMap;
const op = @import("orch2/parser.zig");
const op_lx = @import("orch2/lexer.zig");
const chess = @import("dot/chess/types.zig");
const san = @import("dot/chess/san.zig");

const BuildDb = @import("db_file.zig").BuildDb;
const DbReader = @import("db_file.zig").DbReader;
const PuzzleMeta = @import("db_file.zig").PuzzleMeta;
const DotUsage = @import("dot/usage2.zig").DotUsage;

const FileReader = @import("file_api2.zig").FileReader;
const FileWriter = @import("file_api2.zig").FileWriter;

pub const errors = error{
    BadDbSrcFile,
    ScriptsDirectoryNotFound,
    OrchFileNotFound,
};

pub const OrchRunner = struct {
    text: []const u8,
    io: std.Io,
    orch: op.Orch,
    scriptsDir: std.Io.Dir,
    dbDir: std.Io.Dir,

    const OrchFileSizeLimit: usize = 204800;
    const ScriptFileLimit = 204800;

    const DbBaseDir = ".db-cache";

    const Self = @This();

    pub fn deinit(self: *Self, io: std.Io, allocator: Allocator) void {
        self.orch.deinit(allocator);
        self.scriptsDir.close(io);
        self.dbDir.close(io);
        allocator.free(self.text);
    }

    pub fn init(io: std.Io, scriptsDir: std.Io.Dir, allocator: Allocator, orch_path: []const u8) !OrchRunner {
        const text = FileReader.readFileAlloc(io, scriptsDir, allocator, orch_path, OrchRunner.OrchFileSizeLimit) catch {
            return errors.OrchFileNotFound;
        };

        const orch_filename = try FindDbReader.extract_filename(orch_path);
        const db_path = try std.mem.join(allocator, "_", &[2][]const u8{ orch_filename, Self.DbBaseDir });
        defer allocator.free(db_path);

        try std.Io.Dir.deleteTree(scriptsDir, io, db_path);
        try std.Io.Dir.createDir(scriptsDir, io, db_path, std.Io.Dir.Permissions.default_dir);
        const db_dir = try std.Io.Dir.openDir(scriptsDir, io, db_path, .{});

        var parser = try op.Parser.init(allocator, text);
        defer parser.deinit(allocator);

        const orch = try parser.toOwnedOrch(allocator);

        return .{ .text = text, .io = io, .scriptsDir = scriptsDir, .dbDir = db_dir, .orch = orch };
    }

    pub fn passStep(self: *Self, allocator: Allocator) !void {
        try self.passScripts(allocator, self.orch.scripts, self.orch.src_path);
    }

    fn passScripts(self: *Self, allocator: Allocator, scripts: op.Slice, src_path: []const u8) !void {
        for (scripts.off..scripts.off + scripts.len) |script| {
            try self.passScript(allocator, script, src_path);
        }
    }

    fn passScript(self: *Self, allocator: Allocator, ref: op.Ref, src_path: []const u8) anyerror!void {
        const script = self.orch.scripts_flat[ref];
        var script_filters = try ScriptFilters.init(self.io, self.scriptsDir, self.dbDir, allocator, script.path, src_path, script.preview);
        defer script_filters.deinit(allocator);

        try self.passFilters(allocator, script.filters, &script_filters);
    }

    fn passFilter(self: *Self, allocator: Allocator, ref: op.Ref, script_filter: *ScriptFilters) !void {
        const filter = self.orch.filters_flat[ref];

        const db_src = try script_filter.db_src_for_tag(allocator, filter.tag);
        defer allocator.free(db_src);

        try self.passScripts(allocator, filter.scripts, db_src);
    }

    fn passFilters(self: *Self, allocator: Allocator, filters: op.Slice, script_filters: *ScriptFilters) !void {
        try script_filters.*.passFilters(allocator, self.orch.filters_flat[filters.off .. filters.off + filters.len]);

        for (filters.off..filters.off + filters.len) |filter| {
            try self.passFilter(allocator, filter, script_filters);
        }
    }
};

const ScriptFilters = struct {
    script_path: []const u8,

    io: std.Io,

    previewAppender: ?PreviewTagAppender,
    previewTagAppenders: AutoHashMap(op_lx.FilterTag, PreviewTagAppender),
    tagAppenders: AutoHashMap(op_lx.FilterTag, TagAppender),

    iterator: PositionIterator,

    const Self = @This();

    fn deinit(self: *Self, allocator: Allocator) void {
        var fieldIterator = self.previewTagAppenders.valueIterator();
        while (fieldIterator.next()) |entry| {
            entry.deinit(allocator);
        }
        var fieldIterator2 = self.tagAppenders.valueIterator();
        while (fieldIterator2.next()) |entry| {
            entry.deinit(allocator);
        }

        self.previewTagAppenders.deinit();
        self.tagAppenders.deinit();

        self.iterator.deinit(self.io, allocator);

        if (self.previewAppender) |*appender| {
            appender.deinit(allocator);
        }
    }

    fn init(io: std.Io, scriptsDir: std.Io.Dir, dbDir: std.Io.Dir, allocator: Allocator, script_path: []const u8, src_path: []const u8, preview: ?op.Preview) !Self {
        const iterator = try PositionIterator.init(io, scriptsDir, dbDir, allocator, script_path, src_path);

        const db_dir = iterator.find_db_reader.db_dir;
        const previewAppender = if (preview) |pview| findpv: {
            const src = try ScriptFilters.preview_src_for_tag(script_path, allocator, null);
            defer allocator.free(src);
            break :findpv try PreviewTagAppender.init(io, db_dir, allocator, src, null, pview, iterator.find_db_reader.db_reader.header.count);
        } else null;

        return .{
            .script_path = script_path,
            .io = io,
            .previewAppender = previewAppender,
            .previewTagAppenders = .init(allocator),
            .tagAppenders = .init(allocator),
            .iterator = iterator,
        };
    }

    fn passFilters(self: *Self, allocator: Allocator, filters: []op.Filter) !void {
        const total = self.iterator.find_db_reader.db_reader.header.count;
        for (filters) |filter| {
            if (filter.preview) |preview| {
                try self.initPreview(allocator, filter.tag, preview, total);
            }

            try self.initTag(allocator, filter.tag);
        }

        for (0..total) |i| {
            const runVisuals = try self.iterator.runOnPosition(allocator, i);

            if (self.previewAppender) |*appender|
                try appender.append(self.io, allocator, &self.iterator.dot_usage, runVisuals);

            for (filters) |filter| {
                if (filter.preview != null) {
                    try self.appendPreview(allocator, filter.tag, runVisuals);
                }

                try self.appendTag(allocator, filter.tag, runVisuals);
            }
        }

        for (filters) |filter| {
            if (filter.preview != null) {
                try self.endPreview(filter.tag);
            }

            try self.endTag(filter.tag);
        }
    }

    fn preview_src_for_tag(script_path: []const u8, allocator: Allocator, tag: ?op_lx.FilterTag) ![]const u8 {
        const script_name = try FindDbReader.extract_filename(script_path);
        const filter_path = if (tag) |t| @tagName(t) else "S";

        const suffix = "output";

        const result = try std.mem.join(allocator, "._", &[3][]const u8{ script_name, filter_path, suffix });

        return result;
    }

    fn db_src_for_tag(self: Self, allocator: Allocator, tag: op_lx.FilterTag) ![]const u8 {
        const script_path = try FindDbReader.extract_filename(self.script_path);
        const filter_path = @tagName(tag);

        const suffix = "dbsrc.csv";

        const result = try std.mem.join(allocator, ".", &[3][]const u8{ script_path, filter_path, suffix });

        return result;
    }

    fn initPreview(self: *Self, allocator: Allocator, tag: op_lx.FilterTag, preview: op.Preview, total: usize) !void {
        const src = try ScriptFilters.preview_src_for_tag(self.script_path, allocator, tag);
        defer allocator.free(src);

        const db_dir = self.iterator.find_db_reader.db_dir;
        const appender = try PreviewTagAppender.init(self.io, db_dir, allocator, src, tag, preview, total);

        try self.previewTagAppenders.put(tag, appender);
    }

    fn initTag(self: *Self, allocator: Allocator, tag: op_lx.FilterTag) !void {
        const src = try self.db_src_for_tag(allocator, tag);
        defer allocator.free(src);

        const db_dir = self.iterator.find_db_reader.db_dir;
        const tag_file = try TagAppender.init(self.io, db_dir, allocator, src, tag);

        try self.tagAppenders.put(tag, tag_file);
    }

    fn appendPreview(self: *Self, allocator: Allocator, tag: op_lx.FilterTag, runVisuals: RunVisuals) !void {
        const preview_tag_file = self.previewTagAppenders.getPtr(tag).?;

        try preview_tag_file.append(self.io, allocator, &self.iterator.dot_usage, runVisuals);
    }

    fn appendTag(self: *Self, allocator: Allocator, tag: op_lx.FilterTag, runVisuals: RunVisuals) !void {
        const tagAppender = self.tagAppenders.getPtr(tag).?;
        try tagAppender.append(allocator, runVisuals);
    }

    fn endPreview(self: *Self, tag: op_lx.FilterTag) !void {
        const preview_tag_file = self.previewTagAppenders.getPtr(tag).?;
        try preview_tag_file.end();
    }

    fn endTag(self: *Self, tag: op_lx.FilterTag) !void {
        const tagFile = self.tagAppenders.getPtr(tag).?;
        try tagFile.end();
    }

    fn runOnPosition(self: *Self, i: usize) !RunVisuals {
        _ = self;
        _ = i;
        return .{};
    }
};

const RunVisuals = struct {
    position: chess.Position,
    meta: PuzzleMeta,

    solution_match_type: PuzzleSolutionMatchType,

    const PuzzleSolutionMatchType = enum {
        firstMoveMatch,
        trueMatch,
        negative,
        falseMatch,
        fullFalseMatch,
        fullTrueMatch,

        pub fn fromSolution(solution: []const chess.Move, lines: []const chess.Move, full_len: usize) PuzzleSolutionMatchType {
            var has_false = false;
            var result = PuzzleSolutionMatchType.negative;
            for (0..solution.len) |j| {
                if (j >= lines.len) {
                    return result;
                }
                if (solution[j].equals(lines[j])) {
                    if (result == PuzzleSolutionMatchType.negative) {
                        result = PuzzleSolutionMatchType.firstMoveMatch;
                    }
                    if (!has_false) {
                        if (result == PuzzleSolutionMatchType.negative or result == PuzzleSolutionMatchType.firstMoveMatch or result == PuzzleSolutionMatchType.trueMatch) {
                            if (j == solution.len - 1) {
                                if (j == full_len - 1) {
                                    result = PuzzleSolutionMatchType.fullTrueMatch;
                                } else {
                                    result = PuzzleSolutionMatchType.trueMatch;
                                }
                            }
                        }
                    }
                } else {
                    has_false = true;
                    if (result == PuzzleSolutionMatchType.negative) {
                        result = PuzzleSolutionMatchType.falseMatch;
                    }
                    if (j == full_len) {
                        result = PuzzleSolutionMatchType.fullFalseMatch;
                    }
                }
            }
            return result;
        }

        fn pass(self: PuzzleSolutionMatchType, tag: op_lx.FilterTag) bool {
            switch (self) {
                PuzzleSolutionMatchType.firstMoveMatch => {
                    return tag == op_lx.FilterTag.FirstMove;
                },
                PuzzleSolutionMatchType.falseMatch => {
                    return tag == op_lx.FilterTag.False;
                },
                PuzzleSolutionMatchType.negative => {
                    return tag == op_lx.FilterTag.Negative or tag == op_lx.FilterTag.Zero;
                },
                PuzzleSolutionMatchType.trueMatch => {
                    return tag == op_lx.FilterTag.True;
                },
                PuzzleSolutionMatchType.fullFalseMatch => {
                    return tag == op_lx.FilterTag.FullFalse;
                },
                PuzzleSolutionMatchType.fullTrueMatch => {
                    return tag == op_lx.FilterTag.FullTrue;
                },
            }
        }
    };

    fn init(allocator: Allocator, dot_usage: *DotUsage, position: chess.Position, meta: PuzzleMeta) !RunVisuals {
        try dot_usage.runner.runOnPosition(allocator, position);

        const playedSlices = try dot_usage.getLastLines(allocator);
        defer allocator.free(playedSlices);
        const solution = meta.moves()[0..meta.size];

        var solution_match_type = PuzzleSolutionMatchType.negative;

        for (playedSlices) |playedSlice| {
            const slice_match = PuzzleSolutionMatchType.fromSolution(solution, dot_usage.move_buffer.items[playedSlice.off .. playedSlice.off + playedSlice.len], dot_usage.getInstructionCount());

            if (slice_match == PuzzleSolutionMatchType.fullTrueMatch) {
                solution_match_type = slice_match;
                break;
            }
            if (slice_match == PuzzleSolutionMatchType.trueMatch) {
                solution_match_type = slice_match;
                break;
            }
            if (slice_match == PuzzleSolutionMatchType.firstMoveMatch) {
                solution_match_type = slice_match;
                break;
            }
        }

        return .{ .position = position, .meta = meta, .solution_match_type = solution_match_type };
    }
};

const TagAppender = struct {
    tag_file: FileWriter,
    tag: op_lx.FilterTag,
    append_newline: bool = false,

    const TagFileBufferSize: usize = 2048000;

    const Self = @This();

    fn deinit(self: *Self, allocator: Allocator) void {
        self.tag_file.deinit(allocator);
    }

    fn init(io: std.Io, db_dir: std.Io.Dir, allocator: Allocator, src: []const u8, tag: op_lx.FilterTag) !Self {
        const tag_file = try FileWriter.init(io, db_dir, allocator, src, Self.TagFileBufferSize);

        return .{ .tag_file = tag_file, .tag = tag };
    }

    fn end(self: *Self) !void {
        try self.tag_file.flush();
        try self.tag_file.end();
    }

    fn append(self: *Self, allocator: Allocator, visual: RunVisuals) !void {
        if (visual.solution_match_type.pass(self.tag)) {
            try self.writeTag(allocator, visual);
        }
    }

    fn writeTag(self: *Self, allocator: Allocator, visual: RunVisuals) !void {
        const meta = visual.meta;
        const position = visual.position;

        var builder = try san.PrintBuilder.init(allocator);
        defer builder.deinit(allocator);
        builder.resetPosition(position);

        for (meta.moves()[0..meta.size]) |move| {
            try builder.appendMove(allocator, move);
        }

        const uciMoves = builder.uci_string.items;

        var before_position = position;
        before_position.unmake_move_and_flip_turn(@bitCast(meta.move), if (meta.captured > 15) null else @enumFromInt(meta.captured));
        const fen_str = try chess.Prints.fen(allocator, before_position);
        defer allocator.free(fen_str);

        const uciMove = try san.Prints.fromMoveToUci(allocator, @bitCast(meta.move));
        defer allocator.free(uciMove);

        const meta_id: [5]u8 = @bitCast(meta.id);

        var writer = &self.tag_file;

        if (self.append_newline) {
            _ = try writer.write("\n");
        } else {
            self.append_newline = true;
        }

        _ = try writer.write(&meta_id);

        _ = try writer.write(",");
        _ = try writer.write(fen_str);

        _ = try writer.write(",");
        _ = try writer.write(uciMove);
        _ = try writer.write(" ");
        _ = try writer.write(uciMoves);

        _ = try writer.write(",");
        _ = try writer.write("https://lichess.org/training/");
        _ = try writer.write(&meta_id);
    }
};

const PreviewTagAppender = struct {
    preview: op.Preview,
    tag_file: FileWriter,
    header: PreviewTagHeader,
    start: std.Io.Timestamp,

    append_newline: bool = false,

    builder: san.PrintBuilder,

    i_visual: usize,

    buffer: []u8,

    const TagFileBufferSize: usize = 2048000;

    const CoverageHeaderBufferSize = 180;

    const Self = @This();

    fn deinit(self: *Self, allocator: Allocator) void {
        self.tag_file.deinit(allocator);
        self.header.deinit(allocator);

        self.builder.deinit(allocator);
        allocator.free(self.buffer);
    }

    fn init(io: std.Io, db_dir: std.Io.Dir, allocator: Allocator, src: []const u8, tag: ?op_lx.FilterTag, preview: op.Preview, total: usize) !Self {
        var tag_file = try FileWriter.init(io, db_dir, allocator, src, Self.TagFileBufferSize);
        errdefer tag_file.deinit(allocator);

        var previewHeader = PreviewTagHeader.init(allocator, tag, preview, total);
        errdefer previewHeader.deinit(allocator);

        const start = std.Io.Timestamp.now(io, .awake);

        const builder = try san.PrintBuilder.init(allocator);

        return .{ .i_visual = 0, .buffer = try allocator.alloc(u8, CoverageHeaderBufferSize), .builder = builder, .tag_file = tag_file, .header = previewHeader, .preview = preview, .start = start };
    }

    fn previewPass(self: *Self, visuals: RunVisuals) bool {
        const result = findresult: {
            if (self.preview.single) |single| {
                if (std.mem.containsAtLeast(u8, single, 1, &visuals.meta.id_slice())) {
                    break :findresult true;
                } else {
                    break :findresult false;
                }
            }
            break :findresult true;
        };

        if (result == false) {
            return false;
        }

        self.i_visual += 1;

        if (self.preview.skip) |skip| {
            if (self.i_visual < skip) {
                return false;
            }
            if (self.preview.take) |take| {
                if (self.i_visual - skip > take) {
                    return false;
                }
            }
        } else {
            if (self.preview.take) |take| {
                if (self.i_visual > take) {
                    return false;
                }
            }
        }
        return true;
    }

    fn append(self: *Self, io: std.Io, allocator: Allocator, dot: *DotUsage, visuals: RunVisuals) !void {
        if (self.header.i == 0) try self.writeHeader(io);
        try self.header.append(allocator, visuals);

        if (self.header.tag) |tag| {
            if (visuals.solution_match_type.pass(tag)) {
                if (self.previewPass(visuals)) {
                    try self.writeVisuals(allocator, dot, visuals);
                }
            }
        } else {
            if (self.previewPass(visuals)) {
                try self.writeVisuals(allocator, dot, visuals);
            }
        }

        const step: f64 = @divTrunc(self.header.total, 200);
        if (@mod(self.header.i, step) == 0 or self.header.i == self.header.total) {
            try self.writeHeader(io);
        }
    }

    fn writeVisuals(self: *Self, allocator: Allocator, dot: *DotUsage, visuals: RunVisuals) !void {
        var writer = &self.tag_file;
        _ = try writer.write("\n");

        self.builder.resetPosition(visuals.position);

        for (visuals.meta.moves()[0..visuals.meta.size]) |move| {
            try self.builder.appendMove(allocator, move);
        }

        const sanMoves = self.builder.string.items;

        const meta_id: [5]u8 = @bitCast(visuals.meta.id);

        _ = try writer.write(try std.fmt.bufPrint(self.buffer, "{d}", .{self.header.i}));

        _ = try writer.write(" https://lichess.org/training/");
        _ = try writer.write(&meta_id);
        _ = try writer.write("\n");

        _ = try writer.write("[");
        _ = try writer.write(sanMoves);
        _ = try writer.write("] ");
        _ = try writer.write(@tagName(visuals.solution_match_type));
        _ = try writer.write("\n");

        const out_string = dot.printLines(allocator) catch {
            _ = try writer.write("Error writing output ");
            _ = try writer.write(&meta_id);
            return;
        };

        _ = try writer.write(out_string);
    }

    fn writeHeader(self: *Self, io: std.Io) !void {
        var writer = &self.tag_file;
        const header = self.header;

        for (0..self.buffer.len) |i| {
            self.buffer[i] = ' ';
        }

        const isEnd = header.i == header.total;
        var left: usize = 0;

        const tmp_pos = writer.writer.logicalPos();
        try writer.seekTo(0);
        const totalMs: f64 = @floatFromInt(self.start.untilNow(io, .awake).toMilliseconds());
        const progress = header.i / header.total * 100;
        if (isEnd) {
            left += (try std.fmt.bufPrint(self.buffer[left..], "{d:.2} ms per puzzle, took {d:.0}ms\n", .{ totalMs / header.total, totalMs })).len;
        } else {
            left += (try std.fmt.bufPrint(self.buffer[left..], "Progress: {d:.2} {d:.2} ms per puzzle\n", .{ progress, totalMs / header.total })).len;
        }

        const Coverage = (1 - header.nbNegativeMatch / header.total) * 100;
        const Accuracy = (header.nbFullMatch + header.nbFirstMatch) / (header.total - header.nbNegativeMatch) * 100;
        left += (try std.fmt.bufPrint(self.buffer[left..], "FirstM:{d} N:{d} F:{d} FF:{d} T:{d} FullT: {d}\n", .{ header.nbFirstMatch, header.nbNegativeMatch, header.nbFalseMatch, header.nbFullFalseMatch, header.nbFullMatch, header.nbFullTrueMatch })).len;
        left += (try std.fmt.bufPrint(self.buffer[left..], "Coverage:{d:.2}% Accuracy:{d:.2}%\n", .{ Coverage, Accuracy })).len;
        left += (try std.fmt.bufPrint(self.buffer[left..], "Total:{d}", .{header.total})).len;
        _ = try writer.write(self.buffer);
        try writer.flush();

        try writer.seekTo(@max(tmp_pos, PreviewTagAppender.CoverageHeaderBufferSize));
    }

    fn end(self: *Self) !void {
        try self.tag_file.flush();
        try self.tag_file.end();
    }
};

const PreviewTagHeader = struct {
    total: f64,
    i: f64,

    nbNegativeMatch: f64 = 0,
    nbFullMatch: f64 = 0,
    nbFalseMatch: f64 = 0,
    nbFirstMatch: f64 = 0,
    nbFullFalseMatch: f64 = 0,
    nbFullTrueMatch: f64 = 0,

    tag: ?op_lx.FilterTag,

    const Self = @This();

    fn deinit(self: *Self, allocator: Allocator) void {
        _ = self;
        _ = allocator;
    }

    fn init(
        allocator: Allocator,
        tag: ?op_lx.FilterTag,
        preview: op.Preview,
        total: usize,
    ) Self {
        _ = allocator;
        _ = preview;
        return .{ .total = @floatFromInt(total), .i = 0, .tag = tag };
    }

    fn append(self: *Self, allocator: Allocator, visuals: RunVisuals) !void {
        _ = allocator;
        self.i += 1;

        switch (visuals.solution_match_type) {
            RunVisuals.PuzzleSolutionMatchType.firstMoveMatch => {
                self.nbFirstMatch += 1;
            },
            RunVisuals.PuzzleSolutionMatchType.falseMatch => {
                self.nbFalseMatch += 1;
            },
            RunVisuals.PuzzleSolutionMatchType.negative => {
                self.nbNegativeMatch += 1;
            },
            RunVisuals.PuzzleSolutionMatchType.trueMatch => {
                self.nbFullMatch += 1;
            },
            RunVisuals.PuzzleSolutionMatchType.fullFalseMatch => {
                self.nbFullFalseMatch += 1;
            },
            RunVisuals.PuzzleSolutionMatchType.fullTrueMatch => {
                self.nbFullTrueMatch += 1;
            },
        }
    }
};

const PositionIterator = struct {
    find_db_reader: FindDbReader,
    dot_usage: DotUsage,

    fn deinit(self: *PositionIterator, io: std.Io, allocator: Allocator) void {
        self.dot_usage.deinit(allocator);
        self.find_db_reader.deinit(io);
    }

    fn init(io: std.Io, scriptsDir: std.Io.Dir, dbDir: std.Io.Dir, allocator: Allocator, script_path: []const u8, src_path: []const u8) !PositionIterator {
        const script = try FileReader.readFileAlloc(io, scriptsDir, allocator, script_path, OrchRunner.ScriptFileLimit);
        defer allocator.free(script);
        var dot_usage = try DotUsage.init(allocator, script);
        errdefer dot_usage.deinit(allocator);

        const find_db_reader = try FindDbReader.init(io, scriptsDir, dbDir, allocator, src_path);

        return .{ .find_db_reader = find_db_reader, .dot_usage = dot_usage };
    }

    fn runOnPosition(self: *PositionIterator, allocator: Allocator, i: usize) !RunVisuals {
        const position = try self.find_db_reader.db_reader.readPosition(i);
        const meta = try self.find_db_reader.db_reader.readMeta(i);

        return RunVisuals.init(allocator, &self.dot_usage, position, meta);
    }
};

const FindDbReader = struct {
    db_dir: std.Io.Dir,
    db_reader: DbReader,

    fn deinit(self: *FindDbReader, io: std.Io) void {
        self.db_reader.close(io);
    }

    fn init(io: std.Io, scriptsDir: std.Io.Dir, db_dir: std.Io.Dir, allocator: Allocator, src_path: []const u8) !FindDbReader {
        var iterator = std.mem.splitBackwardsScalar(u8, src_path, '.');

        const extension = iterator.next() orelse return errors.BadDbSrcFile;
        const rest = iterator.rest();
        iterator = std.mem.splitBackwardsScalar(u8, rest, '/');
        const filename = iterator.next() orelse return errors.BadDbSrcFile;

        var db_path: []u8 = undefined;
        var meta_path: []u8 = undefined;

        if (std.mem.eql(u8, extension, "csv")) {
            db_path = try std.mem.join(allocator, ".", &[2][]const u8{ filename, "db" });
            defer allocator.free(db_path);
            meta_path = try std.mem.join(allocator, ".", &[2][]const u8{ filename, "meta" });
            defer allocator.free(meta_path);

            BuildDb.read_csv_to_build_db_if_doesnt_exists(io, db_dir, db_dir, src_path, db_path, meta_path) catch |err| {
                if (err == BuildDb.errors.CsvFileNotFound) {
                    try BuildDb.read_csv_to_build_db_if_doesnt_exists(io, scriptsDir, db_dir, src_path, db_path, meta_path);
                } else {
                    return err;
                }
            };

            const db_reader = try DbReader.open(io, db_dir, db_path, meta_path);

            return .{ .db_reader = db_reader, .db_dir = db_dir };
        } else {
            return errors.BadDbSrcFile;
        }
    }

    fn extract_filename(path: []const u8) ![]const u8 {
        var iterator = std.mem.splitBackwardsScalar(u8, path, '.');

        const extension = iterator.next() orelse return errors.BadDbSrcFile;
        _ = extension;
        const rest = iterator.rest();
        iterator = std.mem.splitBackwardsScalar(u8, rest, '/');
        const filename = iterator.next() orelse return errors.BadDbSrcFile;
        return filename;
    }
};

test "basic usage" {
    const ally = testing.allocator;

    const tmp = testing.tmpDir(.{}).dir;

    try FileWriter.writeToFile(std.testing.io, tmp, ally, "script.gof",
        \\
        \\
    );
    try FileWriter.writeToFile(std.testing.io, tmp, ally, "script2.gof",
        \\
        \\
    );

    try FileWriter.writeToFile(std.testing.io, tmp, ally, "test.pos.csv",
        \\A0QQJ,8/pp6/5k2/4b2n/1P4P1/5PK1/P7/4R3 w - - 0 43,g3h4 e5g3 h4h5 g3e1,1098,103,20,34,advantage endgame fork short,https://lichess.org/PFYBKe5a#85,
    );

    try FileWriter.writeToFile(std.testing.io, tmp, ally, "analysis.orch",
        \\src: test.pos.csv
        \\script.gof:
        \\  Negative: @preview
        \\   script2.gof:
        \\     Zero
        \\  Zero
        \\  Full: @preview
    );

    var runner = try OrchRunner.init(testing.io, tmp, ally, "analysis.orch");
    defer runner.deinit(testing.io, ally);

    try runner.passStep(ally);
}

pub const LiveOrchReloader = struct {
    io: std.Io,
    runner: OrchRunner,
    dir: std.Io.Dir,
    orch_path: []const u8,

    const Self = @This();

    pub fn deinit(self: *Self, io: std.Io, allocator: Allocator) void {
        self.runner.deinit(io, allocator);
    }

    fn reloadOrchFile(self: *Self, allocator: Allocator) !void {
        self.runner = try OrchRunner.init(self.io, self.dir, allocator, self.orch_path);
    }

    pub fn reload(self: *Self, allocator: Allocator) !void {
        var new_orch = try OrchRunner.init(
            self.io,
            self.dir,
            allocator,
            self.orch_path,
        );
        errdefer new_orch.deinit(self.io, allocator);

        self.runner.deinit(allocator);
        self.runner = new_orch;
    }

    pub fn init(io: std.Io, dir: std.Io.Dir, allocator: Allocator, orch_path: []const u8) !Self {
        var self: Self = .{ .io = io, .dir = dir, .orch_path = orch_path, .runner = undefined };

        try self.reloadOrchFile(allocator);

        return self;
    }

    pub fn step(self: *Self, allocator: Allocator) !void {
        try self.reloadOrchFile(allocator);
        try self.runner.passStep(allocator);
    }
};

const FileWatcher = @import("file_watcher.zig").FileWatcher;

pub const LiveOrchRunner = struct {
    watcher: FileWatcher(LiveOrchReloader),

    dir: std.Io.Dir,

    const Self = @This();

    pub fn deinit(self: *Self, io: std.Io, allocator: Allocator) void {
        self.watcher.handler.deinit(io, allocator);
        self.dir.close(io);
    }

    pub fn init(io: std.Io, allocator: Allocator, scripts_path: []const u8, orch_path: []const u8) !Self {
        const scriptsDir = std.Io.Dir.cwd().openDir(io, scripts_path, .{}) catch {
            return errors.ScriptsDirectoryNotFound;
        };

        const step = try LiveOrchReloader.init(io, scriptsDir, allocator, orch_path);
        return .{ .dir = scriptsDir, .watcher = FileWatcher(LiveOrchReloader).init(io, scriptsDir, orch_path, step) };
    }
};
