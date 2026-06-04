const std = @import("std");
const atomic_filters = @import("atomic_filters.zig");

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
    Ve,
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
    Hash,
    TripleHash,
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

    fn triple_hash(self: *Lexer) ?Token {
        const i_start = self.i_next;
        while (self.i_next < self.text.len and self.text[self.i_next] == '#') {
            self.i_next += 1;
            self.column_no += 1;
        }
        return if (self.i_next == i_start)
            null
        else if (self.i_next - i_start == 1)
            Token{ .kind = TokenType.Hash, .line_no = self.line_no, .column_no = self.column_no, .value = self.text[i_start..self.i_next] }
        else
            Token{ .kind = TokenType.TripleHash, .line_no = self.line_no, .column_no = self.column_no, .value = self.text[i_start..self.i_next] };
    }

    fn next_token(self: *Lexer) Token {
        self.skip_whitespace();

        if (self.i_next == self.text.len) {
            return Token{ .kind = TokenType.Eof, .line_no = self.line_no, .column_no = 0, .value = undefined };
        }

        if (self.triple_hash()) |token| {
            return token;
        }

        const column_no = self.column_no;
        if (self.next_word()) |word| {
            if (std.mem.eql(u8, word, "def")) {
                return Token{ .kind = TokenType.Def, .line_no = self.line_no, .column_no = column_no, .value = word };
            } else if (std.mem.eql(u8, word, "if")) {
                return Token{ .kind = TokenType.If, .line_no = self.line_no, .column_no = column_no, .value = word };
            } else if (std.mem.eql(u8, word, "ve")) {
                return Token{ .kind = TokenType.Ve, .line_no = self.line_no, .column_no = column_no, .value = word };
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

    lexer = Lexer.init(" \n\n   #");
    token = lexer.next_token();
    try std.testing.expectEqual(TokenType.Hash, token.kind);

    lexer = Lexer.init(" \n\n #  ## ### #####");
    token = lexer.next_token();
    try std.testing.expectEqual(TokenType.Hash, token.kind);
    token = lexer.next_token();
    try std.testing.expectEqual(TokenType.TripleHash, token.kind);
    token = lexer.next_token();
    try std.testing.expectEqual(TokenType.TripleHash, token.kind);
    token = lexer.next_token();
    try std.testing.expectEqual(TokenType.TripleHash, token.kind);
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
    description: Token,
    name: Token,
    arguments: []Token,
    tags: []Token,
};

const Description = struct { lines: []DescriptionLine };

const Configuration = struct { name: Token };

const Block = struct {
    configurations: ?[]Configuration,
    descriptions: []Description,
    definitions: []Definition,
};

const Program = struct {
    blocks: []Block,
    configurations: ?[]Configuration,
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
            if (block.definitions.len == 0 and block.descriptions.len == 0) {
                continue;
            }
            try blocks.append(self.allocator, block);
        }

        return .{
            .configurations = configurations,
            .blocks = try blocks.toOwnedSlice(self.allocator),
        };
    }

    fn parse_configurations(self: *Parser) !?[]Configuration {
        var configurations: std.ArrayList(Configuration) = .empty;
        errdefer configurations.deinit(self.allocator);

        if (self.eat(TokenType.Equals) == null) {
            configurations.clearAndFree(self.allocator);
            return null;
        }
        while (self.parse_configuration()) |configuration| {
            try configurations.append(self.allocator, configuration);
        }

        return try configurations.toOwnedSlice(self.allocator);
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
        if (self.eat(TokenType.UpperVariable) orelse self.eat(TokenType.LowerVariable)) |name| {
            return Configuration{ .name = name };
        }
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

    fn parse_description_line(self: *Parser) !?DescriptionLine {
        var arguments: std.ArrayList(Token) = .empty;
        errdefer arguments.deinit(self.allocator);

        var tags: std.ArrayList(Token) = .empty;
        errdefer tags.deinit(self.allocator);

        var name: Token = undefined;
        var description: Token = undefined;

        const has_failed = has_failed: {
            if (self.eat(TokenType.If) orelse self.eat(TokenType.Ve)) |token| {
                description = token;
            } else {
                break :has_failed true;
            }
            if (self.eat(TokenType.LowerVariable)) |token| {
                name = token;
            } else {
                break :has_failed true;
            }

            if (self.eat(TokenType.OpenParenthesis) == null) {
                // diagnostics
                // synchronize
                break :has_failed true;
            }
            while (self.parse_description_argument_token()) |token| {
                try arguments.append(self.allocator, token);
                if (self.eat(TokenType.CloseParenthesis) != null)
                    break :has_failed false;
                if (self.eat(TokenType.Comma) != null)
                    continue;
            } else break :has_failed true;
        };

        if (has_failed) {
            arguments.clearAndFree(self.allocator);
            tags.clearAndFree(self.allocator);
            return null;
        }

        return .{
            .name = name,
            .description = description,
            .arguments = try arguments.toOwnedSlice(self.allocator),
            .tags = try tags.toOwnedSlice(self.allocator),
        };
    }

    fn parse_description_argument_token(self: *Parser) ?Token {
        return self.eat(TokenType.LowerVariable) orelse self.eat(TokenType.Underscore);
    }

    fn parse_description(self: *Parser) !?Description {
        var lines: std.ArrayList(DescriptionLine) = .empty;
        errdefer lines.deinit(self.allocator);

        while (try self.parse_description_line()) |line| {
            try lines.append(self.allocator, line);
        }
        if (lines.items.len == 0) {
            lines.clearAndFree(self.allocator);
            return null;
        }
        return .{
            .lines = try lines.toOwnedSlice(self.allocator),
        };
    }

    fn parse_block(self: *Parser) !?Block {
        if (self.eat(TokenType.TripleHash) == null) {
            return null;
        }

        const configurations = try self.parse_configurations();

        var definitions: std.ArrayList(Definition) = .empty;
        errdefer definitions.deinit(self.allocator);

        var descriptions: std.ArrayList(Description) = .empty;
        errdefer descriptions.deinit(self.allocator);

        while (true) {
            if (try self.parse_definition()) |definition|
                try definitions.append(self.allocator, definition)
            else if (try self.parse_description()) |description|
                try descriptions.append(self.allocator, description)
            else
                break;
        }

        //std.debug.print("Definitions {d}", .{definitions.items.len});
        //if (definitions.items.len == 0 and descriptions.items.len == 0)
        //    return null;

        return .{
            .configurations = configurations,
            .descriptions = try descriptions.toOwnedSlice(self.allocator),
            .definitions = try definitions.toOwnedSlice(self.allocator),
        };
    }
};

const Compilation = struct {
    arena: std.heap.ArenaAllocator,
    program: ?Program = null,
    semantic_program: ?SemanticProgram = null,

    fn init(allocator: std.mem.Allocator) Compilation {
        var arena = std.heap.ArenaAllocator.init(allocator);
        errdefer arena.deinit();
        return .{ .arena = arena };
    }

    fn parse(self: *Compilation, text: []const u8) !Program {
        var parser = Parser.init(self.arena.allocator(), text);
        self.program = try parser.parse_program();
        return self.program.?;
    }

    fn parse_semantics(self: *Compilation) !SemanticProgram {
        return if (self.program) |program| {
            var semantic_parser = SemanticParser.init(self.arena.allocator());
            self.semantic_program = try semantic_parser.parse_program(program);
            return self.semantic_program.?;
        } else error.ProgramNotParsed;
    }

    fn deinit(self: *Compilation) void {
        self.arena.deinit();
    }
};

test "parser empty" {
    const allocator = std.testing.allocator;

    var compilation = Compilation.init(allocator);

    const program = try compilation.parse(
        \\
        \\
        \\
    );

    try std.testing.expectEqual(0, program.blocks.len);
    try std.testing.expect(program.configurations == null);
    try std.testing.expectEqual(null, program.configurations);
}

test "parser definition" {
    const allocator = std.testing.allocator;

    var compilation = Compilation.init(allocator);
    defer compilation.deinit();

    const program = try compilation.parse(
        \\###
        \\
        \\ def captures(From, Captured_To)
        \\  captures(From, To, Captured)
        \\
    );

    try std.testing.expectEqual(1, program.blocks.len);
    try std.testing.expectEqual(program.configurations, null);

    try std.testing.expectEqual(1, program.blocks[0].definitions.len);

    try std.testing.expectEqualStrings("captures", program.blocks[0].definitions[0].header.name.value);

    try std.testing.expectEqual(4, program.blocks[0].definitions[0].header.parameters.len);

    try std.testing.expectEqual(1, program.blocks[0].definitions[0].calls.len);

    try std.testing.expectEqualStrings("captures", program.blocks[0].definitions[0].calls[0].name.value);
    try std.testing.expectEqual(3, program.blocks[0].definitions[0].calls[0].arguments.len);
    try std.testing.expectEqualStrings("Captured", program.blocks[0].definitions[0].calls[0].arguments[2].value);
}

test "parser description" {
    const allocator = std.testing.allocator;

    var compilation = Compilation.init(allocator);
    defer compilation.deinit();

    const program = try compilation.parse(
        \\###
        \\
        \\ if captures(king, queen_rook)
        \\ ve attacks(king2, bishop, f3)
        \\   if captures(king2, king3_knight)
        \\
    );

    try std.testing.expectEqual(1, program.blocks.len);
    try std.testing.expectEqual(null, program.configurations);

    try std.testing.expectEqual(1, program.blocks[0].descriptions.len);

    try std.testing.expectEqual(3, program.blocks[0].descriptions[0].lines.len);

    try std.testing.expectEqualStrings("captures", program.blocks[0].descriptions[0].lines[0].name.value);

    try std.testing.expectEqualStrings("if", program.blocks[0].descriptions[0].lines[0].description.value);
    try std.testing.expectEqualStrings("ve", program.blocks[0].descriptions[0].lines[1].description.value);

    try std.testing.expectEqual(4, program.blocks[0].descriptions[0].lines[0].arguments.len);
    try std.testing.expectEqual(TokenType.Underscore, program.blocks[0].descriptions[0].lines[0].arguments[2].kind);
}

test "parser mixed" {
    const allocator = std.testing.allocator;

    var compilation = Compilation.init(allocator);
    defer compilation.deinit();

    const program = try compilation.parse(
        \\###
        \\
        \\ def captures(From, Captured_To)
        \\  captures(From, To, Captured)
        \\
        \\ if captures(king, queen_rook)
        \\ ve attacks(king2, bishop, f3)
        \\   if captures(king2, king3_knight)
        \\
        \\ def captures(From, Captured_To)
        \\  captures(From, To, Captured)
        \\
        \\
    );

    try std.testing.expectEqual(1, program.blocks.len);
    try std.testing.expectEqual(null, program.configurations);

    try std.testing.expectEqual(1, program.blocks[0].descriptions.len);
    try std.testing.expectEqual(2, program.blocks[0].definitions.len);
}

test "parser blocks" {
    const allocator = std.testing.allocator;

    var compilation = Compilation.init(allocator);
    defer compilation.deinit();

    const program = try compilation.parse(
        \\
        \\
        \\###
        \\
        \\ def captures(From, Captured_To)
        \\  captures(From, To, Captured)
        \\
        \\ if captures(king, queen_rook)
        \\ ve attacks(king2, bishop, f3)
        \\   if captures(king2, king3_knight)
        \\
        \\###
        \\
        \\ def captures(From, Captured_To)
        \\  captures(From, To, Captured)
        \\
        \\###
    );

    try std.testing.expectEqual(2, program.blocks.len);
}

test "configurations program" {
    const allocator = std.testing.allocator;

    var compilation = Compilation.init(allocator);
    defer compilation.deinit();

    const program = try compilation.parse(
        \\=GlobalConfig123 anotherConfigabc
        \\
        \\###
        \\
        \\ def captures(From, Captured_To)
        \\  captures(From, To, Captured)
        \\
        \\###
    );

    try std.testing.expectEqual(2, program.configurations.?.len);
    try std.testing.expectEqualStrings("GlobalConfig123", program.configurations.?[0].name.value);
    try std.testing.expectEqualStrings("anotherConfigabc", program.configurations.?[1].name.value);
}

test "configurations program with block" {
    const allocator = std.testing.allocator;

    var compilation = Compilation.init(allocator);
    defer compilation.deinit();

    const program = try compilation.parse(
        \\ ###
        \\=GlobalConfig123 anotherConfigabc
        \\
        \\###
        \\
        \\ def captures(From, Captured_To)
        \\  captures(From, To, Captured)
        \\
        \\###
    );

    try std.testing.expectEqual(null, program.configurations);
    try std.testing.expectEqual(1, program.blocks.len);
    try std.testing.expectEqual(null, program.blocks[0].configurations);
}

test "configurations block" {
    const allocator = std.testing.allocator;

    var compilation = Compilation.init(allocator);
    defer compilation.deinit();

    const program = try compilation.parse(
        \\ ###
        \\=GlobalConfig123 anotherConfigabc
        \\
        \\###
        \\
        \\=GlobalConfig123 anotherConfigabc
        \\ def captures(From, Captured_To)
        \\  captures(From, To, Captured)
        \\
        \\###
    );

    try std.testing.expectEqual(null, program.configurations);
    try std.testing.expectEqual(1, program.blocks.len);
    try std.testing.expectEqual(2, program.blocks[0].configurations.?.len);
}

const SemanticDefinitionName = []const u8;
const SemanticDefinitionParameter = struct { name: []const u8, name2: ?[]const u8 };

const SemanticDefinitionTag = enum { Win, Cond };

const SemanticDefinitionHeader = struct {
    name: SemanticDefinitionName,
    parameters: []SemanticDefinitionParameter,
    tags: []SemanticDefinitionTag,
};

const DefinitionCallArgument = struct { name: []const u8 };

const SemanticDefinitionCall = struct {
    name: atomic_filters.DefinitionCallAction,
    arguments: []DefinitionCallArgument,
};

const SemanticDefinition = struct {
    header: SemanticDefinitionHeader,
    calls: []const SemanticDefinitionCall,
};

const SemanticDescriptionDescription = enum { desc_if, desc_ve };
const SemanticDescriptionName = []const u8;

const SemanticDescriptionArgument = struct { name: []const u8, name2: ?[]const u8 };

const SemanticDescriptionTag = enum {};

const SemanticDescriptionLine = struct {
    description: SemanticDescriptionDescription,
    name: SemanticDescriptionName,
    arguments: []SemanticDescriptionArgument,
    tags: []SemanticDescriptionTag,
};

const SemanticDescription = struct { lines: []SemanticDescriptionLine };

const SemanticConfigurationName = enum { id };
const SemanticConfigurationValue = u64;

const SemanticConfiguration = struct { name: SemanticConfigurationName, value: SemanticConfigurationValue };

const SemanticBlock = struct {
    configurations: ?[]SemanticConfiguration,
    descriptions: []SemanticDescription,
    definitions: []SemanticDefinition,
};

const SemanticProgram = struct {
    blocks: []SemanticBlock,
    configurations: ?[]SemanticConfiguration,
};

const SemanticParser = struct {
    allocator: std.mem.Allocator,

    fn init(allocator: std.mem.Allocator) SemanticParser {
        return .{
            .allocator = allocator,
        };
    }

    fn parse_program(self: *SemanticParser, program: Program) !SemanticProgram {
        const configurations =
            if (program.configurations) |configurations|
                try self.parse_configurations(configurations)
            else
                null;
        const blocks = try self.parse_blocks(program);

        return .{
            .configurations = configurations,
            .blocks = blocks,
        };
    }

    fn parse_configurations(self: *SemanticParser, configurations: []Configuration) ![]SemanticConfiguration {
        var semantic_configs: std.ArrayList(SemanticConfiguration) = .empty;
        errdefer semantic_configs.deinit(self.allocator);

        for (configurations) |config| {
            if (SemanticParser.parse_semantic_configuration(config)) |semantic_config| {
                try semantic_configs.append(self.allocator, semantic_config);
            }
        }
        return try semantic_configs.toOwnedSlice(self.allocator);
    }

    fn parse_blocks(self: *SemanticParser, program: Program) ![]SemanticBlock {
        var semantic_blocks: std.ArrayList(SemanticBlock) = .empty;
        errdefer semantic_blocks.deinit(self.allocator);

        for (program.blocks) |block| {
            try semantic_blocks.append(self.allocator, try self.parse_semantic_block(block));
        }
        return try semantic_blocks.toOwnedSlice(self.allocator);
    }

    fn parse_semantic_configuration(config: Configuration) ?SemanticConfiguration {
        _ = config;
        return null;
    }

    fn parse_semantic_block(self: *SemanticParser, block: Block) !SemanticBlock {
        const configurations = if (block.configurations) |configs|
            try self.parse_configurations(configs)
        else
            null;

        var semantic_descriptions: std.ArrayList(SemanticDescription) = .empty;
        errdefer semantic_descriptions.deinit(self.allocator);

        for (block.descriptions) |description| {
            try semantic_descriptions.append(self.allocator, try self.parse_semantic_description(description));
        }

        var semantic_definitions: std.ArrayList(SemanticDefinition) = .empty;
        errdefer semantic_definitions.deinit(self.allocator);

        for (block.definitions) |definition| {
            try semantic_definitions.append(self.allocator, try self.parse_semantic_definition(definition));
        }

        return .{
            .configurations = configurations,
            .descriptions = try semantic_descriptions.toOwnedSlice(self.allocator),
            .definitions = try semantic_definitions.toOwnedSlice(self.allocator),
        };
    }

    fn parse_semantic_description(self: *SemanticParser, description: Description) !SemanticDescription {
        var semantic_lines: std.ArrayList(SemanticDescriptionLine) = .empty;
        errdefer semantic_lines.deinit(self.allocator);

        for (description.lines) |line| {
            if (try self.parse_semantic_description_line(line)) |semantic_line| {
                try semantic_lines.append(self.allocator, semantic_line);
            }
        }
        return .{
            .lines = try semantic_lines.toOwnedSlice(self.allocator),
        };
    }

    fn parse_semantic_description_line(self: *SemanticParser, line: DescriptionLine) !?SemanticDescriptionLine {
        const description =
            if (std.mem.eql(u8, line.description.value, "if"))
                SemanticDescriptionDescription.desc_if
            else if (std.mem.eql(u8, line.description.value, "ve"))
                SemanticDescriptionDescription.desc_ve
            else
                null;

        if (description == null) {
            return null;
        }

        return .{
            .description = description.?,
            .name = line.name.value,
            .arguments = try self.parse_semantic_description_arguments(line.arguments),
            .tags = try self.parse_semantic_description_tags(line.tags),
        };
    }

    fn parse_semantic_description_tags(self: *SemanticParser, tags: []Token) ![]SemanticDescriptionTag {
        var semantic_tags: std.ArrayList(SemanticDescriptionTag) = .empty;
        errdefer semantic_tags.deinit(self.allocator);

        for (tags) |tag| {
            if (SemanticParser.parse_semantic_description_tag(tag)) |semantic_tag| {
                try semantic_tags.append(self.allocator, semantic_tag);
            }
        }
        return try semantic_tags.toOwnedSlice(self.allocator);
    }

    fn parse_semantic_description_tag(tag: Token) ?SemanticDescriptionTag {
        _ = tag;
        return null;
    }

    fn parse_semantic_description_arguments(self: *SemanticParser, arguments: []Token) ![]SemanticDescriptionArgument {
        var semantic_arguments: std.ArrayList(SemanticDescriptionArgument) = .empty;
        errdefer semantic_arguments.deinit(self.allocator);

        for (arguments) |argument| {
            try semantic_arguments.append(self.allocator, try SemanticParser.parse_semantic_description_argument(argument));
        }
        return try semantic_arguments.toOwnedSlice(self.allocator);
    }

    fn parse_semantic_description_argument(argument: Token) !SemanticDescriptionArgument {
        return .{
            .name = argument.value,
            .name2 = argument.value,
        };
    }

    fn parse_semantic_definition(self: *SemanticParser, definition: Definition) !SemanticDefinition {
        return .{
            .header = try self.parse_semantic_definition_header(definition.header),
            .calls = try self.parse_semantic_definition_calls(definition.calls),
        };
    }

    fn parse_semantic_definition_calls(self: *SemanticParser, calls: []const DefinitionCall) ![]SemanticDefinitionCall {
        var semantic_calls: std.ArrayList(SemanticDefinitionCall) = .empty;
        errdefer semantic_calls.deinit(self.allocator);

        for (calls) |call| {
            if (try self.parse_semantic_definition_call(call)) |semantic_call| {
                try semantic_calls.append(self.allocator, semantic_call);
            }
        }
        return try semantic_calls.toOwnedSlice(self.allocator);
    }

    fn parse_semantic_definition_call(self: *SemanticParser, call: DefinitionCall) !?SemanticDefinitionCall {
        if (atomic_filters.Parser.definition_call_action(call.name.value)) |name| {
            return .{
                .name = name,
                .arguments = try self.parse_semantic_definition_call_arguments(call.arguments),
            };
        } else {
            return null;
        }
    }

    fn parse_semantic_definition_call_arguments(self: *SemanticParser, arguments: []Token) ![]DefinitionCallArgument {
        var semantic_arguments: std.ArrayList(DefinitionCallArgument) = .empty;
        errdefer semantic_arguments.deinit(self.allocator);

        for (arguments) |argument| {
            try semantic_arguments.append(self.allocator, try SemanticParser.parse_semantic_definition_call_argument(argument));
        }
        return try semantic_arguments.toOwnedSlice(self.allocator);
    }

    fn parse_semantic_definition_call_argument(argument: Token) !DefinitionCallArgument {
        return .{
            .name = argument.value,
        };
    }

    fn parse_semantic_definition_header(self: *SemanticParser, header: DefinitionHeader) !SemanticDefinitionHeader {
        var semantic_parameters: std.ArrayList(SemanticDefinitionParameter) = .empty;
        errdefer semantic_parameters.deinit(self.allocator);

        for (header.parameters) |parameter| {
            try semantic_parameters.append(self.allocator, try SemanticParser.parse_semantic_definition_parameter(parameter));
        }

        var semantic_tags: std.ArrayList(SemanticDefinitionTag) = .empty;
        errdefer semantic_tags.deinit(self.allocator);

        for (header.tags) |tag| {
            if (try SemanticParser.parse_semantic_definition_tag(tag)) |semantic_tag| {
                try semantic_tags.append(self.allocator, semantic_tag);
            }
        }

        return .{
            .name = header.name.value,
            .parameters = try semantic_parameters.toOwnedSlice(self.allocator),
            .tags = try semantic_tags.toOwnedSlice(self.allocator),
        };
    }

    fn parse_semantic_definition_tag(tag: Token) !?SemanticDefinitionTag {
        if (std.mem.eql(u8, tag.value, "Win")) {
            return SemanticDefinitionTag.Win;
        } else if (std.mem.eql(u8, tag.value, "Cond")) {
            return SemanticDefinitionTag.Cond;
        }
        return null;
    }

    fn parse_semantic_definition_parameter(parameter: Token) !SemanticDefinitionParameter {
        return .{
            .name = parameter.value,
            .name2 = parameter.value,
        };
    }
};

test "semantic parser" {
    const allocator = std.testing.allocator;

    var compilation = Compilation.init(allocator);
    defer compilation.deinit();

    _ = try compilation.parse(
        \\ ###
        \\=GlobalConfig123 anotherConfigabc
        \\
        \\###
        \\
        \\=GlobalConfig123 anotherConfigabc
        \\ def captures(From, Captured_To)
        \\  captures(From, To, Captured)
        \\
        \\###
    );

    const semantic_program = try compilation.parse_semantics();

    try std.testing.expectEqual(null, semantic_program.configurations);
    try std.testing.expectEqual(1, semantic_program.blocks.len);
    try std.testing.expectEqual(0, semantic_program.blocks[0].configurations.?.len);

    try std.testing.expectEqualStrings("captures", semantic_program.blocks[0].definitions[0].header.name);
    try std.testing.expectEqualStrings("From", semantic_program.blocks[0].definitions[0].header.parameters[0].name);

    try std.testing.expectEqual(1, semantic_program.blocks[0].definitions[0].calls.len);
    try std.testing.expectEqualStrings("To", semantic_program.blocks[0].definitions[0].calls[0].arguments[1].name);
    try std.testing.expectEqualStrings("Captured", semantic_program.blocks[0].definitions[0].calls[0].arguments[2].name);

    try std.testing.expectEqual(atomic_filters.Atomic_action.Captures, semantic_program.blocks[0].definitions[0].calls[0].name.action);
}
