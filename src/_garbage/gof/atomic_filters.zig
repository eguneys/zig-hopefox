const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const chess = @import("chess/types.zig");
const tre = @import("chess/tree.zig");
const rr = @import("runner.zig");
const cc = @import("compilation.zig");
const sym = @import("symbols.zig");

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
    pub fn atomic_call(allocator: Allocator, history: *ArrayList(*tre.PositionNode), table: *Table, range: rr.Range, call: AtomicCall) !void {
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
    fn dispatch(allocator: Allocator, history: *ArrayList(*tre.PositionNode), table: *Table, range: rr.Range, call: AtomicCall) !void {
        try switch (call.action.action) {
            Atomic_action.Captures => dispatch_capture(allocator, history, table, range, call.arguments),
        };
    }

    fn dispatch_capture(allocator: Allocator, history: *ArrayList(*tre.PositionNode), table: *Table, range: rr.Range, arguments: []cc.AtomicArgument) !void {
        if (arguments.len != 3) {
            return errors.InvalidParity;
        }

        const from = arguments[0];
        const to = arguments[1];
        const captured = arguments[2];

        const From = table.getColumn(from.column);
        const To = table.getColumn(to.column);
        const Captured = table.getColumn(captured.column);

        for (range.start..range.end) |i| {
            const position = history.items[i].position;
            const from_symbol_position = sym.SymbolPosition.init(from.symbol, position);
            const to_symbol_position = sym.SymbolPosition.init(to.symbol, position);
            const captured_symbol_position = sym.SymbolPosition.init(captured.symbol, position);
            const bb_symbol_from = from_symbol_position.bitboard();
            const bb_symbol_to = to_symbol_position.bitboard();
            const bb_symbol_captured = captured_symbol_position.bitboard();

            const bb_from = From[i];
            var bb_from2 = bb_symbol_from.bitand(bb_from);
            while (bb_from2.next()) |sq_from| {
                const from_piece = position.pieceOn(sq_from) orelse break;
                const aa_from = from_symbol_position.captures(sq_from);

                const bb_to = To[i];
                var bb_to2 = bb_to.bitand(aa_from);
                _ = bb_symbol_to;
                while (bb_to2.next()) |sq_to| {
                    const bb_captured = Captured[i];
                    var bb_captured2 = bb_symbol_captured.bitand(bb_captured);
                    bb_captured2 = bb_captured2.bitand(chess.Bitboard.fromSquare(sq_to));
                    while (bb_captured2.next()) |sq_captured| {
                        try table.appendDuplicateLastRow(allocator);

                        table.setLastRow(from.column, chess.Bitboard.fromSquare(sq_from));
                        table.setLastRow(to.column, chess.Bitboard.fromSquare(sq_to));
                        table.setLastRow(captured.column, chess.Bitboard.fromSquare(sq_captured));

                        var p = position;
                        p.remove_piece(sq_to);
                        p.remove_piece(sq_from);
                        p.put_piece(sq_to, from_piece);
                        p.flipTurn();
                        try history.append(allocator, try history.items[i].addChild(allocator, p));
                    }
                }
            }
        }
    }
};

const Atomic_filter_dispatchers = struct {
    fn dispatch(allocator: Allocator, history: *ArrayList(*tre.PositionNode), table: *Table, range: rr.Range, call: AtomicCall) !void {
        _ = allocator;
        _ = history;
        _ = table;
        _ = range;
        _ = call;
    }
};
