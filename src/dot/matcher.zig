const std = @import("std");
const testing = std.testing;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const Table = @import("table.zig").Table;
const Tree = @import("tree.zig").Tree;
const History = @import("runner.zig").History;
const chess = @import("chess/types.zig");
const par = @import("parser.zig");
const lx = @import("lexer.zig");

pub const Matcher = struct {
    pub const Slice = struct { off: usize, len: usize };
    pub fn run_dot(allocator: Allocator, history: History, slice: Slice, dot: par.Dot) !void {
        _ = allocator;
        _ = history;
        _ = dot;
        _ = slice;
    }
    pub fn run_star(allocator: Allocator, history: *History, slice: Slice, star: par.Star) !void {
        switch (history.program.tokens[star.starword].identity.starword) {
            lx.StarWordId.Captures => {
                try dispatch_captures(allocator, history, slice, star);
            },
            else => {},
        }
    }

    fn dispatch_captures(allocator: Allocator, history: *History, slice: Slice, star: par.Star) !void {
        for (slice.off..slice.off + slice.len) |off| {
            const from_symbol = history.program.tokens[star.owner.symbol].identity.symbol;
            const to_symbol = history.program.tokens[star.becomes].identity.symbol;
            const captured_symbol = history.program.tokens[star.one].identity.symbol;
            const From = history.table.getColumn(from_symbol);
            const To = history.table.getColumn(to_symbol);
            const Captured = history.table.getColumn(captured_symbol);
            const position = history.getPosition(off);

            for (From, To, Captured) |bb_from, bb_to, bb_captured| {
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

                            history.table.setLastRow(from_symbol, chess.Bitboard.fromSquare(sq_from));
                            history.table.setLastRow(to_symbol, chess.Bitboard.fromSquare(sq_to));
                            history.table.setLastRow(captured_symbol, chess.Bitboard.fromSquare(sq_captured));

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
    }
};

pub const Symbols = struct {
    fn bitboard(symbol: lx.Symbol, position: chess.Position) chess.Bitboard {
        return switch (symbol.name) {
            lx.SymbolId.bishop => position.bb_bishop,
            lx.SymbolId.pawn => position.bb_pawn,
            lx.SymbolId.rook => position.bb_rook,
            lx.SymbolId.queen => position.bb_queen,
            lx.SymbolId.king => position.bb_king,
            lx.SymbolId.knight => position.bb_knight,
            lx.SymbolId.sq => position.bb_vacant(),
        };
    }

    fn captures(symbol: lx.Symbol, from: chess.Square, position: chess.Position) chess.Bitboard {
        return switch (symbol.name) {
            lx.SymbolId.bishop => chess.Attacks.ray_plus(from, position.occupied(), chess.DirectionPlus.Diagonal),
            lx.SymbolId.rook => chess.Attacks.ray_plus(from, position.occupied(), chess.DirectionPlus.Straight),
            lx.SymbolId.queen => chess.Attacks.ray_plus(from, position.occupied(), chess.DirectionPlus.All),
            lx.SymbolId.king => chess.Attacks.king_plus(from, chess.DirectionPlus.All),
            lx.SymbolId.knight => chess.Bitboard.Zero,
            lx.SymbolId.pawn => chess.Attacks.pawn_plus(from, if (position.colorOn(from) == chess.Color.White) chess.DirectionPlus.Forward else chess.DirectionPlus.Backward),
            lx.SymbolId.sq => chess.Bitboard.Zero,
        };
    }
};

fn log2(a: chess.Bitboard, b: chess.Bitboard) void {
    std.debug.print("\nA:\n{s}\nB:\n{s}\n", .{ chess.Prints.bitboard(a), chess.Prints.bitboard(b) });
}
