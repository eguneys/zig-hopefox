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
    pub fn bitboardFrom(symbol: DescriptionSymbol, position: chess.Position) chess.Bitboard {
        return switch (symbol.kind) {
            DescriptionSymbolType.King => position.bb_king,
            DescriptionSymbolType.Pawn => position.bb_pawn,
            DescriptionSymbolType.Queen => position.bb_queen,
            else => chess.Bitboard.Zero,
        };
    }
};
