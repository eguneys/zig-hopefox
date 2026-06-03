const std = @import("std");

const Def = struct {};

pub const ParseErrorMsg = struct {
    line: usize,
    column: usize,
    message: []const u8,
};

pub const Diagnostics = struct {
    errors: std.ArrayList(ParseErrorMsg),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) !Diagnostics {
        return Diagnostics{
            .errors = try std.ArrayList(ParseErrorMsg).initCapacity(allocator, 100),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Diagnostics) void {
        for (self.errors.items) |err| {
            self.allocator.free(err.message);
        }
        self.errors.deinit(self.allocator);
    }

    pub fn addError(self: *Diagnostics, line: usize, col: usize, msg: []const u8) !void {
        const owned_msg = try self.allocator.dupe(u8, msg);

        try self.allocator.append(.{ .line = line, .column = col, .message = owned_msg });
    }

    pub fn printAll(self: Diagnostics) void {
        for (self.errors.items) |err| {
            std.debug.print("Parser Error [{d}:{d}]: {s}\n", .{ err.line, err.column, err.message });
        }
    }
};

const TokenType = enum {
    Def,
    If,
    OpenParenthesis,
    CloseParenthesis,
    Comma,
    UpperVariable,
    LowerVariable,
    OpenBrackets,
    CloseBrackets,
    Equals,
    Eaten,
    Dollar,
    Negation,
    Other,
    Eof,
    BeginIndentation,
};

const Token = struct { kind: TokenType, value: []const u8, line_no: usize, column_no: usize };

const Lexer = struct {
    i_next: usize = 0,
    text: []const u8,
    line_no: usize = 0,
    column_no: usize = 0,

    fn init(text: []const u8) Lexer {
        return Lexer{ .text = text };
    }

    fn take_until_whitespace(self: *Lexer) ?[]const u8 {
        const i_start: usize = self.i_next;
        while (self.i_next < self.text.len) {
            const char = self.text[self.i_next];
            if (!std.ascii.isWhitespace(char)) {
                self.i_next += 1;
                self.column_no += 1;
                continue;
            }
            break;
        }
        return if (i_start != self.i_next)
            self.text[i_start..self.i_next]
        else
            null;
    }

    fn skip_whitespace(self: *Lexer) ?Token {
        var indent_start = self.i_next;
        var is_indentation = self.column_no == 0;
        while (self.i_next < self.text.len) {
            const char = self.text[self.i_next];

            if (char == '\n') {
                self.i_next += 1;
                self.line_no += 1;
                self.column_no = 0;
                is_indentation = true;
                indent_start = self.i_next;
                continue;
            }
            if (std.ascii.isWhitespace(char)) {
                self.i_next += 1;
                self.column_no += 1;
                continue;
            }
            break;
        }

        return if (is_indentation and self.column_no > 0)
            Token{ .kind = TokenType.BeginIndentation, .line_no = self.line_no, .column_no = 0, .value = self.text[indent_start .. indent_start + self.column_no] }
        else
            null;
    }

    fn next_word(self: *Lexer) ?[]const u8 {
        const i_start = self.i_next;
        while (self.i_next < self.text.len) {
            const char = self.text[self.i_next];

            if (!std.ascii.isAlphanumeric(char)) {
                break;
            }

            self.i_next += 1;
            self.column_no += 1;
        }
        return if (i_start != self.i_next)
            self.text[i_start..self.i_next]
        else
            null;
    }

    fn single_token(self: *Lexer) ?Token {
        const char = self.text[self.i_next];

        const m_kind = switch (char) {
            '(' => TokenType.OpenParenthesis,
            ')' => TokenType.CloseParenthesis,
            '[' => TokenType.OpenBrackets,
            ']' => TokenType.CloseBrackets,
            '!' => TokenType.Negation,
            '$' => TokenType.Dollar,
            '=' => TokenType.Equals,
            ',' => TokenType.Comma,
            else => null,
        };

        if (m_kind) |kind| {
            self.column_no += 1;
            self.i_next += 1;
            return Token{ .kind = kind, .line_no = self.line_no, .column_no = self.column_no, .value = self.text[self.i_next - 1 .. self.i_next] };
        }
        return null;
    }

    fn next_token(self: *Lexer) Token {
        if (self.skip_whitespace()) |indentation| {
            return indentation;
        }

        if (self.i_next == self.text.len) {
            return Token{ .kind = TokenType.Eof, .line_no = self.line_no, .column_no = 0, .value = undefined };
        }

        if (self.next_word()) |word| {
            if (std.mem.eql(u8, word, "def")) {
                return Token{ .kind = TokenType.Def, .line_no = self.line_no, .column_no = self.column_no, .value = word };
            } else if (std.mem.eql(u8, word, "if")) {
                return Token{ .kind = TokenType.If, .line_no = self.line_no, .column_no = self.column_no, .value = word };
            }
            if (std.ascii.isLower(word[0])) {
                return Token{ .kind = TokenType.LowerVariable, .line_no = self.line_no, .column_no = self.column_no, .value = word };
            } else if (std.ascii.isUpper(word[0])) {
                return Token{ .kind = TokenType.UpperVariable, .line_no = self.line_no, .column_no = self.column_no, .value = word };
            }
        }

        if (self.single_token()) |token| {
            return token;
        }

        if (self.take_until_whitespace()) |stuff| {
            return Token{ .kind = TokenType.Other, .line_no = self.line_no, .column_no = self.column_no, .value = stuff };
        }
        unreachable;
    }
};

test "lexer" {
    var lexer = Lexer.init("");
    try std.testing.expectEqual(TokenType.Eof, lexer.next_token().kind);

    lexer = Lexer.init("if");
    try std.testing.expectEqual(TokenType.If, lexer.next_token().kind);

    lexer = Lexer.init("def");
    try std.testing.expectEqual(TokenType.Def, lexer.next_token().kind);

    lexer = Lexer.init("def \n \n  ");
    try std.testing.expectEqual(TokenType.Def, lexer.next_token().kind);

    lexer = Lexer.init("$");
    try std.testing.expectEqual(TokenType.Dollar, lexer.next_token().kind);

    lexer = Lexer.init("variable133$! def (Ok, Value)");
    var token = lexer.next_token();
    try std.testing.expectEqual(TokenType.LowerVariable, token.kind);
    try std.testing.expectEqualStrings("variable133", token.value);
    try std.testing.expectEqual(TokenType.Dollar, lexer.next_token().kind);
    try std.testing.expectEqual(TokenType.Negation, lexer.next_token().kind);
    try std.testing.expectEqual(TokenType.Def, lexer.next_token().kind);
    try std.testing.expectEqual(TokenType.OpenParenthesis, lexer.next_token().kind);
    try std.testing.expectEqual(TokenType.UpperVariable, lexer.next_token().kind);
    try std.testing.expectEqual(TokenType.Comma, lexer.next_token().kind);
    try std.testing.expectEqual(TokenType.UpperVariable, lexer.next_token().kind);
    try std.testing.expectEqual(TokenType.CloseParenthesis, lexer.next_token().kind);

    lexer = Lexer.init("    hello\n\n");
    token = lexer.next_token();
    try std.testing.expectEqual(TokenType.BeginIndentation, token.kind);
    try std.testing.expectEqual(4, token.value.len);

    lexer = Lexer.init("    \n\n");
    token = lexer.next_token();
    try std.testing.expectEqual(TokenType.Eof, token.kind);

    lexer = Lexer.init(" \n\n   hello");

    token = lexer.next_token();
    try std.testing.expectEqual(TokenType.BeginIndentation, token.kind);
    try std.testing.expectEqual(3, token.value.len);
    token = lexer.next_token();
    try std.testing.expectEqual(TokenType.LowerVariable, token.kind);
    try std.testing.expectEqualStrings("hello", token.value);
}

const DefinitionHeader = struct {
    name: []Token,
    parameters: []Token,
    tags: []Token,
};

const DefinitionCall = struct {
    name: []Token,
    arguments: []Token,
};

const Definition = struct {
    header: DefinitionHeader,
    calls: []const DefinitionCall,
};

const DescriptionLine = struct {
    name: []Token,
    arguments: []Token,
    tags: []Token,
    indentation: Token,
};

const Description = struct { lines: []DescriptionLine };

const Configuration = struct { name: Token, value: Token };

const Block = struct {
    configurations: []Configuration,
    descriptions: []Description,
    definitions: []Definition,
};

const Program = struct { configurations: []Configuration, blocks: []Block };

const Parser = struct {
    diags: Diagnostics,
    blocks: std.ArrayList(Block),
    configurations: std.ArrayList(Configuration),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) !Parser {
        return Parser{
            .diags = try Diagnostics.init(allocator),
            .allocator = allocator,
            .blocks = undefined,
            .configurations = undefined,
        };
    }

    fn parse_program(self: *Parser, script: []const u8) !Program {
        var lexer = Lexer.init(script);

        const configurations = try self.parse_configurations(&lexer);

        self.blocks = .empty;
        while (self.parse_block(&lexer)) |block| {
            try self.blocks.append(self.allocator, block);
        }

        return Program{
            .configurations = configurations,
            .blocks = self.blocks.items,
        };
    }

    fn parse_configurations(self: *Parser, lexer: *Lexer) ![]Configuration {
        self.configurations = .empty;

        while (self.parse_configuration(lexer)) |configuration| {
            try self.configurations.append(self.allocator, configuration);
        }

        return self.configurations.items;
    }

    fn parse_configuration(self: *Parser, lexer: *Lexer) ?Configuration {
        _ = self;
        _ = lexer;
        return null;
    }

    fn parse_block(self: *Parser, lexer: *Lexer) ?Block {
        _ = self;
        _ = lexer;
        return null;
    }

    pub fn deinit(self: *Parser) void {
        self.diags.deinit();
    }
};

pub const Usage = struct {
    pub fn usage(script: []const u8, allocator: std.mem.Allocator) !void {
        var diags = try Diagnostics.init(allocator);

        var parser = Parser.init(allocator, &diags);

        const ast = try parser.parse_program(script);

        if (diags.errors.items.len > 0) {
            std.debug.print("Parsing failed with {d} errors:\n", .{diags.errors.items.len});
            diags.printAll();
            return;
        }

        _ = ast;
    }
};

test "usage" {
    const allocator = std.testing.allocator;

    var parser = try Parser.init(allocator);
    defer parser.deinit();

    _ = try parser.parse_program(
        \\
        \\
        \\
    );

    try std.testing.expectEqual(0, parser.diags.errors.items.len);
}

fn expectError(script: []const u8, split_errors: []const u8) !void {
    const allocator = std.testing.allocator;

    var parser = try Parser.init(allocator);
    defer parser.deinit();

    _ = try parser.parse(script);

    var errors = std.mem.splitScalar(u8, split_errors, '\n');

    var i: usize = 0;
    while (errors.next()) |expected| {
        try std.testing.expect(parser.diags.errors.items.len > i);
        const actual = parser.diags.errors.items[i];
        try std.testing.expectEqualStrings(actual.message, expected);
        i += 1;
    }

    try std.testing.expectEqual(i, parser.diags.errors.items.len);
}
