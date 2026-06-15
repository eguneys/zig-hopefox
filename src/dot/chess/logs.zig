const std = @import("std");
const cs = @import("types.zig");
const san = @import("san.zig");

pub fn bbo(a: cs.Bitboard) void {
    std.debug.print("\nA:\n{s}", .{cs.Prints.bitboard(a)});
}

pub fn bb(a: cs.Bitboard, b: cs.Bitboard) void {
    std.debug.print("\nA:\n{s}\nB:\n{s}\n", .{ cs.Prints.bitboard(a), cs.Prints.bitboard(b) });
}

pub fn sq(a: cs.Square, b: cs.Square) void {
    std.debug.print("\nA:{s} B:{s}\n", .{ cs.Prints.fromSquare(a), cs.Prints.fromSquare(b) });
}
pub fn pos(a: cs.Position) void {
    std.debug.print("\n{s}\n", .{cs.Prints.position(a)});
}
pub fn move(a: cs.Move) void {
    std.debug.print("\n{s}{s}\n", .{ cs.Prints.fromSquare(@enumFromInt(a.from)), cs.Prints.fromSquare(@enumFromInt(a.to)) });
}

pub fn d(a: usize) void {
    std.debug.print("D:{d} ", .{a});
}

pub fn str(a: []const u8) void {
    std.debug.print("{s} ", .{a});
}
