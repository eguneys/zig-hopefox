const std = @import("std");
const testing = std.testing;
const Allocator = std.mem.Allocator;
const chess = @import("chess/types.zig");
const DotUsage = @import("usage2.zig").DotUsage;

pub fn expectVisuals(expected: []const u8, script: []const u8, position: *const [71:0]u8) !void {
    try expectVisualsPosition(expected, script, chess.Parses.white(position));
}
pub fn expectVisualsPosition(expected: []const u8, script: []const u8, position: chess.Position) !void {
    const ally = testing.allocator;

    var usage = try DotUsage.init(ally, script);
    defer usage.deinit(ally);

    try usage.runner.runOnPosition(ally, position);

    try std.testing.expectEqualStrings(expected, try usage.printLines(ally));
}

test "pawn captures" {
    try expectVisuals(
        \\2: {dxe4}{exd3}
    ,
        \\
        \\pawn *Captures pawn2 *becomes pawn3
        \\
    ,
        \\........
        \\........
        \\........
        \\........
        \\....p...
        \\...P....
        \\........
        \\........
    );
}

test "forks defends etc" {
    try expectVisuals(
        \\1: {Rc8+}
        \\2: {Rc8+ Rd8}
        \\3: {Rc8+ Rd8 Rxd8+}
        \\4: {Rc8+ Rd8 Rxd8+}
        \\5: 
    ,
        \\rook_t *Checks king_o *becomes rook2
        \\rook3_t *Blocks Check *becomes rook4
        \\rook2 *Captures rook4 *becomes rook5
        \\      .Forks king .and queen
        \\      .defendedby bishop
        \\
    ,
        \\q....k..
        \\........
        \\...r.b..
        \\........
        \\........
        \\........
        \\..R.....
        \\........
    );
}

test "forks nonexistent" {
    try expectVisuals(
        \\1: {Rc8+}
        \\2: {Rc8+ Rd8}
        \\3: {Rc8+ Rd8 Rxd8+}
        \\4: 
    ,
        \\rook_t *Checks king_o *becomes rook2
        \\rook3_t *Blocks Check *becomes rook4
        \\rook2 *Captures rook4 *becomes rook5
        \\      .Forks king .and queen
        \\
    ,
        \\.....k..
        \\........
        \\...r.b..
        \\........
        \\........
        \\........
        \\..R.....
        \\........
    );
}
