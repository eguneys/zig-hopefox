const std = @import("std");
const testing = std.testing;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

const errors = error{UnknownToken};

pub const TokenTag = enum { FilterKind, OutputFormat, Command, OutputConfig, Word, Colon, Dash, Number, PathJoin, Dot, Equals, Eof };

pub const OutputFormat = enum {
    preview,
    db,
    csv,
};

pub const FilterKind = enum {
    fullMatch,
    single,
};

pub const OutputConfig = enum {
    basePath,
    filterSingle,
    filter,
    take,
    skip,
    runOnly,
};

pub const Command = enum {
    run,
    input,
    output,
    variation,
    unify,
};

pub const Token = struct {
    tag: TokenTag,
    line: usize,
    column: usize,
    value: union {
        char: u8,
        text: []const u8,
        number: usize,
        command: Command,
        output_config: OutputConfig,
        output_format: OutputFormat,
        filter_kind: FilterKind,
    },
};

pub const Lexer = struct {
    text: []const u8,
    inext: usize = 0,
    line_no: usize = 1,
    column_no: usize = 1,

    pub fn init(text: []const u8) Lexer {
        return .{ .text = text };
    }

    fn peekNextChar(self: Lexer) ?u8 {
        if (self.inext >= self.text.len) {
            return null;
        }

        return self.text[self.inext];
    }

    fn skipWhitespace(self: *Lexer) void {
        while (self.inext < self.text.len) {
            const c = self.text[self.inext];
            if (c == '\n') {
                self.inext += 1;
                self.line_no += 1;
                self.column_no = 1;
            } else if (std.ascii.isWhitespace(c)) {
                self.inext += 1;
                self.column_no += 1;
            } else {
                break;
            }
        }
    }

    const CommandFields = std.meta.fields(Command);
    const OutputConfigFields = std.meta.fields(OutputConfig);
    const OutputFields = std.meta.fields(OutputFormat);
    const FilterKindFields = std.meta.fields(FilterKind);

    fn nextToken(self: *Lexer) !?Token {
        self.skipWhitespace();
        if (self.inext > self.text.len) {
            return null;
        }

        if (self.inext == self.text.len) {
            self.inext += 1;
            return .{
                .tag = TokenTag.Eof,
                .line = self.line_no,
                .column = self.column_no,
                .value = undefined,
            };
        }

        if (self.peekNextChar()) |char| {
            if (char == ':') {
                self.inext += 1;
                self.column_no += 1;
                return .{
                    .tag = TokenTag.Colon,
                    .line = self.line_no,
                    .column = self.column_no - 1,
                    .value = .{ .char = ':' },
                };
            }

            if (char == '=') {
                self.inext += 1;
                self.column_no += 1;
                return .{
                    .tag = TokenTag.Equals,
                    .line = self.line_no,
                    .column = self.column_no - 1,
                    .value = .{ .char = '=' },
                };
            }

            if (char == '-') {
                self.inext += 1;
                self.column_no += 1;
                return .{
                    .tag = TokenTag.Dash,
                    .line = self.line_no,
                    .column = self.column_no - 1,
                    .value = .{ .char = '-' },
                };
            }

            if (char == '.') {
                self.inext += 1;
                self.column_no += 1;
                return .{
                    .tag = TokenTag.Dot,
                    .line = self.line_no,
                    .column = self.column_no - 1,
                    .value = .{ .char = '.' },
                };
            }

            if (char == '/') {
                self.inext += 1;
                self.column_no += 1;
                return .{
                    .tag = TokenTag.PathJoin,
                    .line = self.line_no,
                    .column = self.column_no - 1,
                    .value = .{ .char = '/' },
                };
            }
        }

        const id: usize = findid: {
            var base: usize = 1;
            var iid: usize = 0;
            while (self.peekNextChar()) |char| {
                if (std.ascii.isDigit(char)) {
                    iid += (char - '0') * base;
                    base *= 10;

                    self.inext += 1;
                    self.column_no += 1;
                } else {
                    break;
                }
            }

            break :findid iid;
        };

        if (id != 0) {
            return .{
                .tag = TokenTag.Number,
                .line = self.line_no,
                .column = self.column_no - 1,
                .value = .{ .number = id },
            };
        }

        const column_no = self.column_no;

        inline for (OutputConfigFields, 0..) |tag, i| {
            if (std.mem.startsWith(u8, self.text[self.inext..], tag.name)) {
                self.inext += tag.name.len;
                self.column_no += tag.name.len;

                return .{
                    .tag = TokenTag.OutputConfig,
                    .line = self.line_no,
                    .column = column_no,
                    .value = .{ .output_config = @enumFromInt(i) },
                };
            }
        }

        inline for (CommandFields, 0..) |tag, i| {
            if (std.mem.startsWith(u8, self.text[self.inext..], tag.name)) {
                self.inext += tag.name.len;
                self.column_no += tag.name.len;

                return .{
                    .tag = TokenTag.Command,
                    .line = self.line_no,
                    .column = column_no,
                    .value = .{ .command = @enumFromInt(i) },
                };
            }
        }
        inline for (FilterKindFields, 0..) |tag, i| {
            if (std.mem.startsWith(u8, self.text[self.inext..], tag.name)) {
                self.inext += tag.name.len;
                self.column_no += tag.name.len;

                return .{
                    .tag = TokenTag.FilterKind,
                    .line = self.line_no,
                    .column = column_no,
                    .value = .{ .filter_kind = @enumFromInt(i) },
                };
            }
        }

        inline for (OutputFields, 0..) |tag, i| {
            if (std.mem.startsWith(u8, self.text[self.inext..], tag.name)) {
                self.inext += tag.name.len;
                self.column_no += tag.name.len;

                return .{
                    .tag = TokenTag.OutputFormat,
                    .line = self.line_no,
                    .column = column_no,
                    .value = .{ .output_format = @enumFromInt(i) },
                };
            }
        }

        const findword: []const u8 = findword: {
            const start = self.inext;
            while (self.peekNextChar()) |char| {
                if (!std.ascii.isWhitespace(char)) {
                    self.inext += 1;
                    self.column_no += 1;
                } else {
                    break;
                }
            }
            break :findword self.text[start..self.inext];
        };

        if (findword.len > 0) {
            return .{
                .tag = TokenTag.Word,
                .line = self.line_no,
                .column = column_no,
                .value = .{ .text = findword },
            };
        }

        return errors.UnknownToken;
    }

    pub fn toOwnedTokens(self: *Lexer, allocator: Allocator) ![]Token {
        var tokens: std.ArrayList(Token) = .empty;
        defer tokens.deinit(allocator);

        while (try self.nextToken()) |token| {
            try tokens.append(allocator, token);
        }

        return tokens.toOwnedSlice(allocator);
    }
};

test "basic usage" {
    const ally = testing.allocator;

    var lexer = Lexer.init(
        \\
        \\run: scripts/variation1.gof
        \\db: data/athousand_sorted.csv
        \\output: .output
        \\- filter: fullMatch
        \\- take: 15
        \\- runOnly
        \\variation: 
        \\== rook king
        \\: scripts/variation2.gof
        \\: scripts/variation3.gof
        \\: scripts/variation4.gof
        \\run: scripts/script1.gof
        \\db: data/athousand_sorted.csv
        \\output: scripts/output/script1.csv
        \\- filter: fullMatch
        \\run: scripts/script2.gof
        \\db: scripts/output/script1.csv
        \\output: scripts/script2.csv
        \\- filter: fullMatch
        \\- format: csv
    );

    const tokens = try lexer.toOwnedTokens(ally);
    defer ally.free(tokens);
}
