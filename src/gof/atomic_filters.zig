const std = @import("std");

pub const Atomic_filter = enum {};

pub const Atomic_action = enum { Captures };

const AtomicActionTag = enum { action, filter };
pub const DefinitionCallAction = union(AtomicActionTag) { action: Atomic_action, filter: Atomic_filter };

pub const Parser = struct {
    pub fn definition_call_action(text: []const u8) ?DefinitionCallAction {
        if (std.mem.eql(u8, text, "captures")) {
            return .{ .action = .Captures };
        }
        return null;
    }
};
