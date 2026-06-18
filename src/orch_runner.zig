const std = @import("std");
const testing = std.testing;
const Allocator = std.mem.Allocator;
const AutoHashMap = std.AutoHashMap;
const op = @import("orch2/parser.zig");
const op_lx = @import("orch2/lexer.zig");

pub const OrchRunner = struct {
    orch: op.Orch,

    const Self = @This();

    pub fn deinit(self: *Self, allocator: Allocator) void {
        self.orch.deinit(allocator);
    }

    pub fn init(allocator: Allocator, text: []const u8) !OrchRunner {
        var parser = try op.Parser.init(allocator, text);
        defer parser.deinit(allocator);

        const orch = try parser.toOwnedOrch(allocator);

        return .{ .orch = orch };
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

        var script_filters = try ScriptFilters.init(allocator, script.path, src_path, script.preview);
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
    preview: ?op.Preview,

    previewTagFiles: AutoHashMap(op_lx.FilterTag, FileWriter),
    previewTagHeaders: AutoHashMap(op_lx.FilterTag, PreviewTagHeader),

    tagFiles: AutoHashMap(op_lx.FilterTag, FileWriter),

    const Self = @This();

    fn deinit(self: *Self, allocator: Allocator) void {
        const fieldIterator = self.previewTagHeaders.valueIterator();
        while (fieldIterator.next()) |entry| {
            entry.deinit(allocator);
        }
        const fieldIterator2 = self.tagFiles.valueIterator();
        while (fieldIterator2.next()) |entry| {
            entry.deinit(allocator);
        }
        const fieldIterator3 = self.previewTagFiles.valueIterator();
        while (fieldIterator3.next()) |entry| {
            entry.deinit(allocator);
        }

        self.previewTagFiles.deinit();
        self.previewTagHeaders.deinit();
        self.tagFiles.deinit();
    }

    fn init(allocator: Allocator, script_path: []const u8, src_path: []const u8, preview: ?op.Preview) !Self {
        return .{
            .script_path = script_path,
            .src_path = src_path,
            .preview = preview,
            .previewTagFiles = .init(allocator),
            .previewTagHeaders = .init(allocator),

            .tagFiles = .init(allocator),
        };
    }

    fn passFilters(self: *Self, allocator: Allocator, filters: []op.Filter) !void {
        for (filters) |filter| {
            if (filter.preview) |preview| {
                try self.initPreview(allocator, filter.tag, preview);
            }

            try self.initTag(allocator, filter.tag);
        }

        for (0..10) |i| {
            const runVisuals = try self.runOnPosition(i);

            for (filters) |filter| {
                if (filter.preview) |preview| {
                    try self.appendPreview(allocator, filter.tag, preview, runVisuals);
                }

                try self.appendTag(allocator, filter.tag, runVisuals);
            }
        }

        for (filters) |filter| {
            if (filter.preview != null) {
                try self.endPreview(allocator, filter.tag);
            }

            try self.endTag(allocator, filter.tag);
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

        const suffix = "dbsrc";

        return std.mem.join(allocator, "._", &[4][]const u8{ self.src_path, script_path, filter_path, suffix });
    }

    fn initPreview(self: *Self, allocator: Allocator, tag: op_lx.FilterTag, preview: op.Preview) !void {
        const src = try self.preview_src_for_tag(allocator, tag);
        defer allocator.free(src);

        const preview_tag_file = try FileWriter.init(allocator, src);
        errdefer preview_tag_file.deinit(allocator);

        self.previewTagFiles.put(allocator, tag, preview_tag_file);

        const previewHeader = self.previewHeaderForTag(allocator, tag, preview);
        self.previewTagHeaders.put(allocator, tag, previewHeader);

        previewHeader.write(allocator, preview_tag_file);
    }

    fn initTag(self: *Self, allocator: Allocator, tag: op_lx.FilterTag) !void {
        const src = try self.db_src_for_tag(allocator, tag);
        defer allocator.free(src);

        const tag_file = try FileWriter.init(allocator, src);
        errdefer tag_file.deinit(allocator);

        self.tagFiles.put(allocator, tag, tag_file);
    }

    fn appendPreview(self: *Self, allocator: Allocator, tag: op_lx.FilterTag, preview: op.Preview, runVisuals: RunVisuals) !void {
        runVisuals.writePreview(allocator, self.previewFile, tag, preview);

        const preview_tag_file = self.previewTagFiles.get(tag).?;

        const previewHeader = self.previewTagHeaders.get(tag).?;
        previewHeader.append(runVisuals);

        previewHeader.write(allocator, preview_tag_file);
    }

    fn appendTag(self: *Self, allocator: Allocator, tag: op_lx.FilterTag, runVisuals: RunVisuals) !void {
        const tagFile = self.tagFiles.get(tag).?;
        runVisuals.writeTag(allocator, tagFile);
    }

    fn endPreview(self: *Self, tag: op_lx.FilterTag) !void {
        const preview_tag_file = self.previewTagFiles.get(tag).?;
        preview_tag_file.end();
    }

    fn endTag(self: *Self, tag: op_lx.FilterTag) !void {
        const tagFile = self.tagFiles.get(tag);
        tagFile.end();
    }

    fn runOnPosition(self: *Self, i: usize) !RunVisuals {
        _ = self;
        _ = i;
        return .{};
    }
};

const RunVisuals = struct {};
const PreviewTagHeader = struct {};

const FileWriter = struct {};

test "basic usage" {
    const ally = testing.allocator;

    var runner = try OrchRunner.init(ally,
        \\src: database.db
        \\script.gof:
        \\  FirstMove: @preview
        \\    script2.gof:
        \\      True
        \\      Negative: @preview(take=10)
        \\        script3.gof:
        \\          False
        \\          Full
        \\  Zero
        \\  Full: @preview
    );
    defer runner.deinit(ally);

    try runner.passStep(ally);
}
