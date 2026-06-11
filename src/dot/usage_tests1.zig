const std = @import("std");
const testing = std.testing;
const Allocator = std.mem.Allocator;
const chess = @import("chess/types.zig");
const DotUsage = @import("usage.zig").DotUsage;

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

test "bishop captures" {
    try expectVisuals(
        \\2: {Bxe4}
    ,
        \\
        \\bishop *Captures pawn *becomes bishop2
        \\
    ,
        \\........
        \\........
        \\..b.....
        \\........
        \\....p...
        \\...P....
        \\........
        \\........
    );
}

test "multi line" {
    try expectVisuals(
        \\2: {Bxe4}
        \\3: {Bxe4 dxe4}
    ,
        \\
        \\bishop *Captures pawn *becomes bishop2
        \\pawn2 *Captures bishop2 *becomes pawn3
        \\
    ,
        \\........
        \\........
        \\..b.....
        \\........
        \\....p...
        \\...P....
        \\........
        \\........
    );
}

test "regression 1" {
    const ally = testing.allocator;

    const script =
        \\bishop *Captures pawn *becomes pawn3
    ;

    const position_a = chess.Parses.white(
        \\..r.....
        \\...Qnk.p
        \\...R....
        \\....B..b
        \\Pp..p...
        \\.P..P...
        \\.....PPP
        \\......K.
    );
    const position_b = chess.Parses.white(
        \\...b.k..
        \\pp...prp
        \\........
        \\.Bp.....
        \\....R...
        \\.P......
        \\P....PPP
        \\.K......
    );
    const position_c = chess.Parses.white(
        \\........
        \\pp...Q.p
        \\.n..B.pk
        \\........
        \\.....PPq
        \\.......P
        \\PPP.....
        \\..K.....
    );

    var usage = try DotUsage.init(ally, script);
    defer usage.deinit(ally);

    try usage.runner.runOnPosition(ally, position_a);
    _ = try usage.printLines(ally);

    try usage.runner.runOnPosition(ally, position_b);
    const bb = try usage.printLines(ally);

    std.debug.print("WTF{s}", .{bb});
    try usage.runner.runOnPosition(ally, position_c);
    const aa = try usage.printLines(ally);

    std.debug.print("HELLO{s}", .{aa});
}
