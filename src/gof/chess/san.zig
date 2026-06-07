const std = @import("std");
const types = @import("types.zig");
const flat_map = @import("flat_map.zig");

pub const San = struct {
    from: types.Square,
    to: types.Square,
    ambiguity: bool,
    piece: types.Piece,
    promotion: ?types.MovePromotionRole,
    castling: ?types.Castling,
    capture: ?types.Square,
    check: bool,
    checkmate: bool,

    pub fn fromMove(position: types.Position, move: types.Move) San {
        const to: types.Square = @enumFromInt(move.to);
        return .{
            .piece = position.pieceOn(@enumFromInt(move.from)).?,
            .from = @enumFromInt(move.from),
            .to = to,
            .ambiguity = false,
            .promotion = if (move.kind == types.MoveType.Promotion) move.promotion else null,
            .castling = null,
            .capture = if (position.pieceOn(to) != null) to else null,
            .check = false,
            .checkmate = false,
        };
    }
};

pub const Prints = struct {
    pub fn fromSan(allocator: std.mem.Allocator, san: San) ![]const u8 {
        var res = try std.ArrayList(u8).initCapacity(allocator, 8);
        errdefer res.deinit(allocator);

        if (san.piece.roleOf() != types.Role.Pawn) {
            try res.append(allocator, types.Prints.role(san.piece.roleOf()));
        }

        //try res.appendSlice(allocator, &types.Prints.fromSquare(san.from));
        if (san.capture != null) {
            if (san.piece.roleOf() == types.Role.Pawn) {
                try res.append(allocator, types.Prints.file(san.from.toFile()));
            }
            try res.append(allocator, 'x');
        }
        try res.appendSlice(allocator, &types.Prints.fromSquare(san.to));

        if (san.promotion) |promotion| {
            try res.append(allocator, '=');
            try res.append(allocator, types.Prints.fromPromotionRole(promotion));
        }

        return res.toOwnedSlice(allocator);
    }

    pub fn fromSans(allocator: std.mem.Allocator, slice: []San) ![]const u8 {
        var res = try std.ArrayList(u8).initCapacity(allocator, 8);
        errdefer res.deinit(allocator);

        var sep: []const u8 = "";
        for (slice) |san| {
            try res.appendSlice(allocator, sep);
            const san_string = try Prints.fromSan(allocator, san);
            try res.appendSlice(allocator, san_string);
            allocator.free(san_string);
            sep = " ";
        }
        return try res.toOwnedSlice(allocator);
    }
};

pub const Uci = struct {
    from: types.Square,
    to: types.Square,
    promotion: ?types.MovePromotionRole,

    pub fn role(char: u8) types.MovePromotionRole {
        return switch (char) {
            'b' => types.MovePromotionRole.Bishop,
            'n' => types.MovePromotionRole.Knight,
            'r' => types.MovePromotionRole.Rook,
            'q' => types.MovePromotionRole.Queen,
            else => unreachable,
        };
    }

    pub fn file(char: u8) types.File {
        return switch (char) {
            'a' => types.File.A,
            'b' => types.File.B,
            'c' => types.File.C,
            'd' => types.File.D,
            'e' => types.File.E,
            'f' => types.File.F,
            'g' => types.File.G,
            'h' => types.File.H,
            else => unreachable,
        };
    }

    pub fn rank(char: u8) types.Rank {
        return switch (char) {
            '1' => types.Rank.R1,
            '2' => types.Rank.R2,
            '3' => types.Rank.R3,
            '4' => types.Rank.R4,
            '5' => types.Rank.R5,
            '6' => types.Rank.R6,
            '7' => types.Rank.R7,
            '8' => types.Rank.R8,
            else => unreachable,
        };
    }

    pub fn square(string: []const u8) types.Square {
        return types.Square.fromCoord(Uci.file(string[0]), Uci.rank(string[1]));
    }

    pub fn move(uci: []const u8) Uci {
        const from = Uci.square(uci);
        const to = Uci.square(uci[2..4]);
        const promotion = if (uci.len == 5) Uci.role(uci[4]) else null;
        return .{ .from = from, .to = to, .promotion = promotion };
    }

    pub fn toMove(self: Uci, position: types.Position) types.Move {
        _ = position;
        const kind = if (self.promotion != null) types.MoveType.Promotion else types.MoveType.Normal;
        const promotion = self.promotion orelse types.MovePromotionRole.Queen;
        return .{ .from = @intCast(@intFromEnum(self.from)), .to = @intCast(@intFromEnum(self.to)), .kind = kind, .promotion = promotion };
    }
};

test "pawn moves" {
    const ally = std.testing.allocator;

    const position = types.Fen.parse(types.Fen.Initial);
    const sans = try Prints.fromSan(ally, San.fromMove(position, Uci.move("e2e4").toMove(position)));
    defer ally.free(sans);

    try std.testing.expectEqualStrings("e4", sans);

    try testSan("e4", "e3e4",
        \\........
        \\........
        \\........
        \\........
        \\........
        \\....p...
        \\........
        \\........
    );

    try testSan("cxd4", "c3d4",
        \\........
        \\........
        \\........
        \\........
        \\...P....
        \\..p.....
        \\........
        \\........
    );

    try testSan("e8=Q", "e7e8q",
        \\........
        \\....p...
        \\........
        \\........
        \\........
        \\........
        \\........
        \\........
    );
}

fn testSan(expected: []const u8, uci: []const u8, str_position: *const [71:0]u8) !void {
    const ally = std.testing.allocator;
    const position = types.Parses.white(str_position);
    const sans = try Prints.fromSan(ally, San.fromMove(position, Uci.move(uci).toMove(position)));
    defer ally.free(sans);

    try std.testing.expectEqualStrings(expected, sans);
}

test "king moves" {
    try testSan("Kf4", "e3f4",
        \\........
        \\....p...
        \\........
        \\........
        \\........
        \\....k...
        \\........
        \\........
    );

    try testSan("Qxe7", "e3e7",
        \\........
        \\....p...
        \\........
        \\........
        \\........
        \\....q...
        \\........
        \\........
    );
}
