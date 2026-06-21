const expectVisuals = @import("usage_tests1.zig").expectVisuals;

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
