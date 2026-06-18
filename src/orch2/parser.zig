const std = @import("std");
const testing = std.testing;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const lx = @import("lexer.zig");

pub const errors = error{
    ExpectingSrc,
    ExpectingColon,
    ExpectingScript,
    ExpectingPreviewAt,
    ExpectingPreviewWord,
    ExpectingPreviewParam,
    ExpectingOpenParen,
    ExpectingCloseParen,
    ExpectingEquals,
    ExpectingSingleId,
    ExpectingNumber,
};

pub const Ref = usize;
pub const Slice = struct { off: usize, len: usize };

pub const Orch = struct {
    src_path: []const u8,
    scripts: Slice,
    scripts_flat: []Script,
    filters_flat: []Filter,

    pub fn deinit(self: *Orch, allocator: Allocator) void {
        allocator.free(self.src_path);
        for (self.scripts_flat) |*script| script.deinit(allocator);
        allocator.free(self.scripts_flat);
        allocator.free(self.filters_flat);
    }
};

pub const Script = struct {
    path: []const u8,
    filters: Slice,
    preview: ?Preview,

    pub fn deinit(self: *Script, allocator: Allocator) void {
        allocator.free(self.path);
    }
};

pub const Filter = struct {
    preview: ?Preview,
    tag: lx.FilterTag,
    scripts: Slice,
};

pub const Preview = struct { take: ?usize, skip: ?usize, single: ?[]const u8 };

pub const Parser = struct {
    tokens: []lx.Token,
    inext: usize = 0,
    src_path: []const u8,
    scripts: Slice,
    scripts_flat: ArrayList(Script),
    filters_flat: ArrayList(Filter),

    script_indents: ArrayList(IndentRef),
    filter_indents: ArrayList(IndentRef),

    const IndentRef = struct { ref: Ref, indent: usize };

    pub fn deinit(self: *Parser, allocator: Allocator) void {
        allocator.free(self.tokens);
        self.scripts_flat.deinit(allocator);
        self.filters_flat.deinit(allocator);
        self.script_indents.deinit(allocator);
        self.filter_indents.deinit(allocator);
    }

    pub fn init(allocator: Allocator, text: []const u8) !Parser {
        var lexer = lx.Lexer.init(text);
        var result = Parser{
            .tokens = try lexer.toOwnedTokens(allocator),
            .src_path = undefined,
            .scripts = .{ .off = 0, .len = 0 },
            .scripts_flat = .empty,
            .filters_flat = .empty,
            .script_indents = .empty,
            .filter_indents = .empty,
        };

        try result.parseSource(allocator);

        return result;
    }

    pub fn toOwnedOrch(self: *Parser, allocator: Allocator) !Orch {
        return .{
            .src_path = self.src_path,
            .scripts = self.scripts,
            .scripts_flat = try self.scripts_flat.toOwnedSlice(allocator),
            .filters_flat = try self.filters_flat.toOwnedSlice(allocator),
        };
    }

    fn parseSource(self: *Parser, allocator: Allocator) !void {
        if (self.eatWord("src") == null) {
            return errors.ExpectingSrc;
        }
        if (self.eatTag(lx.TokenTag.Colon) == null) {
            return errors.ExpectingColon;
        }

        self.src_path = try self.parsePath(allocator);
        errdefer allocator.free(self.src_path);

        self.scripts = try self.parseScripts(allocator, 1);
    }

    fn parseScripts(self: *Parser, allocator: Allocator, expectIndent: usize) !Slice {
        var list: ArrayList(Script) = .empty;
        defer list.deinit(allocator);
        errdefer for (list.items) |*item| item.deinit(allocator);

        while (try self.parseScript(allocator, expectIndent)) |script| {
            const ref = self.scripts_flat.items.len + list.items.len;
            try self.script_indents.append(allocator, .{ .ref = ref, .indent = expectIndent });
            try list.append(allocator, script);
        }

        const result = Slice{ .off = self.scripts_flat.items.len, .len = list.items.len };

        try self.scripts_flat.appendSlice(allocator, list.items);

        return result;
    }

    fn parseScript(self: *Parser, allocator: Allocator, expectIndent: usize) !?Script {
        const indent = self.tokens[self.inext].column;

        if (indent != expectIndent) return null;

        var result: Script = undefined;

        result.path = try self.parsePath(allocator);
        errdefer allocator.free(result.path);

        if (self.eatTag(lx.TokenTag.Colon) == null) {
            return errors.ExpectingColon;
        }

        if (self.peekTag(lx.TokenTag.At) != null) {
            result.preview = try self.parsePreview();
        }

        result.filters = try self.parseFilters(allocator, indent + 2);

        return result;
    }

    fn parseFilter(self: *Parser, allocator: Allocator, expectIndent: usize) anyerror!?Filter {
        const indent = self.tokens[self.inext].column;

        if (indent != expectIndent) return null;

        var result: Filter = .{ .preview = null, .tag = undefined, .scripts = undefined };

        if (self.eatTag(lx.TokenTag.Filter)) |tag| {
            result.tag = tag.value.filter;
        } else {
            return null;
        }

        if (self.eatTag(lx.TokenTag.Colon) != null) {
            result.preview = try self.parsePreview();
        }

        result.scripts = try self.parseScripts(allocator, indent + 2);

        return result;
    }

    fn parseFilters(self: *Parser, allocator: Allocator, expectIndent: usize) !Slice {
        var list: ArrayList(Filter) = .empty;
        defer list.deinit(allocator);

        while (try self.parseFilter(allocator, expectIndent)) |filter| {
            const ref = self.filters_flat.items.len + list.items.len;
            try self.filter_indents.append(allocator, .{ .ref = ref, .indent = expectIndent });
            try list.append(allocator, filter);
        }

        const result = Slice{ .off = self.filters_flat.items.len, .len = list.items.len };

        try self.filters_flat.appendSlice(allocator, list.items);

        return result;
    }

    fn parsePreview(self: *Parser) !Preview {
        if (self.eatTag(lx.TokenTag.At) == null) {
            return errors.ExpectingPreviewAt;
        }

        if (self.eatWord("preview") == null) {
            return errors.ExpectingPreviewWord;
        }

        var result = Preview{ .take = null, .skip = null, .single = null };

        if (self.eatTag(lx.TokenTag.OpenParen) == null) {
            return result;
        }

        while (self.peekTag(lx.TokenTag.CloseParen) == null) {
            if (self.eatTag(lx.TokenTag.Param)) |param| {
                if (self.eatTag(lx.TokenTag.Equals) == null) {
                    return errors.ExpectingEquals;
                }
                switch (param.value.param) {
                    lx.ParamTag.single => {
                        if (self.eatTag(lx.TokenTag.AlphaNumericLiteral)) |single| {
                            result.single = single.value.text;
                        } else {
                            return errors.ExpectingSingleId;
                        }
                    },
                    lx.ParamTag.take => {
                        if (self.eatTag(lx.TokenTag.Number)) |take| {
                            result.take = take.value.number;
                        } else {
                            return errors.ExpectingNumber;
                        }
                    },
                    lx.ParamTag.skip => {
                        if (self.eatTag(lx.TokenTag.Number)) |take| {
                            result.skip = take.value.number;
                        } else {
                            return errors.ExpectingNumber;
                        }
                    },
                }
            } else {
                return errors.ExpectingPreviewParam;
            }
        }
        _ = self.eatTag(lx.TokenTag.CloseParen);

        return result;
    }

    fn parsePath(self: *Parser, allocator: Allocator) ![]const u8 {
        var result: ArrayList(u8) = .empty;
        defer result.deinit(allocator);

        var can_see_word = true;
        while (can_see_word) {
            if (self.eatTag(lx.TokenTag.Dot) != null) {
                try result.append(allocator, '.');
                can_see_word = true;
            }

            if (self.eatTag(lx.TokenTag.Dot) != null) {
                try result.append(allocator, '.');
                can_see_word = true;
            }
            if (self.eatTag(lx.TokenTag.PathJoin) != null) {
                try result.append(allocator, '/');
                can_see_word = true;
            }

            if (self.eatWord(null)) |word| {
                try result.appendSlice(allocator, word.value.text);
                can_see_word = false;
            } else {
                break;
            }
            if (self.eatTag(lx.TokenTag.Dot) != null) {
                try result.append(allocator, '.');
                can_see_word = true;
            }
            if (self.eatTag(lx.TokenTag.PathJoin) != null) {
                try result.append(allocator, '/');
                can_see_word = true;
            }
        }

        return try result.toOwnedSlice(allocator);
    }

    fn peekTag(self: *Parser, tag: lx.TokenTag) ?lx.Token {
        const token = self.tokens[self.inext];
        if (token.tag == tag) {
            return token;
        }

        return null;
    }

    fn eatTag(self: *Parser, tag: lx.TokenTag) ?lx.Token {
        const token = self.tokens[self.inext];
        if (token.tag == tag) {
            self.inext += 1;
            return token;
        }

        return null;
    }

    fn eatWord(self: *Parser, word: ?[]const u8) ?lx.Token {
        const token = self.tokens[self.inext];
        if (token.tag == lx.TokenTag.Word) {
            if (word) |w|
                if (!std.mem.eql(u8, token.value.text, w)) return null;
            self.inext += 1;
            return token;
        }

        return null;
    }
};

test "basic usage" {
    const ally = testing.allocator;

    //{ FirstMove, True, Negative, False, Full, Zero };
    var parser = try Parser.init(ally,
        \\src: ../data/database.db
        \\script.gof: @preview(take=10)
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
    defer parser.deinit(ally);

    var orch = try parser.toOwnedOrch(ally);
    defer orch.deinit(ally);

    try testing.expectEqual(3, orch.scripts_flat.len);
    try testing.expectEqual(7, orch.filters_flat.len);

    try testing.expectEqual(1, orch.scripts.len);
    try testing.expectEqual(2, orch.scripts.off);
    try testing.expectEqualStrings("script.gof", orch.scripts_flat[2].path);
    try testing.expectEqual(3, orch.scripts_flat[2].filters.len);
    try testing.expectEqual(4, orch.scripts_flat[2].filters.off);
    try testing.expectEqual(1, orch.filters_flat[4].scripts.len);
}

test "regression" {
    const ally = testing.allocator;

    //{ FirstMove, True, Negative, False, Full, Zero };
    var parser = try Parser.init(ally,
        \\src: ../data/test_b_forks_kr2.csv
        \\script.gof:
        \\  Negative: @preview
        \\    script2.gof:
        \\      Zero
        \\  Zero
        \\  Full: @preview
    );
    defer parser.deinit(ally);

    var orch = try parser.toOwnedOrch(ally);
    defer orch.deinit(ally);

    try testing.expectEqual(1, orch.scripts.len);
}
