const std = @import("std");
const testing = std.testing;
const Allocator = std.mem.Allocator;
const AutoHashMap = std.AutoHashMap;
const op = @import("orch2/parser.zig");
const op_lx = @import("orch2/lexer.zig");
const chess = @import("dot/chess/types.zig");

const BuildDb = @import("db_file.zig").BuildDb;
const DbReader = @import("db_file.zig").DbReader;
const PuzzleMeta = @import("db_file.zig").PuzzleMeta;
const DotUsage = @import("dot/usage2.zig").DotUsage;

const FileReader = @import("file_api2.zig").FileReader;
const FileWriter = @import("file_api2.zig").FileWriter;

const errors = error{BadDbSrcFile};

pub const OrchRunner = struct {
    io: std.Io,
    orch: op.Orch,
    dir: std.Io.Dir,

    const ScriptFileLimit = 204800;

    const DbBaseDir = ".db-cache";

    const Self = @This();

    pub fn deinit(self: *Self, allocator: Allocator) void {
        self.orch.deinit(allocator);
    }

    pub fn init(io: std.Io, dir: std.Io.Dir, allocator: Allocator, text: []const u8) !OrchRunner {
        var parser = try op.Parser.init(allocator, text);
        defer parser.deinit(allocator);

        const orch = try parser.toOwnedOrch(allocator);

        return .{ .io = io, .dir = dir, .orch = orch };
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
        var script_filters = try ScriptFilters.init(self.io, self.dir, allocator, script.path, src_path, script.preview);
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
    src_path: []const u8,
    db_dir: std.Io.Dir,

    io: std.Io,
    preview: ?op.Preview,

    previewTagFiles: AutoHashMap(op_lx.FilterTag, FileWriter),
    previewTagHeaders: AutoHashMap(op_lx.FilterTag, PreviewTagHeader),

    tagFiles: AutoHashMap(op_lx.FilterTag, FileWriter),

    iterator: PositionIterator,

    const Self = @This();

    const PreviewFileBufferSize: usize = 204800;
    const TagFileBufferSize: usize = 2048000;

    fn deinit(self: *Self, allocator: Allocator) void {
        var fieldIterator = self.previewTagHeaders.valueIterator();
        while (fieldIterator.next()) |entry| {
            entry.deinit(allocator);
        }
        var fieldIterator2 = self.tagFiles.valueIterator();
        while (fieldIterator2.next()) |entry| {
            entry.deinit(allocator);
        }
        var fieldIterator3 = self.previewTagFiles.valueIterator();
        while (fieldIterator3.next()) |entry| {
            entry.deinit(allocator);
        }

        self.previewTagFiles.deinit();
        self.previewTagHeaders.deinit();
        self.tagFiles.deinit();

        self.iterator.deinit(self.io, allocator);

        self.db_dir.close(self.io);
    }

    fn init(io: std.Io, dir: std.Io.Dir, allocator: Allocator, script_path: []const u8, src_path: []const u8, preview: ?op.Preview) !Self {
        const db_dir = std.Io.Dir.openDir(dir, io, OrchRunner.DbBaseDir, .{}) catch tryagain: {
            try std.Io.Dir.createDir(dir, io, OrchRunner.DbBaseDir, std.Io.Dir.Permissions.default_dir);

            break :tryagain try std.Io.Dir.openDir(dir, io, OrchRunner.DbBaseDir, .{});
        };

        const iterator = try PositionIterator.init(io, dir, db_dir, allocator, script_path, src_path);

        return .{
            .script_path = script_path,
            .src_path = src_path,
            .io = io,
            .db_dir = db_dir,
            .preview = preview,
            .previewTagFiles = .init(allocator),
            .previewTagHeaders = .init(allocator),

            .tagFiles = .init(allocator),
            .iterator = iterator,
        };
    }

    fn passFilters(self: *Self, allocator: Allocator, filters: []op.Filter) !void {
        for (filters) |filter| {
            if (filter.preview) |preview| {
                try self.initPreview(allocator, filter.tag, preview);
            }

            try self.initTag(allocator, filter.tag);
        }

        for (0..self.iterator.db_reader.header.count) |i| {
            const runVisuals = try self.iterator.runOnPosition(allocator, i);

            for (filters) |filter| {
                if (filter.preview) |preview| {
                    try self.appendPreview(allocator, filter.tag, preview, runVisuals);
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

    fn preview_src_for_tag(self: Self, allocator: Allocator, tag: op_lx.FilterTag) ![]const u8 {
        const script_path = self.script_path;
        const filter_path = @tagName(tag);

        const suffix = "output";

        return std.mem.join(allocator, "._", &[4][]const u8{ self.src_path, script_path, filter_path, suffix });
    }

    fn db_src_for_tag(self: Self, allocator: Allocator, tag: op_lx.FilterTag) ![]const u8 {
        const script_path = self.script_path;
        const filter_path = @tagName(tag);

        const suffix = "dbsrc.csv";

        return std.mem.join(allocator, ".", &[4][]const u8{ self.src_path, script_path, filter_path, suffix });
    }

    fn initPreview(self: *Self, allocator: Allocator, tag: op_lx.FilterTag, preview: op.Preview) !void {
        const src = try self.preview_src_for_tag(allocator, tag);
        defer allocator.free(src);

        var preview_tag_file = try FileWriter.init(self.io, self.db_dir, allocator, src, Self.PreviewFileBufferSize);
        errdefer preview_tag_file.deinit(allocator);

        try self.previewTagFiles.put(tag, preview_tag_file);

        var previewHeader = PreviewTagHeader.init(allocator, tag, preview);
        errdefer previewHeader.deinit(allocator);
        try self.previewTagHeaders.put(tag, previewHeader);

        try previewHeader.write(allocator, preview_tag_file);
    }

    fn initTag(self: *Self, allocator: Allocator, tag: op_lx.FilterTag) !void {
        const src = try self.db_src_for_tag(allocator, tag);
        defer allocator.free(src);

        var tag_file = try FileWriter.init(self.io, self.db_dir, allocator, src, Self.TagFileBufferSize);
        errdefer tag_file.deinit(allocator);

        try self.tagFiles.put(tag, tag_file);
    }

    fn appendPreview(self: *Self, allocator: Allocator, tag: op_lx.FilterTag, preview: op.Preview, runVisuals: RunVisuals) !void {
        _ = preview;
        const preview_tag_file = self.previewTagFiles.get(tag).?;

        var previewHeader = self.previewTagHeaders.getPtr(tag).?;
        try previewHeader.*.append(allocator, runVisuals);

        try previewHeader.write(allocator, preview_tag_file);
    }

    fn appendTag(self: *Self, allocator: Allocator, tag: op_lx.FilterTag, runVisuals: RunVisuals) !void {
        const tagFile = self.tagFiles.getPtr(tag).?;
        try runVisuals.writeTag(allocator, tagFile);
    }

    fn endPreview(self: *Self, tag: op_lx.FilterTag) !void {
        const preview_tag_file = self.previewTagFiles.getPtr(tag).?;
        try preview_tag_file.end();
    }

    fn endTag(self: *Self, tag: op_lx.FilterTag) !void {
        const tagFile = self.tagFiles.getPtr(tag).?;
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

    fn init(allocator: Allocator, position: chess.Position, meta: PuzzleMeta) RunVisuals {
        _ = allocator;
        return .{ .position = position, .meta = meta };
    }

    fn writeTag(self: RunVisuals, allocator: Allocator, writer: *FileWriter) !void {
        _ = self;
        _ = allocator;
        _ = writer;
    }
};
const PreviewTagHeader = struct {
    fn deinit(self: *PreviewTagHeader, allocator: Allocator) void {
        _ = self;
        _ = allocator;
    }

    fn init(
        allocator: Allocator,
        tag: op_lx.FilterTag,
        preview: op.Preview,
    ) PreviewTagHeader {
        _ = allocator;
        _ = tag;
        _ = preview;
        return .{};
    }

    fn append(self: *PreviewTagHeader, allocator: Allocator, visuals: RunVisuals) !void {
        _ = self;
        _ = allocator;
        _ = visuals;
    }

    fn write(self: PreviewTagHeader, allocator: Allocator, writer: FileWriter) !void {
        _ = self;
        _ = allocator;
        _ = writer;
    }
};

const PositionIterator = struct {
    db_reader: DbReader,
    dot_usage: DotUsage,

    fn deinit(self: *PositionIterator, io: std.Io, allocator: Allocator) void {
        self.dot_usage.deinit(allocator);
        self.db_reader.close(io);
    }

    fn init(io: std.Io, script_dir: std.Io.Dir, db_dir: std.Io.Dir, allocator: Allocator, script_path: []const u8, src_path: []const u8) !PositionIterator {
        const script = try FileReader.readFileAlloc(io, script_dir, allocator, script_path, OrchRunner.ScriptFileLimit);
        defer allocator.free(script);
        var dot_usage = try DotUsage.init(allocator, script);
        errdefer dot_usage.deinit(allocator);

        const db_reader = FindDbReader.find(io, db_dir, allocator, src_path) catch tryagain: {
            break :tryagain try FindDbReader.find(io, script_dir, allocator, src_path);
        };

        return .{ .db_reader = db_reader, .dot_usage = dot_usage };
    }

    fn runOnPosition(self: *PositionIterator, allocator: Allocator, i: usize) !RunVisuals {
        const position = try self.db_reader.readPosition(i);
        const meta = try self.db_reader.readMeta(i);

        return RunVisuals.init(allocator, position, meta);
    }
};

const FindDbReader = struct {
    fn find(io: std.Io, dir: std.Io.Dir, allocator: Allocator, src_path: []const u8) !DbReader {
        var iterator = std.mem.splitBackwardsScalar(u8, src_path, '.');

        const extension = iterator.next() orelse return errors.BadDbSrcFile;
        const rest = iterator.rest();

        var db_path: []u8 = undefined;
        var meta_path: []u8 = undefined;

        if (std.mem.eql(u8, extension, "csv")) {
            db_path = try std.mem.join(allocator, ".", &[2][]const u8{ rest, "db" });
            defer allocator.free(db_path);
            meta_path = try std.mem.join(allocator, ".", &[2][]const u8{ rest, "meta" });
            defer allocator.free(meta_path);

            try BuildDb.read_csv_to_build_db_if_doesnt_exists(io, dir, src_path, db_path, meta_path);

            const db_reader = try DbReader.open(io, dir, db_path, meta_path);

            return db_reader;
        } else {
            return errors.BadDbSrcFile;
        }
    }
};

test "basic usage" {
    const ally = testing.allocator;

    const tmp = testing.tmpDir(.{}).dir;

    try FileWriter.writeToFile(std.testing.io, tmp, ally, "script.gof",
        \\
        \\
    );

    try FileWriter.writeToFile(std.testing.io, tmp, ally, "test.pos.csv",
        \\A0QQJ,8/pp6/5k2/4b2n/1P4P1/5PK1/P7/4R3 w - - 0 43,g3h4 e5g3 h4h5 g3e1,1098,103,20,34,advantage endgame fork short,https://lichess.org/PFYBKe5a#85,
    );

    var runner = try OrchRunner.init(testing.io, tmp, ally,
        \\src: test.pos.csv
        \\script.gof:
        \\  Negative: @preview
        \\   script2.gof:
        \\     Zero
        \\  Zero
        \\  Full: @preview
    );
    defer runner.deinit(ally);

    try runner.passStep(ally);
}

pub const LiveOrchRunner = struct {
    pub const OrchFileSizeLimit: usize = 204800;

    pub fn init(io: std.Io, allocator: Allocator, orch_path: []const u8) !OrchRunner {
        const scriptsDir = try std.Io.Dir.cwd().openDir(std.io, "scripts", .{});

        const content = try FileReader.readFileAlloc(io, scriptsDir, allocator, orch_path, LiveOrchRunner.OrchFileSizeLimit);
        defer allocator.free(content);

        return try OrchRunner.init(init.io, scriptsDir, allocator, content);
    }
};
