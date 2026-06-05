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

pub const DescriptionSymbolId = usize;

pub const DescriptionSymbol = struct {
    kind: DescriptionSymbolType,
    id: DescriptionSymbolId,

    pub fn fromSlice(slice: []const u8) ?DescriptionSymbol {
        _ = slice;
        return null;
    }
};
