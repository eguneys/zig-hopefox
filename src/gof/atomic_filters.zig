const std = @import("std");
const Allocator = std.mem.Allocator;
const chess = @import("chess/types.zig");
const rr = @import("runner.zig");

const Table = @import("table.zig").Table(chess.Bitboard);
const AtomicCall = @import("compilation.zig").AtomicCall;

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

pub const CallRunner = struct {
    pub fn atomic_call(allocator: Allocator, history: []const chess.Position, table: Table, range: rr.Range, call: AtomicCall) !void {
        try switch (call.action) {
            .action => Atomic_action_dispatchers.dispatch(allocator, history, table, range, call),
            .filter => Atomic_filter_dispatchers.dispatch(allocator, history, table, range, call),
        };
    }
};

pub const Atomic_action = enum {
    Captures,
};

pub const Atomic_filter = enum {};

const Atomic_action_dispatchers = struct {
    fn dispatch(allocator: Allocator, history: []const chess.Position, table: Table, range: rr.Range, call: AtomicCall) !void {
        try switch (call.action.action) {
            Atomic_action.Captures => dispatch_capture(allocator, history, table, range, call.argument_columns),
        };
    }

    fn dispatch_capture(allocator: Allocator, history: []const chess.Position, table: Table, range: rr.Range, columns: []usize) !void {
        _ = allocator;
        _ = history;
        _ = table;
        _ = range;
        _ = columns;
    }
};

const Atomic_filter_dispatchers = struct {
    fn dispatch(allocator: Allocator, history: []const chess.Position, table: Table, range: rr.Range, call: AtomicCall) !void {
        _ = allocator;
        _ = history;
        _ = table;
        _ = range;
        _ = call;
    }
};
