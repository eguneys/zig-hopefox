const chess = @import("chess/types.zig");
const expectVisuals = @import("usage_tests1.zig").expectVisuals;
const expectVisualsPosition = @import("usage_tests1.zig").expectVisualsPosition;

test "basic usage" {
    try expectVisuals(
        \\2: {Rg1+}{Rc8+}
    ,
        \\
        \\rook *Checks king *becomes rook2
        \\
    ,
        \\......K.
        \\........
        \\........
        \\........
        \\........
        \\........
        \\........
        \\..r.....
    );
}

test "check test" {
    try expectVisualsPosition(
        \\2: {Rd1}{Rf6+}{Rc1+}{Rf8}
    ,
        \\
        \\rook *Checks king *becomes rook2
        \\
    , chess.Fen.parse("2r5/3Qnk1p/3R4/4B2b/Pp2p3/1P2P3/5PPP/6K1 b - - 4 32"));
}

test "_t _o" {
    try expectVisualsPosition(
        \\1: {Rc1+}
    ,
        \\rook_t *Checks king_o *becomes rook2
    , chess.Fen.parse("2r5/3Qnk1p/3R4/4B2b/Pp2p3/1P2P3/5PPP/6K1 b - - 4 32"));
}

test "Check symbol" {
    try expectVisuals(
        \\1: {Rc1+}
        \\2: {Rc1+ Bd1}
    ,
        \\rook *Checks king *becomes rook2
        \\bishop *Blocks Check *becomes bishop2
    ,
        \\........
        \\........
        \\........
        \\........
        \\b.......
        \\..r.....
        \\......p.
        \\......K.
    );
}
