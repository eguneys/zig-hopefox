const std = @import("std");
const Allocator = std.mem.Allocator;
const chess = @import("chess/types.zig");
const rr = @import("runner.zig");
const cc = @import("compilation.zig");

const Table = @import("table.zig").Table(chess.Bitboard);
const AtomicCall = @import("compilation.zig").AtomicCall;

const AtomicActionTag = enum { action, filter };
pub const DefinitionCallAction = union(AtomicActionTag) { action: Atomic_action, filter: Atomic_filter };

const errors = error{InvalidParity};

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
            Atomic_action.Captures => dispatch_capture(allocator, history, table, range, call.arguments),
        };
    }

    fn dispatch_capture(allocator: Allocator, history: []const chess.Position, table: Table, range: rr.Range, arguments: []cc.AtomicArgument) !void {
        _ = allocator;

        if (arguments.len != 3) {
            return errors.InvalidParity;
        }

        const from = arguments[0];
        const to = arguments[1];
        const captured = arguments[2];

        const From = table.getColumn(from.column);
        const To = table.getColumn(to.column);
        const Captured = table.getColumn(captured.column);

        _ = From;
        _ = To;
        _ = Captured;

        for (range.start..range.end) |i| {
            const p = history[i];

            _ = p;
            //for (From) |bb_from| {}
        }
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
