const chess = @import("chess/types.zig");
const expectVisuals = @import("usage_tests1.zig").expectVisuals;
const expectVisualsPosition = @import("usage_tests1.zig").expectVisualsPosition;

test ".eyesThrough" {
    try expectVisuals(
        \\1: {}
        \\2: {}
        \\3: {Bc5+}{Bg5+}
    ,
        \\queen_t .eyesThrough queen2 .through bishop
        \\                       .hanging
        \\bishop *Checks king *becomes bishop2
    ,
        \\........
        \\....K...
        \\........
        \\........
        \\........
        \\.Q..b..q
        \\........
        \\........
    );
}

test ".eyesThrough cannotBeCapturedBy" {
    try expectVisuals(
        \\1: {}
        \\2: {}
        \\3: {Bc5+}{Bg5+}
        \\4: {Bg5+}
    ,
        \\queen_t .eyesThrough queen2 .through bishop
        \\                       .hanging
        \\bishop *Checks king *becomes bishop2
        \\                                 .cannotBeCapturedBy queen2
    ,
        \\........
        \\....k...
        \\........
        \\........
        \\........
        \\..q.B..Q
        \\........
        \\........
    );
}

test ".eyesThrough cannotBeCapturedBy turn captures" {
    try expectVisuals(
        \\1: {}
        \\2: {}
        \\3: {Bc5+}{Bg5+}
        \\4: {Bg5+}
        \\5: {Bg5+ Nxg5}
    ,
        \\queen_t .eyesThrough queen2 .through bishop
        \\                       .hanging
        \\bishop *Checks king *becomes bishop2
        \\                                 .cannotBeCapturedBy queen2
        \\turn    *Captures  bishop2 *becomes turn2
    ,
        \\........
        \\....k...
        \\....n...
        \\........
        \\........
        \\..q.B..Q
        \\........
        \\........
    );
}

test ".eyesThrough cannotBeCapturedBy turn captures does not defend" {
    try expectVisuals(
        \\1: {}
        \\2: {}
        \\3: {Bc5+}{Bg5+}
        \\4: {Bg5+}
        \\5: {Bg5+ Nxg5}
        \\6: {Bg5+ Nxg5}
    ,
        \\queen_t .eyesThrough queen2 .through bishop
        \\                       .hanging
        \\bishop *Checks king *becomes bishop2
        \\                                 .cannotBeCapturedBy queen2
        \\turn    *Captures  bishop2 *becomes opponent2
        \\                                        .doesNotDefend queen2
    ,
        \\........
        \\....k...
        \\....n...
        \\........
        \\........
        \\..q.B..Q
        \\........
        \\........
    );

    try expectVisualsPosition(
        \\1: {}
        \\2: {}
        \\3: {Bf2}{Bc5+}{Bxg5+}
        \\4: {Bf2}{Bxg5+}
        \\5: {Bxg5+ Nxg5}
        \\6: {Bxg5+ Nxg5}
    ,
        \\queen_t .eyesThrough queen2 .through bishop
        \\                       .hanging
        \\bishop *Checks king *becomes bishop2
        \\                                 .cannotBeCapturedBy queen2
        \\turn    *Captures  bishop2 *becomes opponent2
        \\                                        .doesNotDefend queen2
    , chess.Fen.parse("r7/ppp1kp2/4n2r/4P1p1/6P1/2q1B2Q/P6P/5RK1 w - - 0 31"));
}

test "eyesThrough regression 1 Qa4 vs Qd4" {
    try expectVisualsPosition(
        \\1: {}{}
        \\2: {}{}
        \\3: {Bxf7+}{Bxf7+}
        \\4: {Bxf7+}{Bxf7+}
        \\5: {Bxf7+ Kxf7}{Bxf7+ Kxf7}
        \\6: {Bxf7+ Kxf7}{Bxf7+ Kxf7}
        \\7: {Bxf7+ Kxf7 Qxd4}{Bxf7+ Kxf7 Qxa4}
    ,
        \\queen .eyesThrough queen2 .through bishop
        \\                       .hanging
        \\bishop *Checks king *becomes bishop2
        \\                                 .cannotBeCapturedBy queen2
        \\turn    *Captures  bishop2 *becomes opponent2
        \\                                        .doesNotDefend queen2
        \\queen *Captures queen2 *becomes queen3
    , chess.Fen.parse("2r1r1k1/1b3p1p/p5p1/8/Q1Bq4/P6P/1P3PP1/1R4K1 w - - 0 26"));
}

test "eyesThrough regression 2 Bg3 without attack through" {
    try expectVisualsPosition(
        \\1: 
        \\2: 
        \\3: 
        \\4: 
        \\5: 
        \\6: 
        \\7: 
    ,
        \\queen_t .eyesThrough queen2 .through bishop
        \\                       .hanging
        \\bishop *Checks king *becomes bishop2
        \\                                 .cannotBeCapturedBy queen2
        \\turn    *Captures  bishop2 *becomes opponent2
        \\                                        .doesNotDefend queen2
        \\queen *Captures queen2 *becomes queen3
    , chess.Fen.parse("5k2/5p2/pq1b4/1p6/3QB3/P4Nr1/1PP2R1K/5R2 b - - 1 41"));
}
