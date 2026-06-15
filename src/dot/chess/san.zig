const std = @import("std");
const types = @import("types.zig");
const Bitboard = types.Bitboard;
const log = @import("logs.zig");

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
    castling: ?types.Castling,
    capture: ?types.Square,
    check: bool,
    checkmate: bool,

    pub fn fromMove(position: types.Position, move: types.Move) San {
        const to: types.Square = @enumFromInt(move.to);

        var pos_after = position;
        _ = pos_after.make_move(move);
        const check = CheckFind.init(pos_after).isCheck();

        return .{
            .piece = position.getPiece(@enumFromInt(move.from)),
            .from = @enumFromInt(move.from),
            .to = to,
            .ambiguity = false,
            .promotion = if (move.kind == types.MoveType.Promotion) move.promotion else null,
            .castling = null,
            .capture = if (position.pieceOn(to) != null) to else null,
            .check = check,
            .checkmate = false,
        };
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

        if (san.check) {
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

    try std.testing.expectEqualStrings("Qxc7 a8=Q Qc3 Qf3", builder.string.items);
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
        _ = position;
        const kind = if (self.promotion != null) types.MoveType.Promotion else types.MoveType.Normal;
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
