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
            .errors = try std.ArrayList(ParseErrorMsg).initCapacity(allocator, 20),
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

        try self.errors.append(ParseErrorMsg{ .line = line, .column = col, .message = owned_msg });
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
    Underscore,
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
            '_' => TokenType.Underscore,
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

const Program = struct {
    blocks: []Block,
    configurations: []Configuration,
};

const Parser = struct {
    allocator: std.mem.Allocator,
    lexer: Lexer,

    fn init(allocator: std.mem.Allocator, script: []const u8) Parser {
        return Parser{
            .allocator = allocator,
            .lexer = Lexer.init(script),
        };
    }

    fn parse_program(self: *Parser) !Program {
        const configurations = try self.parse_configurations();

        var blocks: std.ArrayList(Block) = .empty;
        errdefer blocks.deinit(self.allocator);

        while (self.parse_block()) |block| {
            try blocks.append(self.allocator, block);
        }

        return Program{
            .configurations = configurations,
            .blocks = try blocks.toOwnedSlice(self.allocator),
        };
    }

    fn parse_configurations(self: *Parser) ![]Configuration {
        var configurations: std.ArrayList(Configuration) = .empty;
        errdefer configurations.deinit(self.allocator);

        while (self.parse_configuration()) |configuration| {
            try configurations.append(self.allocator, configuration);
        }

        return configurations.toOwnedSlice(self.allocator);
    }

    fn parse_configuration(self: *Parser) ?Configuration {
        _ = self;
        return null;
    }

    fn parse_block(self: *Parser) ?Block {
        _ = self;
        return null;
    }
};

pub const ParsedProgram = struct {
    arena: std.heap.ArenaAllocator,
    program: Program,

    pub fn init(allocator: std.mem.Allocator, text: []const u8) !ParsedProgram {
        var arena = std.heap.ArenaAllocator.init(allocator);
        errdefer arena.deinit();

        var parser = Parser.init(arena.allocator(), text);
        const program = try parser.parse_program();
        return ParsedProgram{ .arena = arena, .program = program };
    }

    pub fn deinit(self: *ParsedProgram) void {
        self.arena.deinit();
    }

    pub fn blocks(self: *const ParsedProgram) []Block {
        return self.program.blocks;
    }

    pub fn configurations(self: *const ParsedProgram) []Configuration {
        return self.program.configurations;
    }
};

test "parser empty" {
    const allocator = std.testing.allocator;

    const program = try ParsedProgram.init(allocator,
        \\
        \\
        \\
    );

    try std.testing.expectEqual(0, program.blocks().len);
    try std.testing.expectEqual(0, program.configurations().len);
}

test "parser definition" {
    const allocator = std.testing.allocator;

    const program = try ParsedProgram.init(allocator,
        \\
        \\ def captures(From, Captured_To)
        \\   capture(From, To, Captured)
        \\
    );

    try std.testing.expectEqual(1, program.blocks().len);
    try std.testing.expectEqual(0, program.configurations().len);
}
