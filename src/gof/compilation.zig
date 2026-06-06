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

const Compilation = struct {
    parsification: parser.Parsification,
    definitions_by_id: std.AutoHashMapUnmanaged(parser.IrDefinitionId, parser.IrDefinition),

    fn init(allocator: std.mem.Allocator) Compilation {
        var res = Compilation{ .parsification = parser.Parsification.init(allocator), .definitions_by_id = undefined };

        res.definitions_by_id = .{};
        errdefer res.definitions_by_id.deinit();
        return res;
    }

    fn parse(self: *Compilation, text: []const u8) !void {
        _ = try self.parsification.parse(text);
        _ = try self.parsification.parse_semantics();
        const ir_program = try self.parsification.parse_ir();

        for (ir_program.blocks) |block| {
            for (block.definitions) |def| {
                try self.definitions_by_id.put(self.parsification.arena.allocator(), def.header.id, def);
            }
        }
    }

    fn compile(self: *Compilation) !CompiledProgram {
        var blocks: std.ArrayList(CompiledDescriptionBlock) = .empty;
        errdefer blocks.deinit(self.parsification.arena.allocator());

        for (self.parsification.ir_program.?.blocks) |block| {
            const compiled_block = try self.compile_block(block);
            try blocks.append(self.parsification.arena.allocator(), compiled_block);
        }

        var table_builder = table.TableBuilder(symbols.DescriptionSymbol, chess.Bitboard).init();

        for (self.parsification.ir_program.?.blocks) |block| {
            for (block.descriptions) |desc| {
                for (desc.lines) |line| {
                    for (line.arguments) |argument| {
                        try table_builder.addColumn(self.parsification.arena.allocator(), argument.one);
                        if (argument.two) |two|
                            try table_builder.addColumn(self.parsification.arena.allocator(), two);
                    }
                }
            }
        }

        return .{
            .blocks = try blocks.toOwnedSlice(self.parsification.arena.allocator()),
            .table = try table_builder.toTable(self.parsification.arena.allocator(), 1024),
        };
    }

    const CompiledDescriptionBuilder = struct {
        depth: usize,
        children: ?std.ArrayList(CompiledDescriptionBuilder),
        bound_lines: std.ArrayList([]const AtomicCall),

        fn init(allocator: std.mem.Allocator, depth: usize, line: []const AtomicCall) !CompiledDescriptionBuilder {
            var bound_lines = try std.ArrayList([]const AtomicCall).initCapacity(allocator, 1);
            errdefer bound_lines.deinit(allocator);

            try bound_lines.append(allocator, line);

            return .{
                .depth = depth,
                .bound_lines = bound_lines,
                .children = null,
            };
        }

        fn appendAtDepth(self: *CompiledDescriptionBuilder, allocator: std.mem.Allocator, depth: usize, bound_lines: []const AtomicCall) !void {
            if (self.depth < depth) {
                if (self.children) |children| {
                    try children.items[children.items.len - 1].appendAtDepth(allocator, depth, bound_lines);
                } else {
                    self.children = try std.ArrayList(CompiledDescriptionBuilder).initCapacity(allocator, 1);
                    try self.children.?.append(allocator, try CompiledDescriptionBuilder.init(allocator, depth, bound_lines));
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
                };
            }
        };

        fn toOwnedSlice(self: *CompiledDescriptionBuilder, allocator: std.mem.Allocator) !?[]CompiledDescription {
            const result =
                if (self.children) |list| here: {
                    var result = try std.ArrayList(CompiledDescription).initCapacity(allocator, list.items.len);
                    for (list.items) |*item| {
                        if (try MapBuilder.mapAllocator(allocator, item)) |result_item|
                            try result.append(allocator, result_item);
                    }
                    break :here try result.toOwnedSlice(allocator);
                } else null;
            return result;
        }
    };

    fn compile_block(self: *Compilation, block: parser.IrBlock) !CompiledDescriptionBlock {
        const lines = [0]AtomicCall{};
        var builder = try CompiledDescriptionBuilder.init(self.parsification.arena.allocator(), 0, &lines);

        var last_depth: usize = 0;
        for (block.descriptions) |desc| {
            for (desc.lines) |line| {
                const compiled_definition = try self.compile_definition(line);

                if (line.binding == .desc_if) {
                    last_depth = line.indent;
                }
                try builder.appendAtDepth(self.parsification.arena.allocator(), last_depth, compiled_definition);
            }
        }

        return .{
            .descriptions = (try builder.toOwnedSlice(self.parsification.arena.allocator())).?,
        };
    }

    fn compile_definition(self: *Compilation, line: parser.IrDescriptionLine) !CompiledDefinition {
        var atomic_calls: std.ArrayList(AtomicCall) = .empty;
        errdefer atomic_calls.deinit(self.parsification.arena.allocator());

        if (self.definitions_by_id.get(line.definition_call_id)) |definition| {
            for (definition.calls) |call| {
                const atomic_call = try self.compile_atomic_call(call, definition.header.parameters, line.arguments);
                try atomic_calls.append(self.parsification.arena.allocator(), atomic_call);
            }
        }

        return atomic_calls.toOwnedSlice(self.parsification.arena.allocator());
    }

    fn compile_atomic_call(self: *Compilation, call: parser.IrDefinitionCall, parameters: []parser.IrDefinitionParameter, arguments: []parser.IrDescriptionArgument) !AtomicCall {
        var argument_columns: std.ArrayList(usize) = .empty;
        errdefer argument_columns.deinit(self.parsification.arena.allocator());

        for (call.arguments) |argument| {
            const argument_column = try Compilation.find_argument_column(argument, parameters, arguments);
            try argument_columns.append(self.parsification.arena.allocator(), argument_column);
        }

        return .{
            .action = call.action,
            .argument_columns = try argument_columns.toOwnedSlice(self.parsification.arena.allocator()),
        };
    }

    fn find_argument_column(argument: parser.IrDefinitionCallArgumentId, parameters: []parser.IrDefinitionParameter, arguments: []parser.IrDescriptionArgument) !usize {
        if (parameters.len != arguments.len) {
            // diagnostics
            return errors.UnmatchedParameterList;
        }
        for (parameters, arguments) |candidate, parameter| {
            if (candidate.one == argument) {
                return try Compilation.find_column_for_symbol(parameter.one);
            }
            if (candidate.two) |two| {
                if (two == argument) {
                    if (parameter.two) |ptwo| {
                        return try Compilation.find_column_for_symbol(ptwo);
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

    fn find_column_for_symbol(symbol: symbols.DescriptionSymbol) !usize {
        return symbol.id;
    }

    fn deinit(self: *Compilation) void {
        self.parsification.deinit();
    }
};

const AtomicCall = struct {
    action: atomic.DefinitionCallAction,
    argument_columns: []usize,
};

const CompiledDefinition = []const AtomicCall;

const DescriptionBinding = parser.IrDescriptionBinding;

const CompiledDescription = struct {
    depth: usize,
    bound_lines: []CompiledDefinition,
    children: ?[]CompiledDescription,
};

const CompiledDescriptionBlock = struct {
    descriptions: []CompiledDescription,
};

const CompiledProgram = struct {
    blocks: []CompiledDescriptionBlock,
    table: table.Table(chess.Bitboard),
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

    const program = try compilation.compile();

    try std.testing.expectEqual(2, program.table.columns.len);
}
