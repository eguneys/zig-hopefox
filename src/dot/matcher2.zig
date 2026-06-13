const std = @import("std");
const testing = std.testing;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const Table = @import("table.zig").Table;
const Tree = @import("tree.zig").Tree;
const History = @import("runner2.zig").History;
const chess = @import("chess/types.zig");
const par = @import("parser2.zig");
const lx = @import("lexer2.zig");
const log = @import("logs.zig");

pub const Matcher = struct {
    pub const Slice = struct { off: usize, len: usize };
    pub fn run_dot(allocator: Allocator, history: History, slice: Slice, dot: par.SideEffects) !void {
        _ = allocator;
        _ = history;
        _ = dot;
        _ = slice;
    }
    pub fn run_star(allocator: Allocator, history: *History, slice: Slice, star: par.Becomes) !void {
        switch (history.program.symbols[star.action.tag].identity.tag) {
            lx.SymbolTag.Captures => {
                try dispatch_captures(allocator, history, slice, star);
            },
            lx.SymbolTag.Check => {
                try dispatch_checks(allocator, history, slice, star);
            },
            lx.SymbolTag.Blocks => {
                try dispatch_blocks(allocator, history, slice, star);
            },
            else => {},
        }
    }

    fn dispatch_captures(allocator: Allocator, history: *History, slice: Slice, star: par.Becomes) !void {
        const from_symbol = history.program.symbols[star.from];
        const to_symbol = history.program.symbols[star.to];
        const captured_symbol = history.program.symbols[star.action.one];
        const From = history.table.getColumn(from_symbol.identity);
        const To = history.table.getColumn(to_symbol.identity);
        const Captured = history.table.getColumn(captured_symbol.identity);

        for (slice.off..slice.off + slice.len) |off| {
            const bb_from = From[off];
            const bb_to = To[off];
            const bb_captured = Captured[off];

            const position = history.getPosition(off);

            var bb_from2 = bb_from.bitand(Symbols.bitboard(from_symbol, position));
            while (bb_from2.next()) |sq_from| {
                const aa_captured = Symbols.captures(from_symbol, sq_from, position);
                var bb_captured2 = bb_captured
                    .bitand(Symbols.bitboard(captured_symbol, position))
                    .bitand(aa_captured);
                while (bb_captured2.next()) |sq_captured| {
                    var bb_to2 = bb_to
                        .bitand(chess.Bitboard.fromSquare(sq_captured));
                    while (bb_to2.next()) |sq_to| {
                        try history.table.duplicateLastRow(allocator);

                        history.table.setLastRow(from_symbol.identity, chess.Bitboard.fromSquare(sq_from));
                        history.table.setLastRow(to_symbol.identity, chess.Bitboard.fromSquare(sq_to));
                        history.table.setLastRow(captured_symbol.identity, chess.Bitboard.fromSquare(sq_captured));

                        var move: chess.Move = undefined;
                        move.from = @truncate(@intFromEnum(sq_from));
                        move.to = @truncate(@intFromEnum(sq_to));
                        move.kind = chess.MoveType.Normal;
                        const ref = try history.tree.appendChild(allocator, off, move);
                        try history.nodes.append(allocator, ref);
                    }
                }
            }
        }
    }

    fn dispatch_checks(allocator: Allocator, history: *History, slice: Slice, star: par.Becomes) !void {
        const from_symbol = history.program.symbols[star.from];
        const to_symbol = history.program.symbols[star.to];
        const checked_symbol = history.program.symbols[star.action.one];
        const action_symbol = history.program.symbols[star.action.tag];
        const From = history.table.getColumn(from_symbol.identity);
        const To = history.table.getColumn(to_symbol.identity);
        const Checked = history.table.getColumn(checked_symbol.identity);

        for (slice.off..slice.off + slice.len) |off| {
            const bb_from = From[off];
            const bb_to = To[off];
            const bb_checked = Checked[off];

            const position = history.getPosition(off);

            var bb_from2 = bb_from.bitand(Symbols.bitboard(from_symbol, position));
            while (bb_from2.next()) |sq_from| {
                var bb_checked2 = bb_checked
                    .bitand(Symbols.bitboard(checked_symbol, position));
                while (bb_checked2.next()) |sq_checked| {
                    const aa_checked = Symbols.checks(from_symbol, sq_from, sq_checked, position.occupied());
                    var bb_to2 = bb_to
                        .bitand(aa_checked);
                    while (bb_to2.next()) |sq_to| {
                        try history.table.duplicateLastRow(allocator);

                        history.table.setLastRow(from_symbol.identity, chess.Bitboard.fromSquare(sq_from));
                        history.table.setLastRow(to_symbol.identity, chess.Bitboard.fromSquare(sq_to));
                        history.table.setLastRow(checked_symbol.identity, chess.Bitboard.fromSquare(sq_checked));

                        const aa_checkray = chess.Attacks.from_to(sq_to, sq_checked).unset(sq_checked);
                        history.table.setLastRow(action_symbol.identity, aa_checkray);

                        var move: chess.Move = undefined;
                        move.from = @truncate(@intFromEnum(sq_from));
                        move.to = @truncate(@intFromEnum(sq_to));
                        move.kind = chess.MoveType.Normal;
                        const ref = try history.tree.appendChild(allocator, off, move);
                        try history.nodes.append(allocator, ref);
                    }
                }
            }
        }
    }

    fn dispatch_blocks(allocator: Allocator, history: *History, slice: Slice, star: par.Becomes) !void {
        const from_symbol = history.program.symbols[star.from];
        const to_symbol = history.program.symbols[star.to];
        const blocks_symbol = history.program.symbols[star.action.one];
        const From = history.table.getColumn(from_symbol.identity);
        const To = history.table.getColumn(to_symbol.identity);
        const Blocks = history.table.getColumn(blocks_symbol.identity);

        log.d(star.from);
        log.d(star.to);
        for (slice.off..slice.off + slice.len) |off| {
            const bb_from = From[off];
            const bb_to = To[off];
            const bb_blocks = Blocks[off];

            const position = history.getPosition(off);

            var bb_from2 = bb_from.bitand(Symbols.bitboard(from_symbol, position));
            while (bb_from2.next()) |sq_from| {
                const aa_blocks = Symbols.moves(from_symbol, sq_from, position.occupied());
                var bb_to2 = bb_to
                    .bitand(bb_blocks)
                    .bitand(aa_blocks);
                while (bb_to2.next()) |sq_to| {
                    try history.table.duplicateLastRow(allocator);

                    history.table.setLastRow(from_symbol.identity, chess.Bitboard.fromSquare(sq_from));
                    history.table.setLastRow(to_symbol.identity, chess.Bitboard.fromSquare(sq_to));
                    history.table.setLastRow(blocks_symbol.identity, chess.Bitboard.fromSquare(sq_to));

                    var move: chess.Move = undefined;
                    move.from = @truncate(@intFromEnum(sq_from));
                    move.to = @truncate(@intFromEnum(sq_to));
                    move.kind = chess.MoveType.Normal;
                    const ref = try history.tree.appendChild(allocator, off, move);
                    try history.nodes.append(allocator, ref);
                }
            }
        }
    }
};

pub const Symbols = struct {
    fn action_bitboard(symbol: par.Symbol, table: Table(par.SymbolRef, chess.Bitboard), row: usize) chess.Bitboard {
        return switch (symbol.name) {
            lx.SymbolId.Check => table.getColumn(symbol)[row],
            else => chess.Bitboard.Zero,
        };
    }

    fn bitboard(symbol: par.Symbol, position: chess.Position) chess.Bitboard {
        const role_bb = switch (symbol.identity.tag) {
            lx.SymbolTag.bishop => position.bb_bishop,
            lx.SymbolTag.pawn => position.bb_pawn,
            lx.SymbolTag.rook => position.bb_rook,
            lx.SymbolTag.queen => position.bb_queen,
            lx.SymbolTag.king => position.bb_king,
            lx.SymbolTag.knight => position.bb_knight,
            lx.SymbolTag.sq => position.bb_vacant(),
            else => chess.Bitboard.Zero, // might throw error
        };

        return if (symbol.props.turn) role_bb.bitand(position.bb_turn()) else if (symbol.props.opponent) role_bb.bitand(position.bb_opponent()) else role_bb;
    }

    fn moves(symbol: par.Symbol, from: chess.Square, occupied: chess.Bitboard) chess.Bitboard {
        return switch (symbol.identity.tag) {
            lx.SymbolTag.bishop => chess.Attacks.eyes_plus(from, occupied, chess.DirectionPlus.Diagonal),
            lx.SymbolTag.rook => chess.Attacks.eyes_plus(from, occupied, chess.DirectionPlus.Straight),
            lx.SymbolTag.queen => chess.Attacks.eyes_plus(from, occupied, chess.DirectionPlus.All),
            lx.SymbolTag.king => chess.Bitboard.Zero,
            lx.SymbolTag.knight => chess.Bitboard.Zero,
            lx.SymbolTag.pawn => chess.Bitboard.Zero,
            lx.SymbolTag.sq => chess.Bitboard.Zero,
            else => chess.Bitboard.Zero,
        };
    }

    fn captures(symbol: par.Symbol, from: chess.Square, position: chess.Position) chess.Bitboard {
        return switch (symbol.identity.tag) {
            lx.SymbolTag.bishop => chess.Attacks.ray_plus(from, position.occupied(), chess.DirectionPlus.Diagonal),
            lx.SymbolTag.rook => chess.Attacks.ray_plus(from, position.occupied(), chess.DirectionPlus.Straight),
            lx.SymbolTag.queen => chess.Attacks.ray_plus(from, position.occupied(), chess.DirectionPlus.All),
            lx.SymbolTag.king => chess.Attacks.king_plus(from, chess.DirectionPlus.All),
            lx.SymbolTag.knight => chess.Bitboard.Zero,
            lx.SymbolTag.pawn => chess.Attacks.pawn_plus(from, if (position.colorOn(from) == chess.Color.White) chess.DirectionPlus.Forward else chess.DirectionPlus.Backward),
            lx.SymbolTag.sq => chess.Bitboard.Zero,
            else => chess.Bitboard.Zero,
        };
    }

    fn checks(symbol: par.Symbol, from: chess.Square, check: chess.Square, occupied: chess.Bitboard) chess.Bitboard {
        var bb_to = switch (symbol.identity.tag) {
            lx.SymbolTag.bishop => chess.Attacks.eyes_plus(from, occupied, chess.DirectionPlus.Diagonal),
            lx.SymbolTag.rook => chess.Attacks.eyes_plus(from, occupied, chess.DirectionPlus.Straight),
            lx.SymbolTag.queen => chess.Attacks.eyes_plus(from, occupied, chess.DirectionPlus.All),
            lx.SymbolTag.king => chess.Attacks.king_plus(from, chess.DirectionPlus.All),
            lx.SymbolTag.knight => chess.Bitboard.Zero,
            lx.SymbolTag.pawn => chess.Bitboard.Zero,
            lx.SymbolTag.sq => chess.Bitboard.Zero,
            else => chess.Bitboard.Zero,
        };

        var result = chess.Bitboard.Zero;

        while (bb_to.next()) |to| {
            const bb_to2 = switch (symbol.identity.tag) {
                lx.SymbolTag.bishop => chess.Attacks.ray_plus(to, occupied, chess.DirectionPlus.Diagonal),
                lx.SymbolTag.rook => chess.Attacks.ray_plus(to, occupied, chess.DirectionPlus.Straight),
                lx.SymbolTag.queen => chess.Attacks.ray_plus(to, occupied, chess.DirectionPlus.All),
                lx.SymbolTag.king => chess.Attacks.king_plus(to, chess.DirectionPlus.All),
                lx.SymbolTag.knight => chess.Bitboard.Zero,
                lx.SymbolTag.pawn => chess.Bitboard.Zero,
                lx.SymbolTag.sq => chess.Bitboard.Zero,
                else => chess.Bitboard.Zero,
            };
            if (bb_to2.has(check)) {
                result = result.set(to);
            }
        }

        return result;
    }
};
