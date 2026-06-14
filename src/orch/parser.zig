const std = @import("std");
const testing = std.testing;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const lx = @import("lexer.zig");

const errors = error{UnknownToken};

pub const Orch = struct {
    dbs: []Db,

    pub fn deinit(self: *Orch, allocator: Allocator) void {
        for (self.dbs) |*db| db.deinit(allocator);
        allocator.free(self.dbs);
    }
};

pub const Db = struct {
    db_path: []const u8,
    output: []Output,
    variation: []Variation,

    pub fn deinit(self: *Db, allocator: Allocator) void {
        for (self.variation) |*v| v.deinit(allocator);
        for (self.output) |*o| o.deinit(allocator);
        allocator.free(self.variation);
        allocator.free(self.output);
        allocator.free(self.db_path);
    }
};

pub const Variation = struct {
    name: []const u8,
    script_path: []const u8,
    output: ?[]Output,
    unify: ?[]Unify,

    pub fn deinit(self: *Variation, allocator: Allocator) void {
        if (self.unify) |unify| {
            allocator.free(unify);
        }
        if (self.output) |output| {
            for (output) |*o| o.deinit(allocator);
            allocator.free(output);
        }
        allocator.free(self.script_path);
    }
};

pub const Unify = struct {
    symbol: []const u8,
    to_variation: []const u8,
    to_symbol: []const u8,
};

pub const Output = struct {
    format: lx.OutputFormat,
    basePath: ?[]const u8,
    filter: ?lx.FilterKind,
    take: ?usize,
    skip: ?usize,
    runOnly: ?bool,
    filterSingle: ?[]const u8,

    pub fn deinit(self: *Output, allocator: Allocator) void {
        if (self.basePath) |path| allocator.free(path);
        //if (self.filterSingle) |path| allocator.free(path);
    }
};

pub const Parser = struct {
    inext: usize = 0,
    tokens: []lx.Token,
    dbs: ArrayList(DbInRef),
    outputs: ArrayList(Output),
    unifies: ArrayList(Unify),
    variations: ArrayList(VariationInRef),

    const DbInRef = struct {
        db_path: []const u8,
        output: Slice,
        variation: Slice,
    };

    const Ref = usize;
    const Slice = struct { off: usize, len: usize };

    const VariationInRef = struct {
        name: []const u8,
        script_path: []const u8,
        output: ?Slice,
        unify: ?Slice,
    };

    const Self = @This();

    pub fn deinit(self: *Self, allocator: Allocator) void {
        allocator.free(self.tokens);
        self.dbs.deinit(allocator);
        self.outputs.deinit(allocator);
        self.unifies.deinit(allocator);
        self.variations.deinit(allocator);
    }

    pub fn init(allocator: Allocator, script: []const u8) !Self {
        var lexer = lx.Lexer.init(script);
        const tokens = try lexer.toOwnedTokens(allocator);

        return .{
            .tokens = tokens,
            .dbs = .empty,
            .outputs = .empty,
            .unifies = .empty,
            .variations = .empty,
        };
    }

    pub fn parse(self: *Self, allocator: Allocator) !void {
        while (try self.parseDb(allocator)) |db| {
            try self.dbs.append(allocator, db);
        }
    }

    fn parseDb(self: *Self, allocator: Allocator) !?DbInRef {
        if (self.eatCommand(lx.Command.input) == null) {
            return null;
        }

        const db_path = try self.parsePath(allocator);

        if (try self.parseOutput(allocator)) |output_slice| {
            const variation_slice = try self.parseVariation(allocator);

            if (variation_slice == null) {
                return errors.UnknownToken;
            }

            return .{
                .db_path = db_path,
                .output = output_slice,
                .variation = variation_slice.?,
            };
        }
        return null;
    }

    fn parseOutput(self: *Self, allocator: Allocator) !?Slice {
        if (self.eatCommand(lx.Command.output) == null) {
            return null;
        }

        var result = Slice{ .off = self.outputs.items.len, .len = 0 };
        var something_else = false;
        while (!something_else) {
            if (try self.eatTag(lx.TokenTag.OutputFormat)) |format| {
                var basePath: ?[]const u8 = null;
                var filter: ?lx.FilterKind = null;
                var take: ?usize = null;
                var skip: ?usize = null;
                var runOnly: ?bool = null;
                var filterSingle: ?[]const u8 = null;
                while (try self.eatTag(lx.TokenTag.Dash) != null) {
                    if (basePath == null) {
                        basePath = try self.eatOutputConfigPath(allocator, lx.OutputConfig.basePath);
                    }
                    if (filter == null) {
                        filter = try self.eatOutputConfigFilter(lx.OutputConfig.filter);
                    }
                    if (take == null) {
                        take = try self.eatOutputConfigNumber(lx.OutputConfig.take);
                    }
                    if (skip == null) {
                        skip = try self.eatOutputConfigNumber(lx.OutputConfig.skip);
                    }
                    if (runOnly == null) {
                        runOnly = try self.eatOutputConfigParam(lx.OutputConfig.runOnly);
                    }
                    if (filterSingle == null) {
                        filterSingle = try self.eatOutputConfigText(lx.OutputConfig.filterSingle);
                    }
                }

                const output = Output{
                    .format = format.value.output_format,
                    .basePath = basePath,
                    .filter = filter,
                    .take = take,
                    .skip = skip,
                    .runOnly = runOnly,
                    .filterSingle = filterSingle,
                };

                try self.outputs.append(allocator, output);
                result.len += 1;
            } else {
                something_else = true;
            }
        }
        return result;
    }

    fn log_next_token(self: Self) void {
        std.debug.print("\n{t} Line: {d}:{d}", .{ self.tokens[self.inext].tag, self.tokens[self.inext].line, self.tokens[self.inext].column });
    }

    fn eatOutputConfigPath(self: *Self, allocator: Allocator, config: lx.OutputConfig) !?[]const u8 {
        if (try self.peekTag(lx.TokenTag.OutputConfig)) |tag| {
            if (tag.value.output_config == config) {
                _ = try self.eatTag(lx.TokenTag.OutputConfig);
                return try self.parsePath(allocator);
            }
        }
        return null;
    }
    fn eatOutputConfigFilter(self: *Self, config: lx.OutputConfig) !?lx.FilterKind {
        if (try self.peekTag(lx.TokenTag.OutputConfig)) |tag| {
            if (tag.value.output_config == config) {
                _ = try self.eatTag(lx.TokenTag.OutputConfig);
                if (try self.eatTag(lx.TokenTag.FilterKind)) |kind| {
                    return kind.value.filter_kind;
                }
            }
        }
        return null;
    }
    fn eatOutputConfigNumber(self: *Self, config: lx.OutputConfig) !?usize {
        if (try self.peekTag(lx.TokenTag.OutputConfig)) |tag| {
            if (tag.value.output_config == config) {
                _ = try self.eatTag(lx.TokenTag.OutputConfig);
                if (try self.eatTag(lx.TokenTag.Number)) |number| {
                    return number.value.number;
                }
            }
        }
        return null;
    }
    fn eatOutputConfigParam(self: *Self, config: lx.OutputConfig) !?bool {
        if (try self.peekTag(lx.TokenTag.OutputConfig)) |tag| {
            if (tag.value.output_config == config) {
                _ = try self.eatTag(lx.TokenTag.OutputConfig);
                return true;
            }
        }
        return null;
    }
    fn eatOutputConfigText(self: *Self, config: lx.OutputConfig) !?[]const u8 {
        if (try self.peekTag(lx.TokenTag.OutputConfig)) |tag| {
            if (tag.value.output_config == config) {
                _ = try self.eatTag(lx.TokenTag.OutputConfig);
                return self.eatWord();
            }
        }
        return null;
    }

    fn parseVariation(self: *Self, allocator: Allocator) !?Slice {
        if (self.eatCommand(lx.Command.variation) == null) {
            return null;
        }

        var result = Slice{ .off = self.variations.items.len, .len = 0 };
        while (true) {
            if (self.eatWord()) |name| {
                _ = try self.eatTag(lx.TokenTag.Colon);

                const script_path = try self.parsePath(allocator);
                errdefer allocator.free(script_path);

                const output = try self.parseOutput(allocator);
                const unify = try self.parseUnify(allocator);

                const variation = VariationInRef{
                    .name = name,
                    .script_path = script_path,
                    .output = output,
                    .unify = unify,
                };

                try self.variations.append(allocator, variation);
                result.len += 1;
            } else {
                break;
            }
        }
        return result;
    }

    fn parseUnify(self: *Self, allocator: Allocator) !?Slice {
        if (self.eatCommand(lx.Command.unify) != null) {
            var result = Slice{ .off = self.unifies.items.len, .len = 0 };

            while (try self.eatTag(lx.TokenTag.Dash) != null) {
                var symbol: []const u8 = undefined;
                var to_variation: []const u8 = undefined;
                var to_symbol: []const u8 = undefined;

                if (self.eatWord()) |word| {
                    symbol = word;
                } else {
                    return errors.UnknownToken;
                }

                _ = try self.eatTag(lx.TokenTag.Colon);

                if (self.eatWord()) |word| {
                    to_variation = word;
                } else {
                    return errors.UnknownToken;
                }

                _ = try self.eatTag(lx.TokenTag.Dot);

                if (self.eatWord()) |word| {
                    to_symbol = word;
                } else {
                    return errors.UnknownToken;
                }

                try self.unifies.append(allocator, Unify{
                    .symbol = symbol,
                    .to_variation = to_variation,
                    .to_symbol = to_symbol,
                });
                result.len += 1;
            }

            return result;
        }
        return null;
    }

    fn parsePath(self: *Self, allocator: Allocator) ![]const u8 {
        var result: ArrayList(u8) = .empty;
        defer result.deinit(allocator);

        var can_see_word = true;
        while (can_see_word) {
            if (self.eatWord()) |word| {
                try result.appendSlice(allocator, word);
                can_see_word = false;
            } else {
                break;
            }

            if (try self.eatTag(lx.TokenTag.Dot) != null) {
                try result.append(allocator, '.');
                can_see_word = true;
            }

            if (try self.eatTag(lx.TokenTag.PathJoin) != null) {
                try result.append(allocator, '/');
                can_see_word = true;
            }
        }

        return try result.toOwnedSlice(allocator);
    }

    fn peekTag(self: *Self, tag: lx.TokenTag) !?lx.Token {
        const next = self.tokens[self.inext];
        if (next.tag != tag) {
            return null;
        }

        return self.tokens[self.inext];
    }

    fn eatTag(self: *Self, tag: lx.TokenTag) !?lx.Token {
        const next = self.tokens[self.inext];
        if (next.tag != tag) {
            return null;
        }

        self.inext += 1;
        return self.tokens[self.inext - 1];
    }

    fn eatCommand(self: *Self, command: lx.Command) ?void {
        const next = self.tokens[self.inext];
        if (next.tag != lx.TokenTag.Command or next.value.command != command) {
            return null;
        }

        self.inext += 1;
    }

    fn eatWord(self: *Self) ?[]const u8 {
        const next = self.tokens[self.inext];
        if (next.tag != lx.TokenTag.Word) {
            return null;
        }

        self.inext += 1;

        return self.tokens[self.inext - 1].value.text;
    }

    pub fn toOwnedParse(self: *Self, allocator: Allocator) !Orch {
        try self.parse(allocator);

        var orchs: ArrayList(Db) = .empty;
        errdefer orchs.deinit(allocator);

        for (self.dbs.items) |dbs| {
            var variations: ArrayList(Variation) = .empty;
            errdefer variations.deinit(allocator);

            for (dbs.variation.off..dbs.variation.off + dbs.variation.len) |i| {
                const inref = self.variations.items[i];

                var voutputs: ArrayList(Output) = .empty;
                defer voutputs.deinit(allocator);

                if (inref.output) |slice| {
                    for (slice.off..slice.off + slice.len) |j| {
                        try voutputs.append(allocator, self.outputs.items[j]);
                    }
                }

                var vunifies: ArrayList(Unify) = .empty;
                defer vunifies.deinit(allocator);

                if (inref.unify) |slice| {
                    for (slice.off..slice.off + slice.len) |j| {
                        try vunifies.append(allocator, self.unifies.items[j]);
                    }
                }

                const variation = Variation{
                    .name = inref.name,
                    .script_path = inref.script_path,
                    .output = try voutputs.toOwnedSlice(allocator),
                    .unify = try vunifies.toOwnedSlice(allocator),
                };

                try variations.append(allocator, variation);
            }

            var outputs: ArrayList(Output) = .empty;
            defer outputs.deinit(allocator);

            try outputs.appendSlice(allocator, self.outputs.items[dbs.output.off..(dbs.output.off + dbs.output.len)]);

            const db = Db{
                .db_path = dbs.db_path,
                .output = try outputs.toOwnedSlice(allocator),
                .variation = try variations.toOwnedSlice(allocator),
            };
            try orchs.append(allocator, db);
        }

        return .{ .dbs = try orchs.toOwnedSlice(allocator) };
    }
};

test "basic parser usage" {
    const ally = testing.allocator;

    var parser = try Parser.init(ally,
        \\input: data/athousand_sorted.csv
        \\   output:
        \\      preview:
        \\         - basePath: scripts/output
        \\         - filter: fullMatch
        \\         - filterSingle: _id_0f1ave
        \\         - skip: 10
        \\         - take: 15
        \\         - runOnly:
        \\      db:
        \\         - basePath: scripts/output
        \\         - filter: fullMatch
        \\         - take: 15
        \\         - runOnly:
        \\   variation: 
        \\     mainline: scripts/variation1.gof
        \\         output:
        \\           preview:
        \\            - filter: fullMatch
        \\            - take: 15
        \\            - runOnly:
        \\     variation1: scripts/variation2.gof
        \\         unify:
        \\           - rook: mainline.rook
        \\           - king: mainline.king
        \\     variation2: scripts/variation3.gof
        \\         unify:
        \\           - rook: mainline.rook
        \\           - king: mainline.king
        \\           - bishop: variation1.bishop
        \\     variation3: scripts/variation4.gof
        \\
    );

    defer parser.deinit(ally);

    var orch_file = try parser.toOwnedParse(ally);
    defer orch_file.deinit(ally);

    try testing.expectEqual(1, orch_file.dbs.len);
    try testing.expectEqualStrings("data/athousand_sorted.csv", orch_file.dbs[0].db_path);

    try testing.expectEqual(2, orch_file.dbs[0].output.len);

    try testing.expectEqual(lx.OutputFormat.preview, orch_file.dbs[0].output[0].format);
    try testing.expectEqualStrings("scripts/output", orch_file.dbs[0].output[0].basePath.?);

    try testing.expectEqual(4, orch_file.dbs[0].variation.len);
    try testing.expectEqualStrings("mainline", orch_file.dbs[0].variation[0].name);
    try testing.expectEqualStrings("scripts/variation1.gof", orch_file.dbs[0].variation[0].script_path);
    try testing.expectEqual(lx.OutputFormat.preview, orch_file.dbs[0].variation[0].output.?[0].format);
}

pub const Defaults = struct {
    pub const output: Output = .{
        .format = lx.OutputFormat.preview,
        .basePath = null,
        .filter = null,
        .take = null,
        .runOnly = null,
        .filterSingle = null,
    };
};
