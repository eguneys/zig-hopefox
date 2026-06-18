const std = @import("std");
const testing = std.testing;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const ReadNumber = @import("tool.zig").ReadNumber;

pub const errors = error{UnknownToken};

pub const TokenTag = enum { Src, Word, Dot, PathJoin, Colon, At, OpenParen, CloseParen, Equals, Number, Filter, Param, AlphaNumericLiteral, Eof };

pub const FilterTag = enum { FirstMove, True, Negative, False, Full, Zero };

pub const ParamTag = enum { take, skip, single };

pub const Token = struct {
    tag: TokenTag,
    line: usize,
    column: usize,
    value: union {
        char: u8,
        text: []const u8,
        number: usize,
        param: ParamTag,
        filter: FilterTag,
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

    const FilterTagFields = std.meta.fields(FilterTag);
    const ParamTagFields = std.meta.fields(ParamTag);

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

            if (char == '@') {
                self.inext += 1;
                self.column_no += 1;
                return .{
                    .tag = TokenTag.At,
                    .line = self.line_no,
                    .column = self.column_no - 1,
                    .value = .{ .char = '@' },
                };
            }

            if (char == '(') {
                self.inext += 1;
                self.column_no += 1;
                return .{
                    .tag = TokenTag.OpenParen,
                    .line = self.line_no,
                    .column = self.column_no - 1,
                    .value = .{ .char = '(' },
                };
            }

            if (char == ')') {
                self.inext += 1;
                self.column_no += 1;
                return .{
                    .tag = TokenTag.CloseParen,
                    .line = self.line_no,
                    .column = self.column_no - 1,
                    .value = .{ .char = ')' },
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
            var number: ReadNumber = .{};
            while (self.peekNextChar()) |char| {
                if (std.ascii.isDigit(char)) {
                    number.appendDigit(char - '0');

                    self.inext += 1;
                    self.column_no += 1;
                } else {
                    break;
                }
            }

            break :findid number.toOwnedNumber();
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

        inline for (FilterTagFields, 0..) |tag, i| {
            if (std.mem.startsWith(u8, self.text[self.inext..], tag.name)) {
                self.inext += tag.name.len;
                self.column_no += tag.name.len;

                return .{
                    .tag = TokenTag.Filter,
                    .line = self.line_no,
                    .column = column_no,
                    .value = .{ .filter = @enumFromInt(i) },
                };
            }
        }

        inline for (ParamTagFields, 0..) |tag, i| {
            if (std.mem.startsWith(u8, self.text[self.inext..], tag.name)) {
                self.inext += tag.name.len;
                self.column_no += tag.name.len;

                return .{
                    .tag = TokenTag.Param,
                    .line = self.line_no,
                    .column = column_no,
                    .value = .{ .param = @enumFromInt(i) },
                };
            }
        }

        var isalphanumerictag = false;

        if (self.peekNextChar()) |char| {
            if (char == '_') {
                isalphanumerictag = true;
                self.inext += 1;
                self.column_no += 1;
            }
        }

        const findword: []const u8 = findword: {
            const start = self.inext;
            while (self.peekNextChar()) |char| {
                if (std.ascii.isAlphanumeric(char) or char == '_' or char == '-') {
                    self.inext += 1;
                    self.column_no += 1;
                } else {
                    break;
                }
            }
            break :findword self.text[start..self.inext];
        };

        if (findword.len > 0) {
            if (isalphanumerictag) {
                return .{
                    .tag = TokenTag.AlphaNumericLiteral,
                    .line = self.line_no,
                    .column = column_no,
                    .value = .{ .text = findword },
                };
            } else {
                return .{
                    .tag = TokenTag.Word,
                    .line = self.line_no,
                    .column = column_no,
                    .value = .{ .text = findword },
                };
            }
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
        \\src: database.db
        \\script.gof:
        \\  filterA: @preview
        \\    script2.gof:
        \\      filterA
        \\      filterB: @preview(take=10)
        \\        script3.gof:
        \\          filterA
        \\          filterB
        \\  filterB
        \\  filterC: @preview
    );

    const tokens = try lexer.toOwnedTokens(ally);
    defer ally.free(tokens);
}
