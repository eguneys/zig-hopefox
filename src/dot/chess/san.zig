const std = @import("std");
const types = @import("types.zig");
const Bitboard = types.Bitboard;
const Square = types.Square;
const log = @import("logs.zig");

pub const CheckEvasions = struct {
    piece: Square,
    checker: Square,
    escape: Bitboard,
    safe_escape: Bitboard,
    escape_blocks: Bitboard,
    escape_attacks: Bitboard,
    checker_blockers: Bitboard,
    checker_captures: Bitboard,
    piece_captures: bool,

    pub fn init(position: types.Position, sq_piece: Square, sq_checker: Square) ?CheckEvasions {
        const occ = position.occupied();
        const checker = position.getPiece(sq_checker);
        const bb_check = types.Attacks.piece_ray(sq_checker, occ, checker);
        if (!bb_check.has(sq_piece)) {
            return null;
        }

        var result: CheckEvasions = .{
            .piece = sq_piece,
            .checker = sq_checker,
            .escape = Bitboard.Zero,
            .safe_escape = Bitboard.Zero,
            .escape_blocks = Bitboard.Zero,
            .escape_attacks = Bitboard.Zero,
            .checker_blockers = Bitboard.Zero,
            .checker_captures = Bitboard.Zero,
            .piece_captures = false,
        };

        const piece = position.getPiece(sq_piece);

        result.escape = types.Attacks.piece_ray(sq_piece, occ, piece);

        result.escape_blocks = position.bb_color(piece.colorOf()).unset(sq_piece);

        var attackers = position.bb_color(checker.colorOf());

        while (attackers.next()) |attacker| {
            const attacker_ray = types.Attacks
                .piece_eyes(attacker, occ.unset(sq_piece), position.getPiece(attacker));
            result.escape_attacks = result.escape_attacks.bitor(attacker_ray);
        }
        result.escape_attacks = result.escape_attacks.bitand(result.escape);

        result.safe_escape = result.escape
            .bitdiff(result.escape_attacks)
            .bitdiff(result.escape_blocks);

        var capturers = position.bb_color(piece.colorOf()).unset(sq_piece);
        while (capturers.next()) |capturer| {
            const capturer_ray = types.Attacks.piece_ray(capturer, occ, position.getPiece(capturer));
            if (capturer_ray.has(sq_checker)) {
                result.checker_captures = result.checker_captures.set(capturer);
            }
        }

        result.piece_captures = result.safe_escape.has(sq_checker);

        const block_ray = types.Attacks.piece_eyes(sq_checker, occ.unset(sq_piece), checker);
        var blockers = position.bb_color(piece.colorOf()).unset(sq_piece);
        while (blockers.next()) |blocker| {
            const blocker_ray = types.Attacks.piece_ray(blocker, occ, position.getPiece(blocker));
            if (!block_ray.bitand(blocker_ray).isEmpty()) {
                result.checker_blockers = result.checker_blockers.set(blocker);
            }
        }

        return result;
    }

    pub fn isCheckmate(position: types.Position) ?CheckEvasions {
        if (position.bb_king.bitand(position.bb_turn()).single()) |king| {
            var opp = position.bb_opponent();
            while (opp.next()) |opponent| {
                if (CheckEvasions.init(position, king, opponent)) |evasion| {
                    if (evasion.safe_escape.isEmpty() and
                        evasion.checker_blockers.isEmpty() and
                        evasion.checker_captures.isEmpty() and !evasion.piece_captures)
                    {
                        return evasion;
                    }
                }
            }
        }
        return null;
    }
};

pub const CheckFind = struct {
    black_bb: types.Bitboard,
    white_bb: types.Bitboard,
    white_checkers: Bitboard = Bitboard.Zero,
    black_checkers: Bitboard = Bitboard.Zero,

    pub fn init(position: types.Position) CheckFind {
        var result = CheckFind{ .white_bb = position.bb_white, .black_bb = position.bb_black() };

        const occ = position.occupied();

        if (position.bb_white_king().single()) |white_king| {
            var white_candies =
                types.Attacks.ray_plus(white_king, occ, types.DirectionPlus.All);

            while (white_candies.next()) |candidate| {
                const check = types.Attacks.piece_ray(candidate, occ, position.getPiece(candidate));
                if (check.has(white_king)) {
                    result.white_checkers = result.white_checkers.set(candidate);
                }
            }
        }

        if (position.bb_black_king().single()) |black_king| {
            var black_candies =
                types.Attacks.ray_plus(black_king, occ, types.DirectionPlus.All);

            while (black_candies.next()) |candidate| {
                const check = types.Attacks.piece_ray(candidate, occ, position.getPiece(candidate));
                if (check.has(black_king)) {
                    result.black_checkers = result.black_checkers.set(candidate);
                }
            }
        }

        return result;
    }

    pub fn isCheck(self: CheckFind) bool {
        return !self.black_checkers.bitand(self.white_bb).isEmpty() or !self.white_checkers.bitand(self.black_bb).isEmpty();
    }
};

pub const San = struct {
    from: types.Square,
    to: types.Square,
    ambiguity: bool,
    piece: types.Piece,
    promotion: ?types.MovePromotionRole,
    castling: ?types.CastlingRights,
    capture: ?types.Square,
    check: bool,
    checkmate: bool,

    pub fn fromMove(position: types.Position, move: types.Move) San {
        const to: types.Square = @enumFromInt(move.to);

        var pos_after = position;
        _ = pos_after.make_move(move);
        pos_after.flipTurn();
        const check = CheckFind.init(pos_after).isCheck();
        const isCheckmate = CheckEvasions.isCheckmate(pos_after) != null;

        return .{
            .piece = position.getPiece(@enumFromInt(move.from)),
            .from = @enumFromInt(move.from),
            .to = to,
            .ambiguity = false,
            .promotion = if (move.kind == types.MoveType.Promotion) move.promotion else null,
            .castling = if (move.kind == types.MoveType.Castling)
                CastlingFind.fromMove(position, move)
            else
                null,
            .capture = if (position.pieceOn(to) != null) to else null,
            .check = check,
            .checkmate = isCheckmate,
        };
    }
};

pub const CastlingFind = struct {
    pub fn fromMove(position: types.Position, move: types.Move) ?types.CastlingRights {
        if (move.kind == types.MoveType.Castling) {
            return CastlingFind.fromPosition(position, @enumFromInt(move.from), @enumFromInt(move.to));
        }
        return null;
    }

    pub fn fromPosition(position: types.Position, from: types.Square, to: types.Square) ?types.CastlingRights {
        if (from.king_distance(to) == 2) {
            if (position.bb_king.has(from)) {
                return if (@intFromEnum(from.toFile()) < @intFromEnum(to.toFile()))
                    if (position.bb_white.has(from))
                        types.CastlingRights.whiteCastles(types.CastlingSide.King)
                    else
                        types.CastlingRights.blackCastles(types.CastlingSide.King)
                else if (position.bb_white.has(from))
                    types.CastlingRights.whiteCastles(types.CastlingSide.Queen)
                else
                    types.CastlingRights.blackCastles(types.CastlingSide.Queen);
            }
        }
        return null;
    }
};

pub const Prints = struct {
    single: []u8,
    list: []u8,

    pub fn deinit(self: *Prints, allocator: std.mem.Allocator) void {
        allocator.free(self.single);
        allocator.free(self.list);
    }

    pub fn init(allocator: std.mem.Allocator, capacity: usize) !Prints {
        var single = try std.ArrayList(u8).initCapacity(allocator, 8);
        errdefer single.deinit(allocator);
        var list = try std.ArrayList(u8).initCapacity(allocator, capacity);
        errdefer list.deinit(allocator);

        for (0..single.capacity) |_| try single.append(allocator, undefined);
        for (0..list.capacity) |_| try list.append(allocator, undefined);

        return .{ .single = try single.toOwnedSlice(allocator), .list = try list.toOwnedSlice(allocator) };
    }

    pub fn fromSan(self: Prints, san: San) []const u8 {
        if (san.castling) |castling| {
            return if (castling.white_queenside or castling.black_queenside) "O-O-O" else "O-O";
        }

        var i: usize = 0;
        if (san.piece.roleOf() != types.Role.Pawn) {
            self.single[i] = types.Prints.role(san.piece.roleOf());
            i += 1;
        }

        //try res.appendSlice(allocator, &types.Prints.fromSquare(san.from));
        if (san.capture != null) {
            if (san.piece.roleOf() == types.Role.Pawn) {
                self.single[i] = types.Prints.file(san.from.toFile());
                i += 1;
            }
            self.single[i] = 'x';
            i += 1;
        }
        std.mem.copyForwards(u8, self.single[i..], &types.Prints.fromSquare(san.to));
        i += 2;

        if (san.promotion) |promotion| {
            self.single[i] = '=';
            i += 1;
            self.single[i] = types.Prints.fromPromotionRole(promotion);
            i += 1;
        }

        if (san.checkmate) {
            self.single[i] = '#';
            i += 1;
        } else if (san.check) {
            self.single[i] = '+';
            i += 1;
        }

        return self.single[0..i];
    }
};

pub const PrintBuilder = struct {
    position: types.Position,
    string: std.ArrayList(u8),
    prints: Prints,

    pub fn deinit(self: *PrintBuilder, allocator: std.mem.Allocator) void {
        self.string.deinit(allocator);
        self.prints.deinit(allocator);
    }

    pub fn init(allocator: std.mem.Allocator) !PrintBuilder {
        return .{
            .prints = try Prints.init(allocator, 0),
            .position = undefined,
            .string = try std.ArrayList(u8).initCapacity(allocator, 0),
        };
    }

    pub fn clearRetainingPosition(self: *PrintBuilder) void {
        self.string.clearRetainingCapacity();
    }

    pub fn resetPosition(self: *PrintBuilder, position: types.Position) void {
        self.position = position;
        self.string.clearRetainingCapacity();
    }

    pub fn appendMove(self: *PrintBuilder, allocator: std.mem.Allocator, move: types.Move) !void {
        if (move.isNone()) {
            return;
        }
        if (self.string.items.len > 0) {
            try self.string.append(allocator, ' ');
        }
        try self.string.appendSlice(allocator, self.prints.fromSan(San.fromMove(self.position, move)));
        _ = self.position.make_move(move);
    }
};

test "print builder" {
    const ally = std.testing.allocator;

    var builder = try PrintBuilder.init(ally);
    defer builder.deinit(ally);

    builder.resetPosition(types.Fen.parse(types.Fen.Initial));

    try builder.appendMove(ally, Uci.move("e2e4").toMove(builder.position));
    try builder.appendMove(ally, Uci.move("e7e6").toMove(builder.position));
    try builder.appendMove(ally, Uci.move("g1f3").toMove(builder.position));
    try builder.appendMove(ally, Uci.move("b8c6").toMove(builder.position));
    try builder.appendMove(ally, Uci.move("f1c4").toMove(builder.position));
    try builder.appendMove(ally, Uci.move("e4e5").toMove(builder.position));

    try std.testing.expectEqualStrings("e4 e6 Nf3 Nc6 Bc4 e5", builder.string.items);
}

test "promotion" {
    const ally = std.testing.allocator;

    var builder = try PrintBuilder.init(ally);
    defer builder.deinit(ally);

    builder.resetPosition(types.Fen.parse("8/P1R4p/5pk1/4q1p1/5P2/6KP/5QP1/7r b - - 0 51"));

    try builder.appendMove(ally, Uci.move("e5c7").toMove(builder.position));
    try builder.appendMove(ally, Uci.move("a7a8q").toMove(builder.position));
    try builder.appendMove(ally, Uci.move("c7c3").toMove(builder.position));
    try builder.appendMove(ally, Uci.move("a8f3").toMove(builder.position));

    try std.testing.expectEqualStrings("Qxc7 a8=Q Qc3+ Qf3", builder.string.items);
}

test "castling" {
    const ally = std.testing.allocator;

    var builder = try PrintBuilder.init(ally);
    defer builder.deinit(ally);

    builder.resetPosition(types.Fen.parse("r3k2r/p1ppqp1p/4p1p1/3BQ3/8/2P5/2P2PPP/4R1K1 b kq - 0 24"));

    //e8c8 e1b1 d8e8 d5b7 c8d8 b7a
    try builder.appendMove(ally, Uci.move("e8c8").toMove(builder.position));
    try builder.appendMove(ally, Uci.move("e1b1").toMove(builder.position));
    try builder.appendMove(ally, Uci.move("d8e8").toMove(builder.position));
    try builder.appendMove(ally, Uci.move("d5b7").toMove(builder.position));

    try std.testing.expectEqualStrings("O-O-O Rb1 Re8 Bb7+", builder.string.items);
}

test "more castling A0QQJ" {
    const ally = std.testing.allocator;

    var builder = try PrintBuilder.init(ally);
    defer builder.deinit(ally);

    builder.resetPosition(types.Fen.parse("8/pp6/5k2/4b2n/1P4P1/5PK1/P7/4R3 w - - 0 43"));

    //g3h4 e5g3 h4h5 g3e1
    try builder.appendMove(ally, Uci.move("g3h4").toMove(builder.position));
    try builder.appendMove(ally, Uci.move("e5g3").toMove(builder.position));
    try builder.appendMove(ally, Uci.move("h4h5").toMove(builder.position));
    try builder.appendMove(ally, Uci.move("g3e1").toMove(builder.position));

    try std.testing.expectEqualStrings("Kh4 Bg3+ Kxh5 Bxe1", builder.string.items);
}

pub const Uci = struct {
    from: types.Square,
    to: types.Square,
    promotion: ?types.MovePromotionRole,

    pub fn role(char: u8) types.MovePromotionRole {
        return switch (char) {
            'b' => types.MovePromotionRole.Bishop,
            'n' => types.MovePromotionRole.Knight,
            'r' => types.MovePromotionRole.Rook,
            'q' => types.MovePromotionRole.Queen,
            else => unreachable,
        };
    }

    pub fn file(char: u8) types.File {
        return switch (char) {
            'a' => types.File.A,
            'b' => types.File.B,
            'c' => types.File.C,
            'd' => types.File.D,
            'e' => types.File.E,
            'f' => types.File.F,
            'g' => types.File.G,
            'h' => types.File.H,
            else => unreachable,
        };
    }

    pub fn rank(char: u8) types.Rank {
        return switch (char) {
            '1' => types.Rank.R1,
            '2' => types.Rank.R2,
            '3' => types.Rank.R3,
            '4' => types.Rank.R4,
            '5' => types.Rank.R5,
            '6' => types.Rank.R6,
            '7' => types.Rank.R7,
            '8' => types.Rank.R8,
            else => unreachable,
        };
    }

    pub fn square(string: []const u8) types.Square {
        return types.Square.fromCoord(Uci.file(string[0]), Uci.rank(string[1]));
    }

    pub fn move(uci: []const u8) Uci {
        const from = Uci.square(uci);
        const to = Uci.square(uci[2..4]);
        const promotion = if (uci.len == 5) Uci.role(uci[4]) else null;
        return .{ .from = from, .to = to, .promotion = promotion };
    }

    pub fn toMove(self: Uci, position: types.Position) types.Move {
        const kind =
            if (self.promotion != null)
                types.MoveType.Promotion
            else if (CastlingFind.fromPosition(position, self.from, self.to) != null)
                types.MoveType.Castling
            else
                types.MoveType.Normal;
        const promotion = self.promotion orelse types.MovePromotionRole.Queen;

        return .{ .from = @intCast(@intFromEnum(self.from)), .to = @intCast(@intFromEnum(self.to)), .kind = kind, .promotion = promotion };
    }
};

test "pawn moves" {
    const ally = std.testing.allocator;

    var prints = try Prints.init(ally, 80);
    defer prints.deinit(ally);

    const position = types.Fen.parse(types.Fen.Initial);
    const sans = prints.fromSan(San.fromMove(position, Uci.move("e2e4").toMove(position)));

    try std.testing.expectEqualStrings("e4", sans);

    try testSan("e4", "e3e4",
        \\........
        \\........
        \\........
        \\........
        \\........
        \\....p...
        \\........
        \\........
    );

    try testSan("cxd4", "c3d4",
        \\........
        \\........
        \\........
        \\........
        \\...P....
        \\..p.....
        \\........
        \\........
    );

    try testSan("e8=Q", "e7e8q",
        \\........
        \\....p...
        \\........
        \\........
        \\........
        \\........
        \\........
        \\........
    );
}

fn testSan(expected: []const u8, uci: []const u8, str_position: *const [71:0]u8) !void {
    const ally = std.testing.allocator;
    var prints = try Prints.init(ally, 80);
    defer prints.deinit(ally);

    const position = types.Parses.white(str_position);
    const sans = prints.fromSan(San.fromMove(position, Uci.move(uci).toMove(position)));

    try std.testing.expectEqualStrings(expected, sans);
}

test "king moves" {
    try testSan("Kf4", "e3f4",
        \\........
        \\....p...
        \\........
        \\........
        \\........
        \\....k...
        \\........
        \\........
    );

    try testSan("Qxe7", "e3e7",
        \\........
        \\....p...
        \\........
        \\........
        \\........
        \\....q...
        \\........
        \\........
    );
}

test "checkmate" {
    try testSan("Rd8#", "d4d8",
        \\......k.
        \\.....ppp
        \\........
        \\........
        \\...R....
        \\........
        \\........
        \\........
    );
    try testSan("Bb7#", "a6b7",
        \\k.......
        \\p.......
        \\B..Q....
        \\N.......
        \\........
        \\........
        \\........
        \\........
    );
}
