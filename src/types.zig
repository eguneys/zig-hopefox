const std = @import("std");

const File = enum(u8) { A, B, C, D, E, F, G, H };
const Rank = enum(u8) { R1, R2, R3, R4, R5, R6, R7, R8 };

const Files = [8]File{ File.A, File.B, File.C, File.D, File.E, File.F, File.G, File.H };
const Ranks = [8]Rank{ Rank.R1, Rank.R2, Rank.R3, Rank.R4, Rank.R5, Rank.R6, Rank.R7, Rank.R8 };

const Square = enum(u8) {
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
};

const Squares = [64]Square{ Square.A1, Square.B1, Square.C1, Square.D1, Square.E1, Square.F1, Square.G1, Square.H1, Square.A2, Square.B2, Square.C2, Square.D2, Square.E2, Square.F2, Square.G2, Square.H2, Square.A3, Square.B3, Square.C3, Square.D3, Square.E3, Square.F3, Square.G3, Square.H3, Square.A4, Square.B4, Square.C4, Square.D4, Square.E4, Square.F4, Square.G4, Square.H4, Square.A5, Square.B5, Square.C5, Square.D5, Square.E5, Square.F5, Square.G5, Square.H5, Square.A6, Square.B6, Square.C6, Square.D6, Square.E6, Square.F6, Square.G6, Square.H6, Square.A7, Square.B7, Square.C7, Square.D7, Square.E7, Square.F7, Square.G7, Square.H7, Square.A8, Square.B8, Square.C8, Square.D8, Square.E8, Square.F8, Square.G8, Square.H8 };

const Color = enum(u1) { White, Black };
const Role = enum(u8) { King, Queen, Rook, Bishop, Knight, Pawn };

const Piece = enum(u8) {
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
};

const Bitboard = struct {
    bits: u64,

    pub const Zero = Bitboard{ .bits = 0 };

    pub fn fromSquare(sq: Square) Bitboard {
        return Bitboard{ .bits = @as(u64, 1) << @intCast(@intFromEnum(sq)) };
    }

    pub fn eq(self: Bitboard, other: Bitboard) bool {
        return self.bits == other.bits;
    }

    pub fn single(self: Bitboard) ?Square {
        return if (self.bits & (self.bits -% 1) == 0)
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

    pub fn bitand(self: Bitboard, other: Bitboard) Bitboard {
        return Bitboard{ .bits = self.bits & other.bits };
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

    try std.testing.expect(Bitboard.fromSquare(Square.A1).single() == Square.A1);

    try std.testing.expect(Bitboard.fromSquare(Square.A1).single() == Square.A1);
    try std.testing.expect(Bitboard.fromSquare(Square.H8).single() == Square.H8);

    for (Squares) |square|
        try std.testing.expect(Bitboard.fromSquare(square).single() == square);
}

const Direction = enum { Up, Down, Left, Right, Up_Left, Up_Right, Down_Left, Down_Right };

const Attacks = struct {
    const ray_masks = generate_ray_masks();

    fn generate_ray_masks() Bitboard[8][64] {
        var res = undefined;

        const df = [8]u8{ 0, 0, -1, 1, -1, 1, -1, 1 };
        const dr = [8]u8{ 1, -1, 0, 0, 1, 1, -1, -1 };

        for (Squares) |square| {
            const start_file = square.file();
            const start_rank = square.rank();

            for (0..8) |dir| {
                var mask = 0;
                var f = start_file + df[dir];
                var r = start_rank + dr[dir];

                while (f >= 0 and f < 8 and r >= 0 and r < 8) {
                    const target_square = Square.fromCoord(f, r);
                    mask |= Bitboard.fromSquare(target_square);

                    f += df[dir];
                    r += dr[dir];
                }

                res[dir][square] = mask;
            }
        }
        return res;
    }

    fn ray_attacks(square: Square, occupied: Bitboard) Bitboard {
        return ray_masks[square] & occupied;
    }
};

const Prints = struct {
    pub fn bitboard(self: Bitboard) [71]u8 {
        var string: [71]u8 = undefined;
        for (&string, 0..) |*val, i| {
            const f: usize = i % 9;
            const r: usize = (71 - i) / 9;
            if (f == 8) {
                val.* = '\n';
            } else if (self.has(Square.fromCoord(@enumFromInt(f), @enumFromInt(r)))) {
                val.* = '+';
            } else {
                val.* = '.';
            }
        }
        return string;
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
}
