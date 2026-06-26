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
    pub fn run_dot(allocator: Allocator, history: *History, slice: Slice, dot: par.SideEffects) !void {
        switch (history.program.symbols[dot.action.tag].identity.tag) {
            lx.SymbolTag.Forks => {
                try Filters.dispatch_forks(allocator, history, slice, dot);
            },
            lx.SymbolTag.hanging => {
                try Filters.dispatch_hanging(allocator, history, slice, dot);
            },
            lx.SymbolTag.eyesThrough => {
                try Filters.dispatch_eyesThrough(allocator, history, slice, dot);
            },
            lx.SymbolTag.cannotBeCapturedBy => {
                try Filters.dispatch_cannotBeCapturedBy(allocator, history, slice, dot);
            },
            lx.SymbolTag.doesNotDefend => {
                try Filters.dispatch_doesNotDefend(allocator, history, slice, dot);
            },
            lx.SymbolTag.Captures => {
                try Filters.dispatch_captures(allocator, history, slice, dot);
            },
            lx.SymbolTag.Check => {
                try Filters.dispatch_checks(allocator, history, slice, dot);
            },
            else => {},
        }
    }
    pub fn run_star(allocator: Allocator, history: *History, slice: Slice, star: par.Becomes) !void {
        switch (history.program.symbols[star.action.tag].identity.tag) {
            lx.SymbolTag.Evades => {
                try dispatch_evades(allocator, history, slice, star);
            },
            lx.SymbolTag.Movesto => {
                try dispatch_movesto(allocator, history, slice, star);
            },
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

    fn dispatch_evades(allocator: Allocator, history: *History, slice: Slice, star: par.Becomes) !void {
        const from_symbol = history.program.symbols[star.from];
        const to_symbol = history.program.symbols[star.to];
        const evade_symbol = history.program.symbols[star.action.one];
        const From = history.table.getColumn(from_symbol.identity);
        const To = history.table.getColumn(to_symbol.identity);
        const Evade = history.table.getColumn(evade_symbol.identity);

        for (slice.off..slice.off + slice.len) |off| {
            const bb_from = From[off];
            const bb_to = To[off];
            const bb_evade = Evade[off];

            const position = history.getPosition(off);

            const bb_evade2 = bb_evade
                .bitand(Symbols.bitboard(evade_symbol, position));

            var bb_from2 = bb_from.bitand(Symbols.bitboard(from_symbol, position));
            while (bb_from2.next()) |sq_from| {
                const aa_moves = Symbols.moves(from_symbol, sq_from, position.occupied());

                var bb_evade3 = bb_evade2;

                while (bb_evade3.next()) |sq_evade| {
                    const aa_evade = Symbols.moves(evade_symbol, sq_evade, position.occupied());
                    var bb_to2 = bb_to
                        .bitdiff(aa_evade)
                        .bitand(aa_moves);
                    while (bb_to2.next()) |sq_to| {
                        try history.table.duplicateRow(allocator, off);

                        history.table.setLastRow(from_symbol.identity, chess.Bitboard.fromSquare(sq_from));
                        history.table.setLastRow(to_symbol.identity, chess.Bitboard.fromSquare(sq_to));
                        history.table.setLastRow(evade_symbol.identity, chess.Bitboard.fromSquare(sq_evade));

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

    fn dispatch_movesto(allocator: Allocator, history: *History, slice: Slice, star: par.Becomes) !void {
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
                const aa_captured = Symbols.moves(from_symbol, sq_from, position.occupied());
                var bb_captured2 = bb_captured
                    .bitand(Symbols.bitboard(captured_symbol, position))
                    .bitand(aa_captured);

                while (bb_captured2.next()) |sq_captured| {
                    var bb_to2 = bb_to
                        .bitand(chess.Bitboard.fromSquare(sq_captured));
                    while (bb_to2.next()) |sq_to| {
                        try history.table.duplicateRow(allocator, off);

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
                        try history.table.duplicateRow(allocator, off);

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
        const checks_symbol = history.program.symbols[star.action.tag];
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
                    const aa_checked = Symbols.checks(from_symbol, sq_from, sq_checked, position.occupied(), checks_symbol);
                    var bb_to2 = bb_to
                        .bitand(aa_checked);
                    while (bb_to2.next()) |sq_to| {
                        try history.table.duplicateRow(allocator, off);

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
                    try history.table.duplicateRow(allocator, off);

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
            lx.SymbolTag.turn => position.bb_turn(),
            lx.SymbolTag.opponent => position.bb_opponent(),
            else => chess.Bitboard.Zero, // might throw error
        };

        return if (symbol.props.turn) role_bb.bitand(position.bb_turn()) else if (symbol.props.opponent) role_bb.bitand(position.bb_opponent()) else role_bb;
    }

    fn moves(symbol: par.Symbol, from: chess.Square, occupied: chess.Bitboard) chess.Bitboard {
        return switch (symbol.identity.tag) {
            lx.SymbolTag.bishop => chess.Attacks.eyes_plus(from, occupied, chess.DirectionPlus.Diagonal),
            lx.SymbolTag.rook => chess.Attacks.eyes_plus(from, occupied, chess.DirectionPlus.Straight),
            lx.SymbolTag.queen => chess.Attacks.eyes_plus(from, occupied, chess.DirectionPlus.All),
            lx.SymbolTag.king => chess.Attacks.king_plus(from, chess.DirectionPlus.All),
            lx.SymbolTag.knight => chess.Attacks.knight_plus(from, chess.DirectionPlus.All),
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
            lx.SymbolTag.knight => chess.Attacks.knight_plus(from, chess.DirectionPlus.All),
            lx.SymbolTag.pawn => chess.Attacks.pawn_plus(from, if (position.colorOn(from) == chess.Color.White) chess.DirectionPlus.Forward else chess.DirectionPlus.Backward),
            lx.SymbolTag.sq => chess.Bitboard.Zero,
            lx.SymbolTag.turn => chess.Attacks.piece_eyes(from, position.occupied(), position.getPiece(from)),
            lx.SymbolTag.opponent => chess.Attacks.piece_eyes(from, position.occupied(), position.getPiece(from)),
            else => chess.Bitboard.Zero,
        };
    }

    fn checks(symbol: par.Symbol, from: chess.Square, check: chess.Square, occupied: chess.Bitboard, checks_symbol: par.Symbol) chess.Bitboard {
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

        return if (checks_symbol.props.vacant)
            result.bitdiff(occupied)
        else
            result;
    }
};

pub const Filters = struct {
    fn dispatch_doesNotDefend(allocator: Allocator, history: *History, slice: Matcher.Slice, star: par.SideEffects) !void {
        const from_symbol = history.program.symbols[star.from];
        const From = history.table.getColumn(from_symbol.identity);
        const to_symbol = history.program.symbols[star.action.one];
        const To = history.table.getColumn(to_symbol.identity);

        for (slice.off..slice.off + slice.len) |off| {
            const bb_from = From[off];
            const bb_to = To[off];

            const position = history.getPosition(off);

            var bb_from2 = bb_from
                .bitand(Symbols.bitboard(from_symbol, position));

            const bb_defended = bb_to
                .bitand(Symbols.bitboard(to_symbol, position));

            while (bb_from2.next()) |sq_from| {
                const aa_defended = Symbols.captures(from_symbol, sq_from, position);
                var bb_defended2 = bb_defended.bitdiff(aa_defended);

                if (bb_defended2.isNotEmpty()) {
                    try history.table.duplicateRow(allocator, off);

                    history.table.setLastRow(from_symbol.identity, chess.Bitboard.fromSquare(sq_from));

                    const move = chess.Move.none;
                    const ref = try history.tree.appendChild(allocator, off, move);
                    try history.nodes.append(allocator, ref);
                }
            }
        }
    }

    fn dispatch_cannotBeCapturedBy(allocator: Allocator, history: *History, slice: Matcher.Slice, star: par.SideEffects) !void {
        const from_symbol = history.program.symbols[star.from];
        const From = history.table.getColumn(from_symbol.identity);
        const by_symbol = history.program.symbols[star.action.one];
        const By = history.table.getColumn(by_symbol.identity);

        for (slice.off..slice.off + slice.len) |off| {
            const bb_from = From[off];
            const bb_by = By[off];

            const position = history.getPosition(off);

            var bb_from2 = bb_from
                .bitand(Symbols.bitboard(from_symbol, position));

            const bb_attacker2 = bb_by
                .bitand(Symbols.bitboard(by_symbol, position));

            while (bb_from2.next()) |sq_from| {
                var bb_attacker3 = bb_attacker2;

                while (bb_attacker3.next()) |sq_capture| {
                    if (!Symbols.captures(by_symbol, sq_capture, position).has(sq_from)) {
                        try history.table.duplicateRow(allocator, off);

                        history.table.setLastRow(from_symbol.identity, chess.Bitboard.fromSquare(sq_from));

                        const move = chess.Move.none;
                        const ref = try history.tree.appendChild(allocator, off, move);
                        try history.nodes.append(allocator, ref);
                    }
                }
            }
        }
    }

    fn dispatch_eyesThrough(allocator: Allocator, history: *History, slice: Matcher.Slice, star: par.SideEffects) !void {
        const from_symbol = history.program.symbols[star.from];
        const to_symbol = history.program.symbols[star.action.one];
        const through_symbol = history.program.symbols[star.action.two];
        const From = history.table.getColumn(from_symbol.identity);
        const To = history.table.getColumn(to_symbol.identity);
        const Through = history.table.getColumn(through_symbol.identity);

        for (slice.off..slice.off + slice.len) |off| {
            const bb_from = From[off];
            const bb_to = To[off];
            const bb_through = Through[off];

            const position = history.getPosition(off);

            var bb_from2 = bb_from
                .bitand(Symbols.bitboard(from_symbol, position));

            const bb_to2 = bb_to.bitand(Symbols.bitboard(to_symbol, position));

            const bb_through2 = bb_through.bitand(Symbols.bitboard(through_symbol, position));

            while (bb_from2.next()) |sq_from| {
                const aa_from = Symbols.moves(from_symbol, sq_from, position.occupied());

                var bb_through3 = bb_through2.bitand(aa_from);

                while (bb_through3.next()) |sq_through| {
                    const aa_to =
                        Symbols.moves(from_symbol, sq_from, position.occupied().unset(sq_through))
                            .bitdiff(Symbols.moves(from_symbol, sq_from, position.occupied()));

                    if (aa_to.bitand(bb_to2).single()) |sq_to| {
                        try history.table.duplicateRow(allocator, off);

                        history.table.setLastRow(from_symbol.identity, chess.Bitboard.fromSquare(sq_from));
                        history.table.setLastRow(to_symbol.identity, chess.Bitboard.fromSquare(sq_to));
                        history.table.setLastRow(through_symbol.identity, chess.Bitboard.fromSquare(sq_through));

                        const move = chess.Move.none;
                        const ref = try history.tree.appendChild(allocator, off, move);
                        try history.nodes.append(allocator, ref);
                    }
                }
            }
        }
    }

    fn dispatch_hanging(allocator: Allocator, history: *History, slice: Matcher.Slice, star: par.SideEffects) !void {
        const from_symbol = history.program.symbols[star.from];
        const From = history.table.getColumn(from_symbol.identity);

        for (slice.off..slice.off + slice.len) |off| {
            const bb_from = From[off];

            const position = history.getPosition(off);

            var bb_from2 = bb_from
                .bitand(Symbols.bitboard(from_symbol, position));

            while (bb_from2.next()) |sq_from| {
                var bb_defender_candidates =
                    if (position.colorOnFast(sq_from) == chess.Color.White)
                        position.bb_white
                    else
                        position.bb_black();

                var has_defender = false;
                while (bb_defender_candidates.next()) |candidate| {
                    const candidate_piece = position.getPiece(candidate);
                    const aa_candidate = chess.Attacks.piece_ray(candidate, position.occupied(), candidate_piece);
                    if (aa_candidate.has(sq_from)) {
                        has_defender = true;
                        break;
                    }
                }
                if (has_defender) {
                    continue;
                }

                try history.table.duplicateRow(allocator, off);

                history.table.setLastRow(from_symbol.identity, chess.Bitboard.fromSquare(sq_from));

                const move = chess.Move.none;
                const ref = try history.tree.appendChild(allocator, off, move);
                try history.nodes.append(allocator, ref);
            }
        }
    }

    fn dispatch_forks(allocator: Allocator, history: *History, slice: Matcher.Slice, star: par.SideEffects) !void {
        const from_symbol = history.program.symbols[star.from];
        const fork_a_symbol = history.program.symbols[star.action.one];
        const fork_b_symbol = history.program.symbols[star.action.two];
        const From = history.table.getColumn(from_symbol.identity);
        const ForkA = history.table.getColumn(fork_a_symbol.identity);
        const ForkB = history.table.getColumn(fork_b_symbol.identity);

        for (slice.off..slice.off + slice.len) |off| {
            const bb_from = From[off];
            const bb_forka = ForkA[off];
            const bb_forkb = ForkB[off];

            const position = history.getPosition(off);

            var bb_from2 = bb_from.bitand(Symbols.bitboard(from_symbol, position));
            while (bb_from2.next()) |sq_from| {
                const aa_captures = Symbols.captures(from_symbol, sq_from, position);
                var bb_forka2 = bb_forka
                    .bitand(Symbols.bitboard(fork_a_symbol, position))
                    .bitand(aa_captures);
                while (bb_forka2.next()) |sq_forka| {
                    var bb_forkb2 = bb_forkb
                        .bitand(Symbols.bitboard(fork_b_symbol, position))
                        .bitand(aa_captures);
                    while (bb_forkb2.next()) |sq_forkb| {
                        try history.table.duplicateRow(allocator, off);

                        history.table.setLastRow(from_symbol.identity, chess.Bitboard.fromSquare(sq_from));
                        history.table.setLastRow(fork_a_symbol.identity, chess.Bitboard.fromSquare(sq_forka));
                        history.table.setLastRow(fork_b_symbol.identity, chess.Bitboard.fromSquare(sq_forkb));

                        const move = chess.Move.none;
                        const ref = try history.tree.appendChild(allocator, off, move);
                        try history.nodes.append(allocator, ref);
                    }
                }
            }
        }
    }

    fn dispatch_captures(allocator: Allocator, history: *History, slice: Matcher.Slice, star: par.SideEffects) !void {
        const from_symbol = history.program.symbols[star.from];
        const captured_symbol = history.program.symbols[star.action.one];
        const From = history.table.getColumn(from_symbol.identity);
        const Captured = history.table.getColumn(captured_symbol.identity);

        for (slice.off..slice.off + slice.len) |off| {
            const bb_from = From[off];
            const bb_captured = Captured[off];

            const position = history.getPosition(off);

            var bb_from2 = bb_from.bitand(Symbols.bitboard(from_symbol, position));
            while (bb_from2.next()) |sq_from| {
                const aa_captured = Symbols.captures(from_symbol, sq_from, position);
                var bb_captured2 = bb_captured
                    .bitand(Symbols.bitboard(captured_symbol, position))
                    .bitand(aa_captured);

                while (bb_captured2.next()) |sq_captured| {
                    try history.table.duplicateRow(allocator, off);

                    history.table.setLastRow(from_symbol.identity, chess.Bitboard.fromSquare(sq_from));
                    history.table.setLastRow(captured_symbol.identity, chess.Bitboard.fromSquare(sq_captured));

                    const move = chess.Move.none;
                    const ref = try history.tree.appendChild(allocator, off, move);
                    try history.nodes.append(allocator, ref);
                }
            }
        }
    }

    fn dispatch_checks(allocator: Allocator, history: *History, slice: Matcher.Slice, star: par.SideEffects) !void {
        const from_symbol = history.program.symbols[star.from];
        const checked_symbol = history.program.symbols[star.action.one];
        const From = history.table.getColumn(from_symbol.identity);
        const Checked = history.table.getColumn(checked_symbol.identity);

        for (slice.off..slice.off + slice.len) |off| {
            const bb_from = From[off];
            const bb_checked = Checked[off];

            const position = history.getPosition(off);

            var bb_from2 = bb_from.bitand(Symbols.bitboard(from_symbol, position));

            while (bb_from2.next()) |sq_from| {
                var bb_checked2 = bb_checked
                    .bitand(Symbols.bitboard(checked_symbol, position))
                    .bitand(Symbols.captures(from_symbol, sq_from, position));

                while (bb_checked2.next()) |sq_checked| {
                    try history.table.duplicateRow(allocator, off);

                    history.table.setLastRow(from_symbol.identity, chess.Bitboard.fromSquare(sq_from));
                    history.table.setLastRow(checked_symbol.identity, chess.Bitboard.fromSquare(sq_checked));

                    const move = chess.Move.none;
                    const ref = try history.tree.appendChild(allocator, off, move);
                    try history.nodes.append(allocator, ref);
                }
            }
        }
    }
};

fn log_history(h: History, row: usize) void {
    for (h.table.symbols) |symbol| {
        std.debug.print("{}\n", .{symbol});
        log.bbo(h.table.getColumn(symbol)[row]);
        log.str("\n");
    }
}

fn log_singles(h: History, row: usize) void {
    var symbols = h.table.column_by_symbol.keyIterator();
    while (symbols.next()) |symbol| {
        const bb = h.table.getColumn(symbol.*)[row];
        if (bb.single()) |single| {
            log.sym_id(symbol.*);
            std.debug.print(":{d}:{t} ", .{ h.table.column_by_symbol.get(symbol.*).?, single });
        }
    }
}
