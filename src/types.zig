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

    pub fn file(self: Square) File {
        return @enumFromInt(@intFromEnum(self) % 8);
    }

    pub fn rank(self: Square) Rank {
        return @enumFromInt(@intFromEnum(self) / 8);
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

    pub fn fromSquare(sq: Square) Bitboard {
        return Bitboard{ .bits = @as(u64, 1) << @intCast(@intFromEnum(sq)) };
    }

    pub fn eq(self: Bitboard, other: Bitboard) bool {
        return self.bits == other.bits;
    }

    pub fn square(self: Bitboard) ?Square {
        return if (self.bits & (self.bits -% 1) == 0)
            @enumFromInt(@ctz(self.bits))
        else
            null;
    }
};

test "square" {
    try std.testing.expect(Square.A1.file() == File.A);
    try std.testing.expect(Square.B1.file() == File.B);
    try std.testing.expect(Square.C1.file() == File.C);
    try std.testing.expect(Square.D1.file() == File.D);
    try std.testing.expect(Square.E1.file() == File.E);
    try std.testing.expect(Square.F1.file() == File.F);
    try std.testing.expect(Square.G1.file() == File.G);
    try std.testing.expect(Square.H1.file() == File.H);

    try std.testing.expect(Square.A1.rank() == Rank.R1);
    try std.testing.expect(Square.B1.rank() == Rank.R1);
    try std.testing.expect(Square.C1.rank() == Rank.R1);
    try std.testing.expect(Square.D1.rank() == Rank.R1);
    try std.testing.expect(Square.E1.rank() == Rank.R1);
    try std.testing.expect(Square.F1.rank() == Rank.R1);
    try std.testing.expect(Square.G1.rank() == Rank.R1);
    try std.testing.expect(Square.H1.rank() == Rank.R1);

    try std.testing.expect(Square.A2.rank() == Rank.R2);
    try std.testing.expect(Square.A3.rank() == Rank.R3);
    try std.testing.expect(Square.A4.rank() == Rank.R4);
    try std.testing.expect(Square.A5.rank() == Rank.R5);
    try std.testing.expect(Square.A6.rank() == Rank.R6);
    try std.testing.expect(Square.A7.rank() == Rank.R7);
    try std.testing.expect(Square.A8.rank() == Rank.R8);

    try std.testing.expect(Bitboard.fromSquare(Square.A1).square() == Square.A1);

    try std.testing.expect(Bitboard.fromSquare(Square.A1).square() == Square.A1);
    try std.testing.expect(Bitboard.fromSquare(Square.H8).square() == Square.H8);

    for (Squares) |square|
        try std.testing.expect(Bitboard.fromSquare(square).square() == square);
}
