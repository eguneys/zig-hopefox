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
    output: Output,
    variation: []Variation,

    pub fn deinit(self: *Db, allocator: Allocator) void {
        allocator.free(self.db_path);
        for (self.variation) |*v| v.deinit(allocator);
        allocator.free(self.variation);
    }
};

pub const Variation = struct {
    name: []const u8,
    script_path: []const u8,
    output: ?Output,
    unify: []Unify,

    pub fn deinit(self: *Variation, allocator: Allocator) void {
        allocator.free(self.name);
        allocator.free(self.script_path);
        for (self.unify) |*u| u.deinit(allocator);
        allocator.free(self.unify);
        if (self.output) |*o| o.deinit(allocator);
    }
};

pub const Unify = struct {
    symbol: []const u8,
    to_variation: []const u8,
    to_symbol: []const u8,

    pub fn deinit(self: *Unify, allocator: Allocator) void {
        allocator.free(self.symbol);
        allocator.free(self.to_variation);
        allocator.free(self.to_symbol);
    }
};

pub const FilterKind = enum {
    fullMatch,
    single,
};

pub const Output = struct {
    format: lx.OutputFormat,
    basePath: ?[]const u8,
    filter: ?FilterKind,
    take: ?usize,
    runOnly: ?bool,
    filterSingle: ?[]const u8,

    pub fn deinit(self: *Output, allocator: Allocator) void {
        if (self.basePath) |path| allocator.free(path);
        if (self.filterSingle) |path| allocator.free(path);
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
        output: Ref,
        variation: Slice,
    };

    const Ref = usize;
    const Slice = struct { off: usize, len: usize };

    const VariationInRef = struct {
        name: []const u8,
        script_path: []const u8,
        output: ?Ref,
        unify: Slice,
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
        if (self.eatCommand(lx.Command.db) == null) {
            return null;
        }
        _ = try self.eatTag(lx.TokenTag.Colon);

        const db_path = try self.parsePath(allocator);

        const output = try self.parseOutput() orelse Defaults.output;
        const output_ref = self.outputs.items.len;
        try self.outputs.append(allocator, output);

        var variation_slice = Slice{ .off = self.variations.items.len, .len = 0 };

        while (try self.parseVariation(allocator)) |variation| {
            try self.variations.append(allocator, variation);
            variation_slice.len += 1;
        }

        return .{
            .db_path = db_path,
            .output = output_ref,
            .variation = variation_slice,
        };
    }

    fn parseOutput(self: *Self) !?Output {
        if (self.eatCommand(lx.Command.output) == null) {
            return null;
        }
        _ = try self.eatTag(lx.TokenTag.Colon);

        var something_else = false;
        while (!something_else) {
            if (try self.eatTag(lx.TokenTag.OutputFormat)) |format| {
                _ = try self.eatTag(lx.TokenTag.Colon);

                var basePath: ?[]const u8 = null;
                var filter: ?FilterKind = null;
                var take: ?usize = null;
                var runOnly: ?bool = null;
                var filterSingle: ?[]const u8 = null;
                while (try self.eatTag(lx.TokenTag.Dash) != null) {
                    basePath = try self.eatOutputConfigPath(lx.OutputConfig.basePath);
                    filter = try self.eatOutputConfigFilter(lx.OutputConfig.filter);
                    take = try self.eatOutputConfigNumber(lx.OutputConfig.take);
                    runOnly = try self.eatOutputConfigParam(lx.OutputConfig.runOnly);
                    filterSingle = try self.eatOutputConfigText(lx.OutputConfig.filterSingle);
                }

                return .{
                    .format = format.value.output_format,
                    .basePath = basePath,
                    .filter = filter,
                    .take = take,
                    .runOnly = runOnly,
                    .filterSingle = filterSingle,
                };
            } else {
                something_else = true;
            }
        }
        return errors.UnknownToken;
    }

    fn eatOutputConfigPath(self: *Self, config: lx.OutputConfig) !?[]const u8 {
        _ = self;
        _ = config;
        return null;
    }
    fn eatOutputConfigFilter(self: *Self, config: lx.OutputConfig) !?FilterKind {
        _ = self;
        _ = config;
        return null;
    }
    fn eatOutputConfigNumber(self: *Self, config: lx.OutputConfig) !?usize {
        _ = self;
        _ = config;
        return null;
    }
    fn eatOutputConfigParam(self: *Self, config: lx.OutputConfig) !?bool {
        _ = self;
        _ = config;
        return null;
    }
    fn eatOutputConfigText(self: *Self, config: lx.OutputConfig) !?[]const u8 {
        _ = self;
        _ = config;
        return null;
    }

    fn parseVariation(self: *Self, allocator: Allocator) !?VariationInRef {
        _ = self;
        _ = allocator;
        return null;
    }

    fn parsePath(self: *Self, allocator: Allocator) ![]const u8 {
        var result: ArrayList(u8) = .empty;
        defer result.deinit(allocator);

        var can_see_word = true;
        while (can_see_word) {
            const word = try self.eatWord();
            try result.appendSlice(allocator, word);
            can_see_word = false;

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

    fn eatWord(self: *Self) ![]const u8 {
        const next = self.tokens[self.inext];
        if (next.tag != lx.TokenTag.Word) {
            return errors.UnknownToken;
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

                const output =
                    if (inref.output) |ref| self.outputs.items[ref] else null;

                const variation = Variation{
                    .name = inref.name,
                    .script_path = inref.script_path,
                    .output = output,
                    .unify = self.unifies.items[inref.unify.off .. inref.unify.off + inref.unify.len],
                };

                try variations.append(allocator, variation);
            }

            const db = Db{
                .db_path = dbs.db_path,
                .output = self.outputs.items[dbs.output],
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
        \\db: data/athousand_sorted.csv
        \\   output:
        \\      preview:
        \\         - basePath: scripts/output/
        \\         - filter: fullMatch
        \\         - filterSingle: 0f1ave
        \\         - skip: 10
        \\         - take: 15
        \\         - runOnly
        \\      db:
        \\         - basePath: scripts/output/
        \\         - filter: fullMatch
        \\         - take: 15
        \\         - runOnly
        \\   variation: 
        \\     mainline: scripts/variation1.gof
        \\         output:
        \\           preview:
        \\            - filter: fullMatch
        \\            - take: 15
        \\            - runOnly
        \\     variation1: scripts/variation2.gof
        \\         unify:
        \\           rook: mainline.rook
        \\           king: mainline.king
        \\     variation2: scripts/variation3.gof
        \\         unify:
        \\           rook: mainline.rook
        \\           king: mainline.king
        \\           bishop: variation1.bishop
        \\     variation3: scripts/variation4.gof
        \\
    );

    defer parser.deinit(ally);

    var orch_file = try parser.toOwnedParse(ally);
    defer orch_file.deinit(ally);
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
