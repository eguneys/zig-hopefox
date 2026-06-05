pub const IrDescriptionSymbolType = enum {
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

pub const IrDescriptionSymbolId = usize;

pub const IrDescriptionSymbol = struct {
    kind: IrDescriptionSymbolType,
    id: IrDescriptionSymbolId,

    pub fn fromSlice(slice: []const u8) ?IrDescriptionSymbol {
        _ = slice;
        return null;
    }
};
