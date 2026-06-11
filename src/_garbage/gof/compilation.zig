const std = @import("std");
const atomic = @import("atomic_filters.zig");
const parser = @import("parser.zig");
const symbols = @import("symbols.zig");
const table = @import("table.zig");
const flat_map = @import("flat_map.zig");
const chess = @import("chess/types.zig");

const errors = error{
    UnmatchedParameterList,
    NoSecondParameterFound,
    NoParameterFoundForArgument,
};

pub const Compilation = struct {
    parsification: parser.Parsification,
    definitions_by_id: std.AutoHashMapUnmanaged(parser.IrDefinitionId, parser.IrDefinition),

    pub fn init(allocator: std.mem.Allocator) Compilation {
        var res = Compilation{ .parsification = parser.Parsification.init(allocator), .definitions_by_id = undefined };

        res.definitions_by_id = .{};
        errdefer res.definitions_by_id.deinit();
        return res;
    }

    pub fn parse(self: *Compilation, text: []const u8) !void {
        _ = try self.parsification.parse(text);
        _ = try self.parsification.parse_semantics();
        const ir_program = try self.parsification.parse_ir();

        for (ir_program.blocks) |block| {
            for (block.definitions) |def| {
                try self.definitions_by_id.put(self.parsification.arena.allocator(), def.header.id, def);
            }
        }
    }

    pub fn compile(self: *Compilation, allocator: std.mem.Allocator) !CompiledProgram {
        var blocks: std.ArrayList(CompiledDescriptionBlock) = .empty;
        errdefer blocks.deinit(allocator);

        var table_builder = table.TableBuilder(symbols.DescriptionSymbol, chess.Bitboard).init();

        for (self.parsification.ir_program.?.blocks) |block| {
            for (block.descriptions) |desc| {
                for (desc.lines) |line| {
                    for (line.arguments) |argument| {
                        try table_builder.addColumn(allocator, argument.one);
                        if (argument.two) |two|
                            try table_builder.addColumn(allocator, two);
                    }
                }
            }
        }

        for (self.parsification.ir_program.?.blocks) |block| {
            const compiled_block = try self.compile_block(allocator, block, table_builder);
            try blocks.append(allocator, compiled_block);
        }

        return .{
            .blocks = try blocks.toOwnedSlice(allocator),
            .table = try table_builder.toTable(allocator, 2048),
        };
    }

    pub fn tagsFor(self: Compilation, line_no: usize) []parser.SemanticDescriptionTag {
        const line = self.parsification.semantic_program.?.find_line(line_no).?;
        return line.tags;
    }

    pub fn linesFor(self: Compilation, line_no: usize) parser.DescriptionLine {
        const line = self.parsification.program.?.find_line(line_no).?;
        return line;
    }

    const CompiledDescriptionBuilder = struct {
        depth: usize,
        children: ?std.ArrayList(CompiledDescriptionBuilder),
        bound_lines: std.ArrayList([]const AtomicCall),
        line_no: usize,

        fn init(allocator: std.mem.Allocator, depth: usize, line_no: usize, line: []const AtomicCall) !CompiledDescriptionBuilder {
            var bound_lines = try std.ArrayList([]const AtomicCall).initCapacity(allocator, 1);
            errdefer bound_lines.deinit(allocator);

            try bound_lines.append(allocator, line);

            return .{
                .depth = depth,
                .line_no = line_no,
                .bound_lines = bound_lines,
                .children = null,
            };
        }

        fn appendAtDepth(self: *CompiledDescriptionBuilder, allocator: std.mem.Allocator, depth: usize, line_no: usize, bound_lines: []const AtomicCall) !void {
            if (self.depth < depth) {
                if (self.children) |children| {
                    try children.items[children.items.len - 1].appendAtDepth(allocator, depth, line_no, bound_lines);
                } else {
                    self.children = try std.ArrayList(CompiledDescriptionBuilder).initCapacity(allocator, 1);
                    try self.children.?.append(allocator, try CompiledDescriptionBuilder.init(allocator, depth, line_no, bound_lines));
                }
            } else if (self.depth == depth) {
                try self.bound_lines.append(allocator, bound_lines);
            }
        }

        const MapBuilder = struct {
            pub fn mapAllocator(allocator: std.mem.Allocator, builder: *CompiledDescriptionBuilder) !?CompiledDescription {
                const children =
                    if (builder.children) |list| here: {
                        var result = try std.ArrayList(CompiledDescription).initCapacity(allocator, list.items.len);
                        for (list.items) |*item| {
                            if (try MapBuilder.mapAllocator(allocator, item)) |result_item|
                                try result.append(allocator, result_item);
                        }
                        break :here try result.toOwnedSlice(allocator);
                    } else null;

                return .{
                    .depth = builder.depth,
                    .bound_lines = try builder.bound_lines.toOwnedSlice(allocator),
                    .children = children,
                    .line_no = builder.line_no,
                };
            }
        };

        fn deinit(self: *CompiledDescriptionBuilder, allocator: std.mem.Allocator) void {
            if (self.children) |*children| {
                for (children.items) |*child| {
                    child.deinit(allocator);
                }
                children.deinit(allocator);
            }
            self.bound_lines.deinit(allocator);
        }

        fn toOwnedSlice(self: *CompiledDescriptionBuilder, allocator: std.mem.Allocator) !?[]CompiledDescription {
            const result =
                if (self.children) |*list| here: {
                    var result = try std.ArrayList(CompiledDescription).initCapacity(allocator, list.items.len);
                    errdefer result.deinit(allocator);

                    for (list.items) |*item| {
                        if (try MapBuilder.mapAllocator(allocator, item)) |result_item|
                            try result.append(allocator, result_item);
                        item.deinit(allocator);
                    }
                    list.deinit(allocator);
                    break :here try result.toOwnedSlice(allocator);
                } else null;
            self.bound_lines.deinit(allocator);
            return result;
        }
    };

    fn compile_block(self: *Compilation, allocator: std.mem.Allocator, block: parser.IrBlock, table_builder: table.TableBuilder(symbols.DescriptionSymbol, chess.Bitboard)) !CompiledDescriptionBlock {
        const lines = [0]AtomicCall{};
        var builder = try CompiledDescriptionBuilder.init(allocator, 0, 0, &lines);
        errdefer builder.deinit(allocator);

        var last_depth: usize = 0;
        for (block.descriptions) |desc| {
            for (desc.lines) |line| {
                const compiled_definition = try self.compile_definition(allocator, line, table_builder);

                if (line.binding == .desc_if) {
                    last_depth = line.indent;
                }
                try builder.appendAtDepth(allocator, last_depth, line.line_no, compiled_definition);
            }
        }

        return .{
            .descriptions = (try builder.toOwnedSlice(allocator)).?,
        };
    }

    fn compile_definition(self: *Compilation, allocator: std.mem.Allocator, line: parser.IrDescriptionLine, table_builder: table.TableBuilder(symbols.DescriptionSymbol, chess.Bitboard)) !CompiledDefinition {
        var atomic_calls: std.ArrayList(AtomicCall) = .empty;
        errdefer atomic_calls.deinit(allocator);

        if (self.definitions_by_id.get(line.definition_call_id)) |definition| {
            for (definition.calls) |call| {
                const atomic_call = try Compilation.compile_atomic_call(allocator, call, definition.header.parameters, line.arguments, table_builder);
                try atomic_calls.append(allocator, atomic_call);
            }
        }

        return atomic_calls.toOwnedSlice(allocator);
    }

    fn compile_atomic_call(allocator: std.mem.Allocator, call: parser.IrDefinitionCall, parameters: []parser.IrDefinitionParameter, arguments: []parser.IrDescriptionArgument, table_builder: table.TableBuilder(symbols.DescriptionSymbol, chess.Bitboard)) !AtomicCall {
        var argument_symbols: std.ArrayList(AtomicArgument) = .empty;
        errdefer argument_symbols.deinit(allocator);

        for (call.arguments) |argument| {
            const argument2 = try Compilation.find_argument(argument, parameters, arguments, table_builder);
            try argument_symbols.append(allocator, argument2);
        }

        return .{
            .action = call.action,
            .arguments = try argument_symbols.toOwnedSlice(allocator),
        };
    }

    fn find_argument(argument: parser.IrDefinitionCallArgumentId, parameters: []parser.IrDefinitionParameter, arguments: []parser.IrDescriptionArgument, table_builder: table.TableBuilder(symbols.DescriptionSymbol, chess.Bitboard)) !AtomicArgument {
        const symbol = try Compilation.find_argument_symbol(argument, parameters, arguments);
        return .{ .symbol = symbol, .column = try table_builder.findColumn(symbol) };
    }

    fn find_argument_symbol(argument: parser.IrDefinitionCallArgumentId, parameters: []parser.IrDefinitionParameter, arguments: []parser.IrDescriptionArgument) !symbols.DescriptionSymbol {
        if (parameters.len != arguments.len) {
            // diagnostics
            return errors.UnmatchedParameterList;
        }
        for (parameters, arguments) |candidate, parameter| {
            if (candidate.one == argument) {
                return parameter.one;
            }
            if (candidate.two) |two| {
                if (two == argument) {
                    if (parameter.two) |ptwo| {
                        return ptwo;
                    } else {
                        // diagnostics
                        return errors.NoSecondParameterFound;
                    }
                }
            }
        }
        // diagnostics
        return errors.NoParameterFoundForArgument;
    }

    pub fn deinit(self: *Compilation) void {
        self.parsification.deinit();
    }
};

pub const AtomicArgument = struct { symbol: symbols.DescriptionSymbol, column: usize };

pub const AtomicCall = struct {
    action: atomic.DefinitionCallAction,
    arguments: []AtomicArgument,

    pub fn deinit(self: AtomicCall, allocator: std.mem.Allocator) void {
        allocator.free(self.arguments);
    }
};

const CompiledDefinition = []const AtomicCall;

const DescriptionBinding = parser.IrDescriptionBinding;

pub const CompiledDescription = struct {
    depth: usize,
    bound_lines: []CompiledDefinition,
    children: ?[]CompiledDescription,
    line_no: usize,

    pub fn deinit(self: *CompiledDescription, allocator: std.mem.Allocator) void {
        for (self.bound_lines) |calls| {
            for (calls) |*call| call.deinit(allocator);
            allocator.free(calls);
        }
        allocator.free(self.bound_lines);
        if (self.children) |children| {
            for (children) |*child| {
                child.deinit(allocator);
            }
            allocator.free(children);
        }
    }
};

const CompiledDescriptionBlock = struct {
    descriptions: []CompiledDescription,
    pub fn deinit(self: *CompiledDescriptionBlock, allocator: std.mem.Allocator) void {
        for (self.descriptions) |*description| {
            description.deinit(allocator);
        }
        allocator.free(self.descriptions);
    }
};

pub const CompiledProgram = struct {
    blocks: []CompiledDescriptionBlock,
    table: table.Table(chess.Bitboard),

    pub fn deinit(self: *CompiledProgram, allocator: std.mem.Allocator) void {
        for (self.blocks) |*block| {
            block.deinit(allocator);
        }
        allocator.free(self.blocks);
        self.table.deinit(allocator);
    }
};

test "basic usage" {
    const ally = std.testing.allocator;

    var compilation = Compilation.init(ally);
    defer compilation.deinit();

    try compilation.parse(
        \\ ###
        \\
        \\if hello(king, queen)
        \\
        \\ def hello(From, To)
        \\   captures(From)
    );

    var program = try compilation.compile(ally);
    defer program.deinit(ally);

    try std.testing.expectEqual(2, program.table.columns.len);
}

test "more table " {
    const ally = std.testing.allocator;

    var compilation = Compilation.init(ally);
    defer compilation.deinit();

    try compilation.parse(
        \\ ###
        \\
        \\if hello(king, queen)
        \\ve hello2(king, queen, bishop_rook)
        \\
        \\ def hello(From, To)
        \\   captures(From)
        \\
        \\def hello2(From, To, Captured_X)
    );

    var program = try compilation.compile(ally);
    defer program.deinit(ally);

    try std.testing.expectEqual(4, program.table.columns.len);
}
