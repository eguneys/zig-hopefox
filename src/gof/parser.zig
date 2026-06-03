const std = @import("std");

const Def = struct {};

const ParseErrorMsg = struct {
    line: usize,
    column: usize,
    message: []const u8,
};

const Diagnostics = struct {
    errors: std.ArrayList(ParseErrorMsg),
    allocator: std.mem.Allocator,

    fn init(allocator: std.mem.Allocator) !Diagnostics {
        return Diagnostics{
            .errors = try std.ArrayList(ParseErrorMsg).initCapacity(allocator, 20),
            .allocator = allocator,
        };
    }

    fn deinit(self: *Diagnostics) void {
        for (self.errors.items) |err| {
            self.allocator.free(err.message);
        }
        self.errors.deinit(self.allocator);
    }

    fn addError(self: *Diagnostics, line: usize, col: usize, msg: []const u8) !void {
        const owned_msg = try self.allocator.dupe(u8, msg);

        try self.errors.append(ParseErrorMsg{ .line = line, .column = col, .message = owned_msg });
    }

    fn printAll(self: Diagnostics) void {
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

    fn skip_whitespace(self: *Lexer) void {
        while (self.i_next < self.text.len) {
            const char = self.text[self.i_next];

            if (char == '\n') {
                self.i_next += 1;
                self.line_no += 1;
                self.column_no = 0;
                continue;
            }
            if (std.ascii.isWhitespace(char)) {
                self.i_next += 1;
                self.column_no += 1;
                continue;
            }
            break;
        }
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
        self.skip_whitespace();

        if (self.i_next == self.text.len) {
            return Token{ .kind = TokenType.Eof, .line_no = self.line_no, .column_no = 0, .value = undefined };
        }

        const column_no = self.column_no;
        if (self.next_word()) |word| {
            if (std.mem.eql(u8, word, "def")) {
                return Token{ .kind = TokenType.Def, .line_no = self.line_no, .column_no = column_no, .value = word };
            } else if (std.mem.eql(u8, word, "if")) {
                return Token{ .kind = TokenType.If, .line_no = self.line_no, .column_no = column_no, .value = word };
            }
            if (std.ascii.isLower(word[0])) {
                return Token{ .kind = TokenType.LowerVariable, .line_no = self.line_no, .column_no = column_no, .value = word };
            } else if (std.ascii.isUpper(word[0])) {
                return Token{ .kind = TokenType.UpperVariable, .line_no = self.line_no, .column_no = column_no, .value = word };
            }
        }

        if (self.single_token()) |token| {
            return token;
        }

        if (self.take_until_whitespace()) |stuff| {
            return Token{ .kind = TokenType.Other, .line_no = self.line_no, .column_no = column_no, .value = stuff };
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
    try std.testing.expectEqual(TokenType.LowerVariable, token.kind);
    try std.testing.expectEqual(4, token.column_no);

    lexer = Lexer.init("    \n\n");
    token = lexer.next_token();
    try std.testing.expectEqual(TokenType.Eof, token.kind);

    lexer = Lexer.init(" \n\n   hello");

    token = lexer.next_token();
    try std.testing.expectEqual(TokenType.LowerVariable, token.kind);
    try std.testing.expectEqual(3, token.column_no);
    token = lexer.next_token();
    try std.testing.expectEqual(TokenType.Eof, token.kind);
}

const DefinitionHeader = struct {
    name: Token,
    parameters: []Token,
    tags: []Token,
};

const DefinitionCall = struct {
    name: Token,
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

    next_token: ?Token,
    lookahead_token: ?Token,

    fn advance(self: *Parser) void {
        self.next_token = self.lookahead_token;
        self.lookahead_token = self.lexer.next_token();
    }

    fn init(allocator: std.mem.Allocator, script: []const u8) Parser {
        var lexer = Lexer.init(script);
        const next_token = lexer.next_token();
        const lookahed_token = lexer.next_token();
        return Parser{
            .allocator = allocator,
            .lexer = lexer,
            .next_token = next_token,
            .lookahead_token = lookahed_token,
        };
    }

    fn parse_program(self: *Parser) !Program {
        const configurations = try self.parse_configurations();

        var blocks: std.ArrayList(Block) = .empty;
        errdefer blocks.deinit(self.allocator);

        while (try self.parse_block()) |block| {
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

    fn eat(self: *Parser, kind: TokenType) ?Token {
        if (self.next_token) |token| {
            if (token.kind != kind) {
                return null;
            }
            self.advance();
            return token;
        }
        return null;
    }

    fn parse_configuration(self: *Parser) ?Configuration {
        _ = self;
        return null;
    }

    fn parse_definition(self: *Parser) !?Definition {
        if (try self.parse_definition_header()) |header| {
            var calls: std.ArrayList(DefinitionCall) = .empty;
            errdefer calls.deinit(self.allocator);

            while (try self.parse_definition_call()) |call| {
                try calls.append(self.allocator, call);
            }

            return .{
                .header = header,
                .calls = try calls.toOwnedSlice(self.allocator),
            };
        }
        return null;
    }

    fn parse_definition_header(self: *Parser) !?DefinitionHeader {
        var parameters: std.ArrayList(Token) = .empty;
        errdefer parameters.deinit(self.allocator);

        var tags: std.ArrayList(Token) = .empty;
        errdefer tags.deinit(self.allocator);

        var m_name: ?Token = undefined;

        const has_failed = has_failed: {
            if (self.eat(TokenType.Def) != null) {
                m_name = self.eat(TokenType.LowerVariable);
                if (m_name == null) {
                    break :has_failed true;
                }

                if (self.eat(TokenType.OpenParenthesis) == null) {
                    // diagnostics
                    // synchronize
                    break :has_failed true;
                }
                while (self.parse_definition_parameter_token()) |token2| {
                    try parameters.append(self.allocator, token2);
                    if (self.eat(TokenType.CloseParenthesis) != null)
                        break :has_failed false;
                    if (self.eat(TokenType.Comma) != null)
                        continue;
                } else break :has_failed true;
            } else break :has_failed true;
        };

        if (has_failed) {
            parameters.clearAndFree(self.allocator);
            tags.clearAndFree(self.allocator);
            return null;
        }

        return if (m_name) |name|
            .{
                .name = name,
                .parameters = try parameters.toOwnedSlice(self.allocator),
                .tags = try tags.toOwnedSlice(self.allocator),
            }
        else
            null;
    }

    fn log_token(self: *Parser, token: Token) void {
        _ = self;
        std.debug.print("Log Token: .{s} {s}\n", .{ std.enums.tagName(TokenType, token.kind).?, token.value });
    }

    fn log_next_token(self: *Parser) void {
        if (self.next_token) |token| {
            std.debug.print("Next Token: .{s} {s}\n", .{ std.enums.tagName(TokenType, token.kind).?, token.value });
        }
        if (self.lookahead_token) |token| {
            std.debug.print("Lookahead Token: .{s} {s}\n", .{ std.enums.tagName(TokenType, token.kind).?, token.value });
        }
    }

    fn parse_definition_call(self: *Parser) !?DefinitionCall {
        var arguments: std.ArrayList(Token) = .empty;
        errdefer arguments.deinit(self.allocator);

        var m_name: ?Token = undefined;

        const has_failed = has_failed: {
            m_name = self.eat(TokenType.LowerVariable);
            if (m_name == null) {
                break :has_failed true;
            }

            if (self.eat(TokenType.OpenParenthesis) == null) {
                // diagnostics
                // synchronize
                break :has_failed true;
            }
            while (self.eat(TokenType.UpperVariable)) |token2| {
                try arguments.append(self.allocator, token2);
                if (self.eat(TokenType.CloseParenthesis) != null)
                    break :has_failed false;
                if (self.eat(TokenType.Comma) != null)
                    continue;
            } else break :has_failed true;
        };

        if (has_failed) {
            arguments.clearAndFree(self.allocator);
            return null;
        }

        return if (m_name) |name|
            .{
                .name = name,
                .arguments = try arguments.toOwnedSlice(self.allocator),
            }
        else
            null;
    }

    fn parse_definition_parameter_token(self: *Parser) ?Token {
        return self.eat(TokenType.UpperVariable) orelse self.eat(TokenType.Underscore);
    }

    fn parse_description(self: *Parser) ?Description {
        _ = self;
        return null;
    }

    fn parse_block(self: *Parser) !?Block {
        const configurations = try self.parse_configurations();

        var definitions: std.ArrayList(Definition) = .empty;
        errdefer definitions.deinit(self.allocator);

        var descriptions: std.ArrayList(Description) = .empty;
        errdefer descriptions.deinit(self.allocator);

        while (true) {
            if (try self.parse_definition()) |definition|
                try definitions.append(self.allocator, definition)
            else if (self.parse_description()) |description|
                try descriptions.append(self.allocator, description)
            else
                break;
        }

        //std.debug.print("Definitions {d}", .{definitions.items.len});
        if (definitions.items.len == 0 and descriptions.items.len == 0)
            return null;

        return .{
            .configurations = configurations,
            .descriptions = try descriptions.toOwnedSlice(self.allocator),
            .definitions = try definitions.toOwnedSlice(self.allocator),
        };
    }
};

const ParsedProgram = struct {
    arena: std.heap.ArenaAllocator,
    program: Program,

    fn init(allocator: std.mem.Allocator, text: []const u8) !ParsedProgram {
        var arena = std.heap.ArenaAllocator.init(allocator);
        errdefer arena.deinit();

        var parser = Parser.init(arena.allocator(), text);
        const program = try parser.parse_program();
        return ParsedProgram{ .arena = arena, .program = program };
    }

    fn deinit(self: *ParsedProgram) void {
        self.arena.deinit();
    }
};

test "parser empty" {
    const allocator = std.testing.allocator;

    const parsed_program = try ParsedProgram.init(allocator,
        \\
        \\
        \\
    );

    const program = parsed_program.program;

    try std.testing.expectEqual(0, program.blocks.len);
    try std.testing.expectEqual(0, program.configurations.len);
}

test "parser definition" {
    const allocator = std.testing.allocator;

    var parsed_program = try ParsedProgram.init(allocator,
        \\
        \\ def captures(From, Captured_To)
        \\  captures(From, To, Captured)
        \\
    );
    defer parsed_program.deinit();

    const program = parsed_program.program;

    try std.testing.expectEqual(1, program.blocks.len);
    try std.testing.expectEqual(0, program.configurations.len);

    try std.testing.expectEqual(1, program.blocks[0].definitions.len);

    try std.testing.expectEqualStrings("captures", program.blocks[0].definitions[0].header.name.value);

    try std.testing.expectEqual(4, program.blocks[0].definitions[0].header.parameters.len);

    try std.testing.expectEqual(1, program.blocks[0].definitions[0].calls.len);

    try std.testing.expectEqualStrings("captures", program.blocks[0].definitions[0].calls[0].name.value);
    try std.testing.expectEqual(3, program.blocks[0].definitions[0].calls[0].arguments.len);
    try std.testing.expectEqualStrings("Captured", program.blocks[0].definitions[0].calls[0].arguments[2].value);
}

test "fuzz lexer" {
    //try std.testing.fuzz({}, fuzzLexer, .{});
}

fn fuzzLexer(context: void, smith: *std.testing.Smith) !void {
    _ = context;

    _ = smith;
    //const a = smith.value(u8);
    //try std.testing.expect(a != 3);
}

fn testOne(context: void, smith: *std.testing.Smith) !void {
    _ = context;
    // Try passing `--fuzz` to `zig build test` and see if it manages to fail this test case!

    const gpa = std.testing.allocator;
    var list: std.ArrayList(u8) = .empty;
    defer list.deinit(gpa);
    while (!smith.eos()) switch (smith.value(enum { add_data, dup_data })) {
        .add_data => {
            const slice = try list.addManyAsSlice(gpa, smith.value(u4));
            smith.bytes(slice);
        },
        .dup_data => {
            if (list.items.len == 0) continue;
            if (list.items.len > std.math.maxInt(u32)) return error.SkipZigTest;
            const len = smith.valueRangeAtMost(u32, 1, @min(32, list.items.len));
            const off = smith.valueRangeAtMost(u32, 0, @intCast(list.items.len - len));
            try list.appendSlice(gpa, list.items[off..][0..len]);
            try std.testing.expectEqualSlices(
                u8,
                list.items[off..][0..len],
                list.items[list.items.len - len ..],
            );
        },
    };
}

test "fuzz example" {
    //try std.testing.fuzz({}, testOne, .{});
}
