const std = @import("std");
const testing = std.testing;
const Allocator = std.mem.Allocator;
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

    const Self = @This();

    fn deinit(self: *Self, allocator: Allocator) void {
        _ = self;
        _ = allocator;
    }

    fn init(allocator: Allocator, script_path: []const u8, src_path: []const u8, preview: ?op.Preview) !Self {
        _ = allocator;
        return .{ .script_path = script_path, .src_path = src_path, .preview = preview };
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
            if (filter.preview) |preview| {
                try self.endPreview(allocator, filter.tag, preview);
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
        _ = self;
        _ = allocator;
        _ = tag;
        _ = preview;
    }

    fn initTag(self: *Self, allocator: Allocator, tag: op_lx.FilterTag) !void {
        _ = self;
        _ = allocator;
        _ = tag;
    }

    fn appendPreview(self: *Self, allocator: Allocator, tag: op_lx.FilterTag, preview: op.Preview, runVisuals: RunVisuals) !void {
        _ = self;
        _ = allocator;
        _ = tag;
        _ = preview;
        _ = runVisuals;
    }

    fn appendTag(self: *Self, allocator: Allocator, tag: op_lx.FilterTag, runVisuals: RunVisuals) !void {
        _ = self;
        _ = allocator;
        _ = tag;
        _ = runVisuals;
    }

    fn endPreview(self: *Self, allocator: Allocator, tag: op_lx.FilterTag, preview: op.Preview) !void {
        _ = self;
        _ = allocator;
        _ = tag;
        _ = preview;
    }

    fn endTag(self: *Self, allocator: Allocator, tag: op_lx.FilterTag) !void {
        _ = self;
        _ = allocator;
        _ = tag;
    }

    fn runOnPosition(self: *Self, i: usize) !RunVisuals {
        _ = self;
        _ = i;
        return .{};
    }
};

const RunVisuals = struct {};

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
