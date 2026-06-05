const std = @import("std");
const atomic = @import("atomic_filters.zig");
const parser = @import("parser.zig");
const symbols = @import("symbols.zig");
const table = @import("table.zig");

const errors = error{
    NoSecondParameterFound,
    NoParameterFoundForArgument,
};

const Compilation = struct {
    parsification: parser.Parsification,
    definitions_by_id: std.AutoHashMap(parser.IrDefinitionId, parser.IrDefinition),

    fn init(allocator: std.mem.Allocator) Compilation {
        var parsification = parser.Parsification.init(allocator);
        var definitions_by_id: std.AutoHashMap(parser.IrDefinitionId, parser.IrDefinition) = .init(parsification.arena.allocator());
        errdefer definitions_by_id.deinit();
        return Compilation{
            .parsification = parsification,
            .definitions_by_id = definitions_by_id,
        };
    }

    fn parse(self: *Compilation, text: []const u8) !void {
        _ = try self.parsification.parse(text);
        _ = try self.parsification.parse_semantics();
        const ir_program = try self.parsification.parse_ir();

        for (ir_program.blocks) |block| {
            for (block.definitions) |def| {
                try self.definitions_by_id.put(def.header.id, def);
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

        const mytable = try table.Table(symbols.DescriptionSymbol).initCapacity(self.parsification.arena.allocator(), 256, 2048);

        return .{
            .blocks = try blocks.toOwnedSlice(self.parsification.arena.allocator()),
            .table = mytable,
        };
    }

    const CompiledDescriptionBuilder = struct {
        depth: usize,
        children: ?std.ArrayList(CompiledDescriptionBuilder),
        bound_lines: [][]AtomicCall,

        fn init(depth: usize, bound_lines: [][]AtomicCall) CompiledDescriptionBuilder {
            return .{
                .depth = depth,
                .bound_lines = bound_lines,
                .children = null,
            };
        }

        fn appendAtDepth(self: *CompiledDescriptionBuilder, allocator: std.mem.Allocator, depth: usize, bound_lines: []AtomicCall) !void {
            if (self.depth < depth) {
                if (self.children) |children| {
                    try children.getLast().appendAtDepth(allocator, depth, bound_lines);
                } else {
                    self.children = std.ArrayList(CompiledDescriptionBuilder).initCapacity(allocator, 1);
                    try self.children.?.append(allocator, CompiledDescriptionBuilder.init(depth, bound_lines));
                }
            } else if (self.depth == depth) {
                try self.bound_lines.appendSlice(allocator, bound_lines);
            }
        }

        fn toOwnedSlice(self: *CompiledDescriptionBuilder, allocator: std.mem.Allocator) ![]CompiledDescription {

            self.bound_lines
            if (self.children) |children| {
                for (children) |child| {}
            } else {
                return .empty;
            }
        }
    };

    fn compile_block(self: *Compilation, block: parser.IrBlock) !CompiledDescriptionBlock {
        var builder = CompiledDescriptionBuilder.init();

        var last_depth = 0;
        for (block.descriptions) |desc| {
            for (desc.lines) |line| {
                const compiled_definition = try self.compile_definition(line);

                if (line.binding == .desc_if) {
                    last_depth = line.indent;
                }
                builder.appendAtDepth(self.parsification.arena.allocator(), last_depth, compiled_definition);
            }
        }

        return .{
            .descriptions = try builder.toOwnedSlice(self.parsification.arena.allocator()),
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

const CompiledDefinition = []AtomicCall;

const DescriptionBinding = parser.IrDescriptionBinding;

const CompiledDescription = struct {
    depth: usize,
    bound_lines: []CompiledDefinition,
    children: []CompiledDescription,
};

const CompiledDescriptionBlock = struct {
    descriptions: []CompiledDescription,
};

const CompiledProgram = struct {
    blocks: []CompiledDescriptionBlock,
    table: table.Table(symbols.DescriptionSymbol),
};

test "basic usage" {
    const ally = std.testing.allocator;

    var compilation = Compilation.init(ally);

    try compilation.parse(
        \\ ###
        \\
        \\if hello(king, queen)
        \\
        \\ def hello(From, To)
        \\   captures(From)
    );

    const program = try compilation.compile();

    try std.testing.expectEqual(program.table.columns.len, 2);
}
