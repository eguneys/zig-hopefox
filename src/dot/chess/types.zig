const std = @import("std");

pub const File = enum(u8) {
    A,
    B,
    C,
    D,
    E,
    F,
    G,
    H,

    pub fn distance(self: File, other: File) usize {
        const a = @intFromEnum(self);
        const b = @intFromEnum(other);
        return if (a > b) a - b else b - a;
    }
};
pub const Rank = enum(u8) {
    R1,
    R2,
    R3,
    R4,
    R5,
    R6,
    R7,
    R8,

    pub fn distance(self: Rank, other: Rank) usize {
        const a = @intFromEnum(self);
        const b = @intFromEnum(other);
        return if (a > b) a - b else b - a;
    }
};

pub const Files = [8]File{ File.A, File.B, File.C, File.D, File.E, File.F, File.G, File.H };
pub const Ranks = [8]Rank{ Rank.R1, Rank.R2, Rank.R3, Rank.R4, Rank.R5, Rank.R6, Rank.R7, Rank.R8 };

pub const Square = enum(u8) {
    A1,
    B1,
    C1,
    D1,
    E1,
    F1,
    G1,
    H1,
    A2,
    B2,
    C2,
    D2,
    E2,
    F2,
    G2,
    H2,
    A3,
    B3,
    C3,
    D3,
    E3,
    F3,
    G3,
    H3,
    A4,
    B4,
    C4,
    D4,
    E4,
    F4,
    G4,
    H4,
    A5,
    B5,
    C5,
    D5,
    E5,
    F5,
    G5,
    H5,
    A6,
    B6,
    C6,
    D6,
    E6,
    F6,
    G6,
    H6,
    A7,
    B7,
    C7,
    D7,
    E7,
    F7,
    G7,
    H7,
    A8,
    B8,
    C8,
    D8,
    E8,
    F8,
    G8,
    H8,

    pub fn toFile(self: Square) File {
        return @enumFromInt(@intFromEnum(self) % 8);
    }

    pub fn toRank(self: Square) Rank {
        return @enumFromInt(@intFromEnum(self) / 8);
    }

    pub fn fromCoord(file: File, rank: Rank) Square {
        return @enumFromInt(@intFromEnum(file) + @intFromEnum(rank) * 8);
    }

    pub fn king_distance(self: Square, other: Square) usize {
        const dx: usize = self.toFile().distance(other.toFile());
        const dy: usize = self.toRank().distance(other.toRank());
        return @max(dx, dy);
    }
};

test "square king distance" {
    try std.testing.expectEqual(7, Square.A1.king_distance(Square.H8));
    try std.testing.expectEqual(5, Square.H8.king_distance(Square.C8));
}

pub const Squares = [64]Square{ Square.A1, Square.B1, Square.C1, Square.D1, Square.E1, Square.F1, Square.G1, Square.H1, Square.A2, Square.B2, Square.C2, Square.D2, Square.E2, Square.F2, Square.G2, Square.H2, Square.A3, Square.B3, Square.C3, Square.D3, Square.E3, Square.F3, Square.G3, Square.H3, Square.A4, Square.B4, Square.C4, Square.D4, Square.E4, Square.F4, Square.G4, Square.H4, Square.A5, Square.B5, Square.C5, Square.D5, Square.E5, Square.F5, Square.G5, Square.H5, Square.A6, Square.B6, Square.C6, Square.D6, Square.E6, Square.F6, Square.G6, Square.H6, Square.A7, Square.B7, Square.C7, Square.D7, Square.E7, Square.F7, Square.G7, Square.H7, Square.A8, Square.B8, Square.C8, Square.D8, Square.E8, Square.F8, Square.G8, Square.H8 };

pub const Color = enum(u1) {
    White,
    Black,
    pub fn opposite(self: Color) Color {
        return if (self == Color.White) Color.Black else Color.White;
    }
};
pub const Role = enum(u8) { King, Queen, Rook, Bishop, Knight, Pawn };

pub const Piece = enum(u8) {
    White_King,
    White_Queen,
    White_Rook,
    White_Bishop,
    White_Knight,
    White_Pawn,
    Black_King,
    Black_Queen,
    Black_Rook,
    Black_Bishop,
    Black_Knight,
    Black_Pawn,

    pub fn colorOf(self: Piece) Color {
        return @enumFromInt(@intFromEnum(self) / 6);
    }
    pub fn roleOf(self: Piece) Role {
        return @enumFromInt(@intFromEnum(self) % 6);
    }

    pub fn fromColors(color: Color, role: Role) Piece {
        return @enumFromInt(@as(u8, @intFromEnum(color)) * 6 + @intFromEnum(role));
    }

    pub fn promote(self: Piece, role: MovePromotionRole) Piece {
        return Piece.fromColors(self.colorOf(), @enumFromInt(@intFromEnum(role) + 1));
    }
};

test "piece" {
    try std.testing.expectEqual(@as(File, @enumFromInt(0)), File.A);
    try std.testing.expectEqual(@as(Rank, @enumFromInt(7)), Rank.R8);

    try std.testing.expect(Piece.White_Pawn.colorOf() == Color.White);
    try std.testing.expect(Piece.White_Bishop.colorOf() == Color.White);
    try std.testing.expect(Piece.White_King.colorOf() == Color.White);

    try std.testing.expect(Piece.Black_Pawn.colorOf() == Color.Black);
    try std.testing.expect(Piece.Black_Bishop.colorOf() == Color.Black);
    try std.testing.expect(Piece.Black_King.colorOf() == Color.Black);

    try std.testing.expect(Piece.Black_Pawn.roleOf() == Role.Pawn);
    try std.testing.expect(Piece.Black_Bishop.roleOf() == Role.Bishop);
    try std.testing.expect(Piece.Black_King.roleOf() == Role.King);
}

pub const Bitboard = packed struct(u64) {
    bits: u64,

    pub const All = Bitboard{ .bits = 0xffff_ffff_ffff_ffff };
    pub const Zero = Bitboard{ .bits = 0 };
    pub const A1 = Bitboard.fromSquare(Square.A1);
    pub const A2 = Bitboard.fromSquare(Square.A2);
    pub const A3 = Bitboard.fromSquare(Square.A3);
    pub const A4 = Bitboard.fromSquare(Square.A4);
    pub const A5 = Bitboard.fromSquare(Square.A5);
    pub const A6 = Bitboard.fromSquare(Square.A6);
    pub const A7 = Bitboard.fromSquare(Square.A7);
    pub const A8 = Bitboard.fromSquare(Square.A8);
    pub const B1 = Bitboard.fromSquare(Square.B1);
    pub const B2 = Bitboard.fromSquare(Square.B2);
    pub const B3 = Bitboard.fromSquare(Square.B3);
    pub const B4 = Bitboard.fromSquare(Square.B4);
    pub const B5 = Bitboard.fromSquare(Square.B5);
    pub const B6 = Bitboard.fromSquare(Square.B6);
    pub const B7 = Bitboard.fromSquare(Square.B7);
    pub const B8 = Bitboard.fromSquare(Square.B8);
    pub const C1 = Bitboard.fromSquare(Square.C1);
    pub const C2 = Bitboard.fromSquare(Square.C2);
    pub const C3 = Bitboard.fromSquare(Square.C3);
    pub const C4 = Bitboard.fromSquare(Square.C4);
    pub const C5 = Bitboard.fromSquare(Square.C5);
    pub const C6 = Bitboard.fromSquare(Square.C6);
    pub const C7 = Bitboard.fromSquare(Square.C7);
    pub const C8 = Bitboard.fromSquare(Square.C8);
    pub const D1 = Bitboard.fromSquare(Square.D1);
    pub const D2 = Bitboard.fromSquare(Square.D2);
    pub const D3 = Bitboard.fromSquare(Square.D3);
    pub const D4 = Bitboard.fromSquare(Square.D4);
    pub const D5 = Bitboard.fromSquare(Square.D5);
    pub const D6 = Bitboard.fromSquare(Square.D6);
    pub const D7 = Bitboard.fromSquare(Square.D7);
    pub const D8 = Bitboard.fromSquare(Square.D8);
    pub const E1 = Bitboard.fromSquare(Square.E1);
    pub const E2 = Bitboard.fromSquare(Square.E2);
    pub const E3 = Bitboard.fromSquare(Square.E3);
    pub const E4 = Bitboard.fromSquare(Square.E4);
    pub const E5 = Bitboard.fromSquare(Square.E5);
    pub const E6 = Bitboard.fromSquare(Square.E6);
    pub const E7 = Bitboard.fromSquare(Square.E7);
    pub const E8 = Bitboard.fromSquare(Square.E8);
    pub const F1 = Bitboard.fromSquare(Square.F1);
    pub const F2 = Bitboard.fromSquare(Square.F2);
    pub const F3 = Bitboard.fromSquare(Square.F3);
    pub const F4 = Bitboard.fromSquare(Square.F4);
    pub const F5 = Bitboard.fromSquare(Square.F5);
    pub const F6 = Bitboard.fromSquare(Square.F6);
    pub const F7 = Bitboard.fromSquare(Square.F7);
    pub const F8 = Bitboard.fromSquare(Square.F8);
    pub const G1 = Bitboard.fromSquare(Square.G1);
    pub const G2 = Bitboard.fromSquare(Square.G2);
    pub const G3 = Bitboard.fromSquare(Square.G3);
    pub const G4 = Bitboard.fromSquare(Square.G4);
    pub const G5 = Bitboard.fromSquare(Square.G5);
    pub const G6 = Bitboard.fromSquare(Square.G6);
    pub const G7 = Bitboard.fromSquare(Square.G7);
    pub const G8 = Bitboard.fromSquare(Square.G8);
    pub const H1 = Bitboard.fromSquare(Square.H1);
    pub const H2 = Bitboard.fromSquare(Square.H2);
    pub const H3 = Bitboard.fromSquare(Square.H3);
    pub const H4 = Bitboard.fromSquare(Square.H4);
    pub const H5 = Bitboard.fromSquare(Square.H5);
    pub const H6 = Bitboard.fromSquare(Square.H6);
    pub const H7 = Bitboard.fromSquare(Square.H7);
    pub const H8 = Bitboard.fromSquare(Square.H8);

    pub fn fromInt(bits: u64) Bitboard {
        return .{ .bits = bits };
    }

    pub fn fromSquare(sq: Square) Bitboard {
        return Bitboard{ .bits = @as(u64, 1) << @intCast(@intFromEnum(sq)) };
    }

    pub fn eq(self: Bitboard, other: Bitboard) bool {
        return self.bits == other.bits;
    }

    pub fn single(self: Bitboard) ?Square {
        return if ((self.bits & (self.bits -% 1) == 0) and self.isNotEmpty())
            @enumFromInt(@ctz(self.bits))
        else
            null;
    }

    pub fn first(self: Bitboard) ?Square {
        return if (self.isNotEmpty())
            @enumFromInt(@ctz(self.bits))
        else
            null;
    }

    pub fn has(self: Bitboard, square: Square) bool {
        return self.bitand(Bitboard.fromSquare(square)).isNotEmpty();
    }

    pub fn isEmpty(self: Bitboard) bool {
        return self.bits == 0;
    }

    pub fn isNotEmpty(self: Bitboard) bool {
        return self.bits != 0;
    }

    pub fn invert(self: Bitboard) Bitboard {
        return Bitboard{ .bits = ~self.bits };
    }

    pub fn unset(self: Bitboard, square: Square) Bitboard {
        return self.bitand(Bitboard.fromSquare(square).invert());
    }

    pub fn set(self: Bitboard, square: Square) Bitboard {
        return self.bitor(Bitboard.fromSquare(square));
    }

    pub fn bitand(self: Bitboard, other: Bitboard) Bitboard {
        return Bitboard{ .bits = self.bits & other.bits };
    }

    pub fn bitor(self: Bitboard, other: Bitboard) Bitboard {
        return Bitboard{ .bits = self.bits | other.bits };
    }

    pub fn bitdiff(self: Bitboard, other: Bitboard) Bitboard {
        return Bitboard{ .bits = self.bits & ~other.bits };
    }

    pub fn complement(self: Bitboard) Bitboard {
        return Bitboard{ .bits = ~self.bits };
    }

    pub fn next(self: *Bitboard) ?Square {
        if (self.first()) |sq| {
            self.bits &= (self.bits -% 1);
            return sq;
        } else return null;
    }
};

test "square" {
    try std.testing.expect(Square.A1.toFile() == File.A);
    try std.testing.expect(Square.B1.toFile() == File.B);
    try std.testing.expect(Square.C1.toFile() == File.C);
    try std.testing.expect(Square.D1.toFile() == File.D);
    try std.testing.expect(Square.E1.toFile() == File.E);
    try std.testing.expect(Square.F1.toFile() == File.F);
    try std.testing.expect(Square.G1.toFile() == File.G);
    try std.testing.expect(Square.H1.toFile() == File.H);

    try std.testing.expect(Square.A1.toRank() == Rank.R1);
    try std.testing.expect(Square.B1.toRank() == Rank.R1);
    try std.testing.expect(Square.C1.toRank() == Rank.R1);
    try std.testing.expect(Square.D1.toRank() == Rank.R1);
    try std.testing.expect(Square.E1.toRank() == Rank.R1);
    try std.testing.expect(Square.F1.toRank() == Rank.R1);
    try std.testing.expect(Square.G1.toRank() == Rank.R1);
    try std.testing.expect(Square.H1.toRank() == Rank.R1);

    try std.testing.expect(Square.A2.toRank() == Rank.R2);
    try std.testing.expect(Square.A3.toRank() == Rank.R3);
    try std.testing.expect(Square.A4.toRank() == Rank.R4);
    try std.testing.expect(Square.A5.toRank() == Rank.R5);
    try std.testing.expect(Square.A6.toRank() == Rank.R6);
    try std.testing.expect(Square.A7.toRank() == Rank.R7);
    try std.testing.expect(Square.A8.toRank() == Rank.R8);

    try std.testing.expect(Bitboard.Zero.single() == null);
    try std.testing.expect(Bitboard.fromSquare(Square.A1).single() == Square.A1);

    try std.testing.expect(Bitboard.fromSquare(Square.A1).single() == Square.A1);
    try std.testing.expect(Bitboard.fromSquare(Square.H8).single() == Square.H8);

    for (Squares) |square|
        try std.testing.expect(Bitboard.fromSquare(square).single() == square);

    try std.testing.expectEqual(Square.A1, Square.fromCoord(File.A, Rank.R1));
    try std.testing.expectEqual(Square.H8, Square.fromCoord(File.H, Rank.R8));
}

pub const Direction = enum { Up, Down, Left, Right, Up_Left, Up_Right, Down_Left, Down_Right };

pub const DirectionPlus = enum { Forward, Backward, KingSide, QueenSide, Diagonal, Horizontal, Vertical, All, Straight };

pub const Attacks = struct {
    const ray_masks = generate_ray_masks();

    fn generate_ray_masks() [8][64]Bitboard {
        var res: [8][64]Bitboard = undefined;

        const df = [8]i8{ 0, 0, -1, 1, -1, 1, -1, 1 };
        const dr = [8]i8{ 1, -1, 0, 0, 1, 1, -1, -1 };

        for (Squares) |square| {
            const start_file = @intFromEnum(square.toFile());
            const start_rank = @intFromEnum(square.toRank());

            for (0..8) |dir| {
                var mask = Bitboard.Zero;
                var f = @as(i8, start_file) + df[dir];
                var r = @as(i8, start_rank) + dr[dir];

                while (f >= 0 and f < 8 and r >= 0 and r < 8) {
                    @setEvalBranchQuota(50000);
                    const target_square = Square.fromCoord(@enumFromInt(f), @enumFromInt(r));
                    mask = mask.bitor(Bitboard.fromSquare(target_square));

                    f += df[dir];
                    r += dr[dir];
                }

                res[dir][@intFromEnum(square)] = mask;
            }
        }
        return res;
    }

    const king_masks = generate_king_masks();

    fn generate_king_masks() [8][64]Bitboard {
        var res: [8][64]Bitboard = undefined;

        const df = [8]i8{ 0, 0, -1, 1, -1, 1, -1, 1 };
        const dr = [8]i8{ 1, -1, 0, 0, 1, 1, -1, -1 };

        for (Squares) |square| {
            const start_file = @intFromEnum(square.toFile());
            const start_rank = @intFromEnum(square.toRank());

            for (0..8) |dir| {
                var mask = Bitboard.Zero;
                const f = @as(i8, start_file) + df[dir];
                const r = @as(i8, start_rank) + dr[dir];

                if (f >= 0 and f < 8 and r >= 0 and r < 8) {
                    @setEvalBranchQuota(10000);
                    const target_square = Square.fromCoord(@enumFromInt(f), @enumFromInt(r));
                    mask = mask.bitor(Bitboard.fromSquare(target_square));
                }

                res[dir][@intFromEnum(square)] = mask;
            }
        }
        return res;
    }

    pub fn directionOf(from: Square, to: Square) Direction {
        if (from.toFile() == to.toFile()) {
            return if (@intFromEnum(from.toRank()) < @intFromEnum(to.toRank())) Direction.Up else Direction.Down;
        } else if (from.toRank() == to.toRank()) {
            return if (@intFromEnum(from.toFile()) < @intFromEnum(to.toFile())) Direction.Right else Direction.Left;
        } else if (@intFromEnum(from.toFile()) < @intFromEnum(to.toFile())) {
            return if (@intFromEnum(from.toRank()) < @intFromEnum(to.toRank())) Direction.Up_Right else Direction.Down_Right;
        } else {
            return if (@intFromEnum(from.toRank()) < @intFromEnum(to.toRank())) Direction.Up_Left else Direction.Down_Left;
        }
    }

    pub fn from_to(from: Square, to: Square) Bitboard {
        return eye(from, Bitboard.fromSquare(to), directionOf(from, to));
    }

    pub fn rayall(square: Square, occupied: Bitboard, direction: Direction) Bitboard {
        return ray_masks[@intFromEnum(direction)][@intFromEnum(square)].bitand(occupied);
    }

    fn positive_eye(occ: u64, ray_mask: u64, slider_bit: u64) u64 {
        const o = occ & ray_mask;
        return ((o -% (2 *% slider_bit)) ^ occ) & ray_mask;
    }

    // world
    fn negative_eye(occ: u64, ray_mask: u64, slider_bit: u64) u64 {
        const o: u64 = @bitReverse(occ & ray_mask);
        const r: u64 = @bitReverse(slider_bit);
        return @bitReverse((o -% (2 *% r)) ^ o) & ray_mask;
    }

    pub fn eye(square: Square, occupied: Bitboard, direction: Direction) Bitboard {
        const ray_mask = ray_masks[@intFromEnum(direction)][@intFromEnum(square)];
        const slider_bit = Bitboard.fromSquare(square);

        return switch (direction) {
            Direction.Right, Direction.Up, Direction.Up_Left, Direction.Up_Right => Bitboard.fromInt(positive_eye(occupied.bits, ray_mask.bits, slider_bit.bits)),

            else => Bitboard.fromInt(negative_eye(occupied.bits, ray_mask.bits, slider_bit.bits)),
        };
    }

    pub fn ray(square: Square, occupied: Bitboard, direction: Direction) Bitboard {
        return eye(square, occupied, direction).bitand(occupied);
    }

    pub fn eyes_plus(square: Square, occupied: Bitboard, plus: DirectionPlus) Bitboard {
        return switch (plus) {
            DirectionPlus.Forward => Attacks.eye(square, occupied, Direction.Up)
                .bitor(Attacks.eye(square, occupied, Direction.Up_Right))
                .bitor(Attacks.eye(square, occupied, Direction.Up_Left)),
            DirectionPlus.Backward => Attacks.eye(square, occupied, Direction.Down)
                .bitor(Attacks.eye(square, occupied, Direction.Down_Right))
                .bitor(Attacks.eye(square, occupied, Direction.Down_Left)),
            DirectionPlus.KingSide => Attacks.eye(square, occupied, Direction.Right)
                .bitor(Attacks.eye(square, occupied, Direction.Up_Right))
                .bitor(Attacks.eye(square, occupied, Direction.Down_Right)),
            DirectionPlus.QueenSide => Attacks.eye(square, occupied, Direction.Left)
                .bitor(Attacks.eye(square, occupied, Direction.Up_Left))
                .bitor(Attacks.eye(square, occupied, Direction.Down_Left)),
            DirectionPlus.Diagonal => Attacks.eye(square, occupied, Direction.Up_Left)
                .bitor(Attacks.eye(square, occupied, Direction.Up_Right))
                .bitor(Attacks.eye(square, occupied, Direction.Down_Left))
                .bitor(Attacks.eye(square, occupied, Direction.Down_Right)),
            DirectionPlus.Straight => Attacks.eye(square, occupied, Direction.Up)
                .bitor(Attacks.eye(square, occupied, Direction.Right))
                .bitor(Attacks.eye(square, occupied, Direction.Left))
                .bitor(Attacks.eye(square, occupied, Direction.Down)),
            else => Bitboard.Zero,
        };
    }

    pub fn ray_plus(square: Square, occupied: Bitboard, plus: DirectionPlus) Bitboard {
        return switch (plus) {
            DirectionPlus.Forward => Attacks.ray(square, occupied, Direction.Up)
                .bitor(Attacks.ray(square, occupied, Direction.Up_Right))
                .bitor(Attacks.ray(square, occupied, Direction.Up_Left)),
            DirectionPlus.Backward => Attacks.ray(square, occupied, Direction.Down)
                .bitor(Attacks.ray(square, occupied, Direction.Down_Right))
                .bitor(Attacks.ray(square, occupied, Direction.Down_Left)),
            DirectionPlus.KingSide => Attacks.ray(square, occupied, Direction.Right)
                .bitor(Attacks.ray(square, occupied, Direction.Up_Right))
                .bitor(Attacks.ray(square, occupied, Direction.Down_Right)),
            DirectionPlus.QueenSide => Attacks.ray(square, occupied, Direction.Left)
                .bitor(Attacks.ray(square, occupied, Direction.Up_Left))
                .bitor(Attacks.ray(square, occupied, Direction.Down_Left)),
            DirectionPlus.Diagonal => Attacks.ray(square, occupied, Direction.Up_Left)
                .bitor(Attacks.ray(square, occupied, Direction.Up_Right))
                .bitor(Attacks.ray(square, occupied, Direction.Down_Left))
                .bitor(Attacks.ray(square, occupied, Direction.Down_Right)),
            DirectionPlus.Straight => Attacks.ray(square, occupied, Direction.Up)
                .bitor(Attacks.ray(square, occupied, Direction.Right))
                .bitor(Attacks.ray(square, occupied, Direction.Left))
                .bitor(Attacks.ray(square, occupied, Direction.Down)),
            DirectionPlus.All => Attacks.ray_plus(square, occupied, DirectionPlus.Diagonal)
                .bitor(Attacks.ray_plus(square, occupied, DirectionPlus.Straight)),
            else => Bitboard.Zero,
        };
    }

    pub fn pawn(square: Square, direction: Direction) Bitboard {
        return king(square, direction);
    }

    pub fn pawn_plus(square: Square, plus: DirectionPlus) Bitboard {
        return switch (plus) {
            DirectionPlus.Forward => Attacks.pawn(square, Direction.Up_Left)
                .bitor(Attacks.pawn(square, Direction.Up_Right)),
            DirectionPlus.Backward => Attacks.pawn(square, Direction.Down_Left)
                .bitor(Attacks.pawn(square, Direction.Down_Right)),
            DirectionPlus.KingSide => Attacks.pawn(square, Direction.Up_Right)
                .bitor(Attacks.pawn(square, Direction.Down_Right)),
            DirectionPlus.QueenSide => Attacks.pawn(square, Direction.Up_Left)
                .bitor(Attacks.pawn(square, Direction.Down_Left)),
            DirectionPlus.Diagonal => Attacks.pawn(square, Direction.Up_Left)
                .bitor(Attacks.pawn(square, Direction.Down_Left))
                .bitor(Attacks.pawn(square, Direction.Up_Right))
                .bitor(Attacks.pawn(square, Direction.Down_Right)),
            else => Bitboard.Zero,
        };
    }

    pub fn king(square: Square, direction: Direction) Bitboard {
        return king_masks[@intFromEnum(direction)][@intFromEnum(square)];
    }

    pub fn king_plus(square: Square, plus: DirectionPlus) Bitboard {
        return switch (plus) {
            DirectionPlus.Forward => Attacks.king(square, Direction.Up)
                .bitor(Attacks.pawn(square, Direction.Up_Right))
                .bitor(Attacks.king(square, Direction.Up_Left)),
            DirectionPlus.Backward => Attacks.king(square, Direction.Down)
                .bitor(Attacks.king(square, Direction.Down_Left))
                .bitor(Attacks.pawn(square, Direction.Down_Right)),
            DirectionPlus.KingSide => Attacks.king(square, Direction.Right)
                .bitor(Attacks.king(square, Direction.Up_Right))
                .bitor(Attacks.king(square, Direction.Down_Right)),
            DirectionPlus.QueenSide => Attacks.king(square, Direction.Left)
                .bitor(Attacks.king(square, Direction.Up_Left))
                .bitor(Attacks.king(square, Direction.Down_Left)),
            DirectionPlus.Diagonal => Attacks.king(square, Direction.Up_Left)
                .bitor(Attacks.king(square, Direction.Up_Right))
                .bitor(Attacks.king(square, Direction.Down_Left))
                .bitor(Attacks.king(square, Direction.Down_Right)),

            DirectionPlus.Horizontal => Attacks.king(square, Direction.Left)
                .bitor(Attacks.king(square, Direction.Right)),
            DirectionPlus.Vertical => Attacks.king(square, Direction.Up)
                .bitor(Attacks.king(square, Direction.Down)),
            DirectionPlus.Straight => Attacks.king_plus(square, DirectionPlus.Horizontal)
                .bitor(Attacks.king_plus(square, DirectionPlus.Vertical)),
            DirectionPlus.All => Attacks.king_plus(square, DirectionPlus.Straight)
                .bitor(Attacks.king_plus(square, DirectionPlus.Diagonal)),
        };
    }

    pub fn piece_ray(square: Square, occupied: Bitboard, piece: Piece) Bitboard {
        return switch (piece) {
            Piece.Black_Bishop, Piece.White_Bishop => Attacks.ray_plus(square, occupied, DirectionPlus.Diagonal),
            Piece.Black_Rook, Piece.White_Rook => Attacks.ray_plus(square, occupied, DirectionPlus.Straight),
            Piece.Black_Queen, Piece.White_Queen => Attacks.ray_plus(square, occupied, DirectionPlus.All),
            Piece.Black_King, Piece.White_King => Attacks.king_plus(square, DirectionPlus.All),
            Piece.Black_Knight, Piece.White_Knight => Bitboard.Zero,
            Piece.Black_Pawn => Attacks.pawn_plus(square, DirectionPlus.Backward),
            Piece.White_Pawn => Attacks.pawn_plus(square, DirectionPlus.Forward),
        };
    }
};

test "from_to" {
    try expectBitboard(
        \\........
        \\........
        \\........
        \\..oooo..
        \\........
        \\........
        \\........
        \\........
    , Attacks.from_to(Square.G5, Square.C5));
}

test "ray attacks" {
    try expectBitboard(
        \\........
        \\........
        \\........
        \\.....o..
        \\........
        \\........
        \\........
        \\........
    , Attacks.ray(Square.H5, Bitboard.F5.bitor(Bitboard.E5), Direction.Left));
}

test "eyes attacks" {
    try expectBitboard(
        \\........
        \\........
        \\........
        \\..oooo..
        \\........
        \\........
        \\........
        \\........
    , Attacks.eye(Square.B5, Bitboard.fromSquare(Square.F5), Direction.Right));

    try expectBitboard(
        \\......o.
        \\.....o..
        \\....o...
        \\........
        \\........
        \\........
        \\........
        \\........
    , Attacks.eye(Square.D5, Bitboard.G8, Direction.Up_Right));

    try expectBitboard(
        \\....o...
        \\....o...
        \\....o...
        \\........
        \\........
        \\........
        \\........
        \\........
    , Attacks.eye(Square.E5, Bitboard.Zero, Direction.Up));

    try expectBitboard(
        \\........
        \\........
        \\........
        \\........
        \\........
        \\........
        \\..ooo...
        \\........
    , Attacks.eye(Square.F2, Bitboard.fromSquare(Square.C2), Direction.Left));

    try expectBitboard(
        \\........
        \\........
        \\........
        \\....o...
        \\...o....
        \\..o.....
        \\.o......
        \\........
    , Attacks.eye(Square.F6, Bitboard.fromSquare(Square.B2), Direction.Down_Left));

    try expectBitboard(
        \\........
        \\........
        \\........
        \\.o......
        \\..o.....
        \\...o....
        \\........
        \\........
    , Attacks.eye(Square.A6, Bitboard.fromSquare(Square.D3), Direction.Down_Right));
}

test "piece attacks" {
    try expectBitboard(
        \\........
        \\........
        \\........
        \\..o.o...
        \\........
        \\........
        \\........
        \\........
    , Attacks.pawn_plus(Square.D4, DirectionPlus.Forward));

    try expectBitboard(
        \\........
        \\........
        \\........
        \\..ooo...
        \\........
        \\........
        \\........
        \\........
    , Attacks.king_plus(Square.D4, DirectionPlus.Forward));
}

pub const Prints = struct {
    const FileNames = [8]u8{ 'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h' };
    const RankNames = [8]u8{ '1', '2', '3', '4', '5', '6', '7', '8' };

    pub fn file(self: File) u8 {
        return FileNames[@intFromEnum(self)];
    }

    pub fn rank(self: Rank) u8 {
        return RankNames[@intFromEnum(self)];
    }

    pub fn fromSquare(self: Square) [2]u8 {
        return .{ Prints.file(self.toFile()), Prints.rank(self.toRank()) };
    }

    pub fn fromPromotionRole(self: MovePromotionRole) u8 {
        return switch (self) {
            MovePromotionRole.Bishop => 'B',
            MovePromotionRole.Knight => 'N',
            MovePromotionRole.Rook => 'R',
            MovePromotionRole.Queen => 'Q',
        };
    }

    pub fn bitboard(self: Bitboard) [71]u8 {
        var string: [71]u8 = undefined;
        for (&string, 0..) |*val, i| {
            const f: usize = i % 9;
            const r: usize = (71 - i) / 9;
            if (f == 8) {
                val.* = '\n';
            } else if (self.has(Square.fromCoord(@enumFromInt(f), @enumFromInt(r)))) {
                val.* = 'o';
            } else {
                val.* = '.';
            }
        }
        return string;
    }

    pub fn position(self: Position) [71]u8 {
        var string: [71]u8 = undefined;
        for (&string, 0..) |*val, i| {
            const f: usize = i % 9;
            const r: usize = (71 - i) / 9;
            if (f == 8) {
                val.* = '\n';
            } else {
                const square = Square.fromCoord(@enumFromInt(f), @enumFromInt(r));
                if (self.pieceOn(square)) |pieceOn| {
                    val.* = piece(pieceOn);
                } else {
                    val.* = '.';
                }
            }
        }
        return string;
    }

    pub fn role(self: Role) u8 {
        return switch (self) {
            Role.Bishop => 'B',
            Role.Knight => 'N',
            Role.Rook => 'R',
            Role.Queen => 'Q',
            Role.King => 'K',
            Role.Pawn => 'P',
        };
    }

    pub fn piece(self: Piece) u8 {
        return switch (self) {
            Piece.White_Bishop => 'B',
            Piece.White_Rook => 'R',
            Piece.White_Knight => 'N',
            Piece.White_King => 'K',
            Piece.White_Queen => 'Q',
            Piece.White_Pawn => 'P',
            Piece.Black_Bishop => 'b',
            Piece.Black_Rook => 'r',
            Piece.Black_Knight => 'n',
            Piece.Black_King => 'k',
            Piece.Black_Queen => 'q',
            Piece.Black_Pawn => 'p',
        };
    }

    pub fn moveFromTo(allocator: std.mem.Allocator, move: Move) ![]const u8 {
        const invalid_move: []const u8 = "--";
        return switch (move.kind) {
            MoveType.Normal => try std.mem.join(allocator, "", &[2][]const u8{ &Prints.fromSquare(@enumFromInt(move.from)), &Prints.fromSquare(@enumFromInt(move.to)) }),
            else => invalid_move,
        };
    }
};

test "bitboards" {
    try std.testing.expectEqualStrings(&Prints.bitboard(Bitboard.Zero),
        \\........
        \\........
        \\........
        \\........
        \\........
        \\........
        \\........
        \\........
    );

    try std.testing.expectEqualStrings(&Prints.bitboard(Bitboard.A1),
        \\........
        \\........
        \\........
        \\........
        \\........
        \\........
        \\........
        \\o.......
    );

    try std.testing.expectEqualStrings(&Prints.bitboard(Bitboard.H8.bitor(Bitboard.A1)),
        \\.......o
        \\........
        \\........
        \\........
        \\........
        \\........
        \\........
        \\o.......
    );
}

test "basic attacks" {
    try expectBitboard(
        \\........
        \\........
        \\........
        \\........
        \\........
        \\..o.....
        \\........
        \\........
    , Attacks.ray(Square.A1, Bitboard.C3, Direction.Up_Right));

    try expectBitboard(
        \\........
        \\........
        \\........
        \\....o...
        \\...o.o..
        \\....o...
        \\........
        \\........
    , Attacks.ray(Square.E4, Bitboard.All, Direction.Up)
        .bitor(Attacks.ray(Square.E4, Bitboard.All, Direction.Down))
        .bitor(Attacks.ray(Square.E4, Bitboard.All, Direction.Left))
        .bitor(Attacks.ray(Square.E4, Bitboard.All, Direction.Right)));

    try expectBitboard(
        \\........
        \\........
        \\........
        \\...o.o..
        \\........
        \\...o.o..
        \\........
        \\........
    , Attacks.ray(Square.E4, Bitboard.All, Direction.Up_Left)
        .bitor(Attacks.ray(Square.E4, Bitboard.All, Direction.Down_Right))
        .bitor(Attacks.ray(Square.E4, Bitboard.All, Direction.Down_Left))
        .bitor(Attacks.ray(Square.E4, Bitboard.All, Direction.Up_Right)));
}

fn expectBitboard(expected: []const u8, actual: Bitboard) !void {
    return std.testing.expectEqualStrings(expected, &Prints.bitboard(actual));
}

pub const Position = packed struct(u512) {
    bb_king: Bitboard,
    bb_queen: Bitboard,
    bb_rook: Bitboard,
    bb_bishop: Bitboard,
    bb_knight: Bitboard,
    bb_pawn: Bitboard,
    bb_white: Bitboard, // 8 * 7
    turn: Color,
    padding1: u7,
    padding7: u56,

    pub fn bb_vacant(self: Position) Bitboard {
        return self.occupied().complement();
    }

    pub fn bb_black(self: Position) Bitboard {
        return self.occupied().bitdiff(self.bb_white);
    }

    pub fn bb_turn(self: Position) Bitboard {
        return if (self.turn == Color.White) self.bb_white else self.bb_black();
    }

    pub fn bb_turn_pawn(self: Position) Bitboard {
        return self.bb_turn().bitand(self.bb_pawn);
    }

    pub fn bb_turn_bishop(self: Position) Bitboard {
        return self.bb_turn().bitand(self.bb_bishop);
    }

    pub fn bb_turn_rook(self: Position) Bitboard {
        return self.bb_turn().bitand(self.bb_rook);
    }

    pub fn bb_turn_knight(self: Position) Bitboard {
        return self.bb_turn().bitand(self.bb_knight);
    }

    pub fn bb_turn_queen(self: Position) Bitboard {
        return self.bb_turn().bitand(self.bb_queen);
    }

    pub fn bb_turn_king(self: Position) Bitboard {
        return self.bb_turn().bitand(self.bb_king);
    }

    pub fn bb_opponent(self: Position) Bitboard {
        return if (self.turn == Color.Black) self.bb_white else self.bb_black();
    }
    pub fn bb_opponent_pawn(self: Position) Bitboard {
        return self.bb_opponent().bitand(self.bb_pawn);
    }

    pub fn bb_opponent_bishop(self: Position) Bitboard {
        return self.bb_opponent().bitand(self.bb_bishop);
    }

    pub fn bb_opponent_rook(self: Position) Bitboard {
        return self.bb_opponent().bitand(self.bb_rook);
    }

    pub fn bb_opponent_knight(self: Position) Bitboard {
        return self.bb_opponent().bitand(self.bb_knight);
    }

    pub fn bb_opponent_queen(self: Position) Bitboard {
        return self.bb_opponent().bitand(self.bb_queen);
    }

    pub fn bb_opponent_king(self: Position) Bitboard {
        return self.bb_opponent().bitand(self.bb_king);
    }

    pub fn bb_white_pawn(self: Position) Bitboard {
        return self.bb_white.bitand(self.bb_pawn);
    }

    pub fn bb_white_bishop(self: Position) Bitboard {
        return self.bb_white.bitand(self.bb_bishop);
    }

    pub fn bb_white_rook(self: Position) Bitboard {
        return self.bb_white.bitand(self.bb_rook);
    }

    pub fn bb_white_knight(self: Position) Bitboard {
        return self.bb_white.bitand(self.bb_knight);
    }

    pub fn bb_white_queen(self: Position) Bitboard {
        return self.bb_white.bitand(self.bb_queen);
    }

    pub fn bb_white_king(self: Position) Bitboard {
        return self.bb_white.bitand(self.bb_king);
    }

    pub fn bb_black_pawn(self: Position) Bitboard {
        return self.bb_black().bitand(self.bb_pawn);
    }

    pub fn bb_black_bishop(self: Position) Bitboard {
        return self.bb_black().bitand(self.bb_bishop);
    }

    pub fn bb_black_rook(self: Position) Bitboard {
        return self.bb_black().bitand(self.bb_rook);
    }

    pub fn bb_black_knight(self: Position) Bitboard {
        return self.bb_black().bitand(self.bb_knight);
    }

    pub fn bb_black_queen(self: Position) Bitboard {
        return self.bb_black().bitand(self.bb_queen);
    }

    pub fn bb_black_king(self: Position) Bitboard {
        return self.bb_black().bitand(self.bb_king);
    }

    pub fn empty() Position {
        return std.mem.zeroes(Position);
    }

    pub fn occupied(self: Position) Bitboard {
        return self.bb_bishop
            .bitor(self.bb_rook)
            .bitor(self.bb_pawn)
            .bitor(self.bb_knight)
            .bitor(self.bb_queen)
            .bitor(self.bb_king);
    }

    pub fn turnOf(self: Position) Color {
        return self.turn;
    }

    pub fn pieceOn(self: Position, square: Square) ?Piece {
        if (self.roleOn(square)) |role| {
            return Piece.fromColors(self.colorOnFast(square), role);
        }
        return null;
    }

    pub fn getPiece(self: Position, square: Square) Piece {
        return self.pieceOn(square) orelse unreachable;
    }

    pub fn colorOnFast(self: Position, square: Square) Color {
        return if (self.bb_white.has(square))
            Color.White
        else
            Color.Black;
    }

    pub fn colorOn(self: Position, square: Square) ?Color {
        return if (self.bb_white.has(square))
            Color.White
        else if (self.occupied().has(square))
            Color.Black
        else
            null;
    }

    pub fn roleOn(self: Position, square: Square) ?Role {
        if (self.bb_pawn.has(square))
            return Role.Pawn;
        if (self.bb_rook.has(square))
            return Role.Rook;
        if (self.bb_bishop.has(square))
            return Role.Bishop;
        if (self.bb_knight.has(square))
            return Role.Knight;
        if (self.bb_king.has(square))
            return Role.King;
        if (self.bb_queen.has(square))
            return Role.Queen;
        return null;
    }

    pub fn opponent(self: Position) Bitboard {
        return self.bb_occupied.bitdiff(self.bb_turn);
    }

    pub fn put_piece(self: *Position, square: Square, piece: Piece) void {
        const color = piece.colorOf();
        const role = piece.roleOf();

        if (color == Color.White)
            self.bb_white = self.bb_white.set(square);

        const pieces: [*]Bitboard = @ptrCast(self);
        pieces[@intFromEnum(role)] = pieces[@intFromEnum(role)].set(square);
    }

    pub fn flipTurn(self: *Position) void {
        self.turn = self.turn.opposite();
    }

    pub fn remove_piece(self: *Position, square: Square) void {
        self.bb_pawn = self.bb_pawn.unset(square);
        self.bb_king = self.bb_king.unset(square);
        self.bb_rook = self.bb_rook.unset(square);
        self.bb_knight = self.bb_knight.unset(square);
        self.bb_queen = self.bb_queen.unset(square);
        self.bb_bishop = self.bb_bishop.unset(square);
        self.bb_white = self.bb_white.unset(square);
    }

    pub fn make_normal_move(self: *Position, from: Square, to: Square) ?Piece {
        const from_piece = self.pieceOn(from).?;
        const captured = self.pieceOn(to);
        self.remove_piece(from);
        self.remove_piece(to);
        self.put_piece(to, from_piece);
        return captured;
    }

    pub fn make_promotion_move(self: *Position, from: Square, to: Square, promotion: MovePromotionRole) ?Piece {
        const from_piece = self.pieceOn(from).?;
        const captured = self.pieceOn(to);
        self.remove_piece(from);
        self.remove_piece(to);
        self.put_piece(to, from_piece.promote(promotion));
        return captured;
    }

    pub fn make_castling_move(self: *Position, kingFrom: Square, kingTo: Square) void {
        const from_king = self.getPiece(kingFrom);
        const side = CastlingSide.fromKingTo(kingTo);
        const rookToFile = if (side == CastlingSide.King) File.F else File.D;
        const rookTo = Square.fromCoord(rookToFile, kingFrom.toRank());
        const rookFromFile = if (side == CastlingSide.King) File.H else File.A;
        const rookFrom = Square.fromCoord(rookFromFile, kingFrom.toRank());
        const from_rook = self.getPiece(rookFrom);

        self.remove_piece(kingFrom);
        self.remove_piece(rookFrom);
        self.put_piece(kingTo, from_king);
        self.put_piece(rookTo, from_rook);
    }

    pub fn make_move(self: *Position, move: Move) ?Piece {
        switch (move.kind) {
            MoveType.Normal => {
                return self.make_normal_move(@enumFromInt(move.from), @enumFromInt(move.to));
            },
            MoveType.Castling => {
                self.make_castling_move(@enumFromInt(move.from), @enumFromInt(move.to));
                return null;
            },
            MoveType.Promotion => {
                return self.make_promotion_move(@enumFromInt(move.from), @enumFromInt(move.to), move.promotion);
            },
            MoveType.EnPassant => {
                return null;
            },
        }
    }

    pub fn make_move_and_flip_turn(self: *Position, move: Move) ?Piece {
        const res = self.make_move(move);
        self.flipTurn();
        return res;
    }
};

pub const Fen = struct {
    pub const Initial = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1";

    pub fn parse(string: []const u8) Position {
        var state: u8 = 0;
        var position: Position = Position.empty();
        var rank: u8 = 7;
        var file: u8 = 0;

        for (string) |char| {
            switch (char) {
                ' ' => {
                    state = state + 1;
                },
                '/' => {
                    rank = rank - 1;
                    file = 0;
                },
                '1'...'8' => {
                    file = file + char - '0';
                },
                else => {
                    if (state == 0) {
                        if (parsePiece(char)) |piece| {
                            const square = Square.fromCoord(@enumFromInt(file), @enumFromInt(rank));
                            position.put_piece(square, piece);
                            file = file + 1;
                        }
                    }
                    if (char == 'b' and state == 1) {
                        position.flipTurn();
                    }
                },
            }
        }
        return position;
    }

    pub fn parsePiece(char: u8) ?Piece {
        return switch (char) {
            'r' => Piece.Black_Rook,
            'b' => Piece.Black_Bishop,
            'n' => Piece.Black_Knight,
            'k' => Piece.Black_King,
            'q' => Piece.Black_Queen,
            'p' => Piece.Black_Pawn,
            'R' => Piece.White_Rook,
            'B' => Piece.White_Bishop,
            'N' => Piece.White_Knight,
            'K' => Piece.White_King,
            'Q' => Piece.White_Queen,
            'P' => Piece.White_Pawn,
            else => null,
        };
    }
};

test "Position A" {
    var position: Position = Position.empty();
    try std.testing.expectEqual(position.turnOf(), Color.White);
    position.flipTurn();
    try std.testing.expectEqual(position.turnOf(), Color.Black);

    try std.testing.expectEqual(64, @sizeOf(Position));

    var position2: Position = Position.empty();

    position2.put_piece(Square.A1, Piece.White_Rook);

    try std.testing.expectEqual(Piece.White_Rook, position2.pieceOn(Square.A1));

    try expectPosition(
        \\........
        \\........
        \\........
        \\........
        \\........
        \\........
        \\........
        \\R.......
    , position2);

    position2.put_piece(Square.B1, Piece.White_Bishop);
    position2.put_piece(Square.C1, Piece.White_Knight);
    position2.put_piece(Square.C3, Piece.White_Pawn);

    try expectPosition(
        \\........
        \\........
        \\........
        \\........
        \\........
        \\..P.....
        \\........
        \\RBN.....
    , position2);
}

fn expectPosition(expected: []const u8, actual: Position) !void {
    return std.testing.expectEqualStrings(expected, &Prints.position(actual));
}

test "Fen" {
    try expectPosition(
        \\rnbqkbnr
        \\pppppppp
        \\........
        \\........
        \\........
        \\........
        \\PPPPPPPP
        \\RNBQKBNR
    , Fen.parse(Fen.Initial));
}

pub const MoveType = enum(u2) { Normal, Castling, Promotion, EnPassant };

pub const MovePromotionRole = enum(u2) { Queen, Rook, Bishop, Knight };

pub const Move = packed struct(u16) {
    from: u6,
    to: u6,
    kind: MoveType,
    promotion: MovePromotionRole,

    pub const none: Move = .{
        .from = 0,
        .to = 0,
        .kind = undefined,
        .promotion = undefined,
    };

    pub fn isNone(self: Move) bool {
        return self == Move.none;
    }
};

pub const Parses = struct {
    pub fn bitboard(string: *const [71:0]u8) Bitboard {
        var result = Bitboard.Zero;

        for (0..8) |rank| {
            for (0..8) |file| {
                const char = string[(7 - rank) * 9 + file];
                switch (char) {
                    'o' => {
                        result = result.set(Square.fromCoord(@enumFromInt(file), @enumFromInt(rank)));
                    },
                    else => {},
                }
            }
        }
        return result;
    }

    pub fn white(string: *const [71:0]u8) Position {
        var result = Position.empty();

        for (0..8) |rank| {
            for (0..8) |file| {
                const char = string[(7 - rank) * 9 + file];
                if (Fen.parsePiece(char)) |piece| {
                    const square = Square.fromCoord(@enumFromInt(file), @enumFromInt(rank));
                    result.put_piece(square, piece);
                }
            }
        }
        return result;
    }

    pub fn black(string: *const [71:0]u8) Position {
        var res = white(string);
        res.flipTurn();
        return res;
    }
};

test "parses bitboard" {
    try std.testing.expectEqual(Bitboard.A1, Parses.bitboard(
        \\........
        \\........
        \\........
        \\........
        \\........
        \\........
        \\........
        \\o.......
    ));

    try std.testing.expectEqual(Bitboard.D4.bitor(Bitboard.D5).bitor(Bitboard.H8), Parses.bitboard(
        \\.......o
        \\........
        \\........
        \\...o....
        \\...o....
        \\........
        \\........
        \\........
    ));
}

test "parses position" {
    try std.testing.expectEqual(Fen.parse(Fen.Initial), Parses.white(
        \\rnbqkbnr
        \\pppppppp
        \\........
        \\........
        \\........
        \\........
        \\PPPPPPPP
        \\RNBQKBNR
    ));
}

pub const CastlingSide = enum(u2) {
    King,
    Queen,

    pub fn fromKingTo(kingTo: Square) CastlingSide {
        return if (kingTo.toFile() == File.C) CastlingSide.Queen else CastlingSide.King;
    }
};

pub const CastlingRights = packed struct(u4) {
    white_kingside: bool = false,
    white_queenside: bool = false,
    black_kingside: bool = false,
    black_queenside: bool = false,

    pub fn full() CastlingRights {
        return .{ .white_kingside = true, .white_queenside = true, .black_kingside = true, .black_queenside = true };
    }

    pub fn whiteCastles(side: CastlingSide) CastlingRights {
        return .{ .white_kingside = side == CastlingSide.King, .white_queenside = side == CastlingSide.Queen };
    }

    pub fn blackCastles(side: CastlingSide) CastlingRights {
        return .{ .black_kingside = side == CastlingSide.King, .black_queenside = side == CastlingSide.Queen };
    }
};
