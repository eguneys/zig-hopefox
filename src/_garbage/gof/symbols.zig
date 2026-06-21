const std = @import("std");
const chess = @import("chess/types.zig");

pub const DescriptionSymbolType = enum {
    Piece,
    Pawn,
    King,
    Queen,
    Rook,
    Bishop,
    Knight,
    Major,
    Minor,
    Square,
    Turn,
};

const RoleNames: [6][]const u8 = .{
    "king", "queen", "rook", "bishop", "knight", "pawn",
};
const RoleKinds = [_]DescriptionSymbolType{
    DescriptionSymbolType.King, DescriptionSymbolType.Queen, DescriptionSymbolType.Rook, DescriptionSymbolType.Bishop, DescriptionSymbolType.Knight,
    DescriptionSymbolType.Pawn,
};

pub const DescriptionSymbolId = usize;

pub const DescriptionSymbol = struct {
    kind: DescriptionSymbolType,
    id: DescriptionSymbolId,

    pub fn equals(self: DescriptionSymbol, other: DescriptionSymbol) bool {
        return self.kind == other.kind and self.id == other.id;
    }

    pub fn fromSlice(slice: []const u8) ?DescriptionSymbol {
        for (RoleNames, RoleKinds) |name, kind| {
            if (std.mem.startsWith(u8, slice, name)) {
                return .{ .kind = kind, .id = DescriptionSymbol.extract_id(slice[name.len..]) };
            }
        }
        if (std.mem.startsWith(u8, slice, "turn")) {
            return .{ .kind = DescriptionSymbolType.Turn, .id = DescriptionSymbol.extract_id(slice[4..]) };
        }

        return null;
    }

    fn extract_id(slice: []const u8) DescriptionSymbolId {
        var base: usize = slice.len;
        var id: usize = 0;
        for (slice) |char| {
            id += (char - '0') * std.math.pow(usize, 10, base - 1);
            base -= 1;
        }
        return id;
    }
};

test "fromSlice" {
    try std.testing.expect(null != DescriptionSymbol.fromSlice("king3"));
    try std.testing.expectEqual(DescriptionSymbolType.King, DescriptionSymbol.fromSlice("king3").?.kind);
    try std.testing.expectEqual(3, DescriptionSymbol.fromSlice("king3").?.id);
    try std.testing.expectEqual(12, DescriptionSymbol.fromSlice("king12").?.id);
}

pub const SymbolPosition = struct {
    position: chess.Position,
    symbol: DescriptionSymbol,

    pub fn init(symbol: DescriptionSymbol, position: chess.Position) SymbolPosition {
        return .{ .symbol = symbol, .position = position };
    }

    pub fn bitboard(self: SymbolPosition) chess.Bitboard {
        return switch (self.symbol.kind) {
            DescriptionSymbolType.King => self.position.bb_king,
            DescriptionSymbolType.Pawn => self.position.bb_pawn,
            DescriptionSymbolType.Queen => self.position.bb_queen,
            DescriptionSymbolType.Bishop => self.position.bb_bishop,
            DescriptionSymbolType.Rook => self.position.bb_rook,
            DescriptionSymbolType.Knight => self.position.bb_knight,
            DescriptionSymbolType.Turn => self.position.bb_turn(),
            else => chess.Bitboard.Zero,
        };
    }

    pub fn captures(self: SymbolPosition, from: chess.Square) chess.Bitboard {
        switch (self.symbol.kind) {
            DescriptionSymbolType.Turn => {
                std.debug.print("{}", .{from});
                return chess.Bitboard.Zero;
            },
            DescriptionSymbolType.Pawn => {
                const piece = self.position.getPiece(from);
                const direction = if (piece.colorOf() == chess.Color.White)
                    chess.DirectionPlus.Forward
                else
                    chess.DirectionPlus.Backward;
                return chess.Attacks.pawn_plus(from, direction);
            },
            DescriptionSymbolType.Bishop => {
                return chess.Attacks.ray_plus(from, self.position.occupied(), chess.DirectionPlus.Diagonal);
            },
            DescriptionSymbolType.King => {
                return chess.Attacks.king_plus(from, chess.DirectionPlus.All);
            },
            else => {
                return chess.Bitboard.Zero;
            },
        }
    }
};
