const std = @import("std");
const atomic = @import("atomic_filters.zig");
const parser = @import("parser.zig");

const Compilation = struct {
    parsification: parser.Parsification,

    fn asdf(allocator: std.mem.Allocator) Compilation {
        const parsification = parser.Parsification.init(allocator);
        return Compilation{
            .parsification = parsification,
        };
    }

    fn parse(self: *Compilation, text: []const u8) !void {
        self.parsification.parse(text);
        self.parsification.parse_semantics();
        self.parsification.parse_ir();
    }

    fn compile(self: *Compilation) !CompiledProgram {
        return .{};
    }

    fn deinit(self: *Compilation) void {
        self.parsification.deinit();
    }
};

const AtomicCall = struct {
    action: atomic.DefinitionCallAction,
    arguments: usize,
};

const CompiledDefinition = []AtomicCall;

const DescriptionBinding = parser.IrDescriptionDescription;

const CompiledDescription = struct {
    binding: DescriptionBinding,
    bound_lines: []CompiledDefinition,
    children: []CompiledDescription,
};

const CompiledDescriptionBlock = struct {
    descriptions: []CompiledDescription,
};

const CompiledProgram = struct {
    blocks: []CompiledDescriptionBlock,
};
