const std = @import("std");
const types = @import("types.zig");
const flat_map = @import("flat_map.zig");
const san = @import("san.zig");

pub const Line = struct {
    position: types.Position,
    moves: []types.Move,

    pub fn deinit(self: Line, allocator: std.mem.Allocator) void {
        allocator.free(self.moves);
    }
};

pub const PositionNode = struct {
    position: types.Position,
    parent: ?*PositionNode,
    children: std.ArrayList(*PositionNode),

    pub fn root(allocator: std.mem.Allocator, position: types.Position) !*PositionNode {
        const child_ptr = try allocator.create(PositionNode);
        child_ptr.* = PositionNode.init(position, null);
        return child_ptr;
    }

    fn init(position: types.Position, parent: ?*PositionNode) PositionNode {
        return .{ .position = position, .parent = parent, .children = .empty };
    }

    pub fn deinit(self: *PositionNode, allocator: std.mem.Allocator) void {
        for (self.children.items) |child| {
            child.deinit(allocator);
        }
        self.children.deinit(allocator);
        allocator.destroy(self);
    }

    pub fn addChild(self: *PositionNode, allocator: std.mem.Allocator, position: types.Position) !*PositionNode {
        const child_ptr = try allocator.create(PositionNode);
        child_ptr.* = PositionNode.init(position, self);
        try self.children.append(allocator, child_ptr);
        return child_ptr;
    }

    const NodePositionToMove = struct {
        pub fn flatMapContext(context: types.Position, child: *PositionNode) ?types.Move {
            return PositionsToMove.move(context, child.position);
        }
    };

    pub fn childMoves(self: PositionNode, allocator: std.mem.Allocator) ![]types.Move {
        const mapMoves = flat_map.ArrayListMapContext(NodePositionToMove, types.Position, *PositionNode, types.Move);
        var res = try mapMoves.flatMapContext(allocator, self.position, self.children.items);
        return res.toOwnedSlice(allocator);
    }

    pub fn depth(self: PositionNode) usize {
        var i: usize = 1;
        var pchild = self.parent;
        while (pchild) |child| {
            pchild = child.parent;
            i += 1;
        }
        return i;
    }

    pub fn movesToRoot(self: PositionNode, allocator: std.mem.Allocator) !Line {
        var list = try std.ArrayList(types.Move).initCapacity(allocator, self.depth());
        errdefer list.deinit(allocator);
        var child = self;
        while (child.parent) |parent| {
            const move = PositionsToMove.move(parent.position, child.position);
            try list.append(allocator, move);
            child = parent.*;
        }
        std.mem.reverse(types.Move, list.items);
        return .{ .moves = try list.toOwnedSlice(allocator), .position = child.position };
    }
};

const PositionsToMove = struct {
    pub fn move(p_from: types.Position, p_to: types.Position) types.Move {
        if (p_from.bb_turn_pawn().bitdiff(p_to.bb_opponent_pawn()).single()) |from| {
            if (p_to.bb_opponent_queen().bitdiff(p_from.bb_turn_queen()).single()) |to| {
                return .{
                    .from = @truncate(@intFromEnum(from)),
                    .to = @truncate(@intFromEnum(to)),
                    .kind = types.MoveType.Promotion,
                    .promotion = types.MovePromotionRole.Queen,
                };
            } else if (p_to.bb_opponent_rook().bitdiff(p_from.bb_turn_rook()).single()) |to| {
                return .{
                    .from = @truncate(@intFromEnum(from)),
                    .to = @truncate(@intFromEnum(to)),
                    .kind = types.MoveType.Promotion,
                    .promotion = types.MovePromotionRole.Rook,
                };
            } else if (p_to.bb_opponent_knight().bitdiff(p_from.bb_turn_knight()).single()) |to| {
                return .{
                    .from = @truncate(@intFromEnum(from)),
                    .to = @truncate(@intFromEnum(to)),
                    .kind = types.MoveType.Promotion,
                    .promotion = types.MovePromotionRole.Knight,
                };
            } else if (p_to.bb_opponent_bishop().bitdiff(p_from.bb_turn_bishop()).single()) |to| {
                return .{
                    .from = @truncate(@intFromEnum(from)),
                    .to = @truncate(@intFromEnum(to)),
                    .kind = types.MoveType.Promotion,
                    .promotion = types.MovePromotionRole.Bishop,
                };
            }
        }

        const diff =
            bit_diff(p_from.bb_turn_king(), p_to.bb_opponent_king()) orelse
            bit_diff(p_from.bb_turn_pawn(), p_to.bb_opponent_pawn()) orelse
            bit_diff(p_from.bb_turn_bishop(), p_to.bb_opponent_bishop()) orelse
            bit_diff(p_from.bb_turn_rook(), p_to.bb_opponent_rook()) orelse
            bit_diff(p_from.bb_turn_knight(), p_to.bb_opponent_knight()) orelse
            bit_diff(p_from.bb_turn_queen(), p_to.bb_opponent_queen()) orelse
            unreachable;

        return .{
            .from = @truncate(@intFromEnum(diff.from)),
            .to = @truncate(@intFromEnum(diff.to)),
            .kind = types.MoveType.Normal,
            .promotion = types.MovePromotionRole.Knight,
        };
    }

    const Diff = struct { from: types.Square, to: types.Square };

    fn bit_diff(bb_from: types.Bitboard, bb_to: types.Bitboard) ?Diff {
        if (bb_from.bitdiff(bb_to).single()) |from| {
            if (bb_to.bitdiff(bb_from).single()) |to| {
                return .{ .from = from, .to = to };
            }
        }

        return null;
    }
};

test "basic usage" {
    const ally = std.testing.allocator;

    var root = try PositionNode.root(ally, types.Parses.white(
        \\........
        \\........
        \\........
        \\........
        \\........
        \\........
        \\..P.....
        \\........
    ));
    defer root.deinit(ally);

    _ = try root.addChild(ally, types.Parses.black(
        \\........
        \\........
        \\........
        \\........
        \\..P.....
        \\........
        \\........
        \\........
    ));

    const moves = try root.childMoves(ally);
    defer ally.free(moves);
    const sans = try SansFromMoves.ReduceSlice(ally, &root.position, moves);
    defer ally.free(sans);
    const sans_string = try san.Prints.fromSans(ally, sans);
    defer ally.free(sans_string);

    try std.testing.expectEqualStrings("c4", sans_string);
}

pub const SansFromMoves = struct {
    pub const Reduce = flat_map.ArrayListMapContext(SansFromMoves, types.Position, types.Move, san.San).reduce;
    pub const ReduceSlice = flat_map.ArrayListMapContext(SansFromMoves, types.Position, types.Move, san.San).reduceSlice;

    pub fn reduce(position: *types.Position, move: types.Move) san.San {
        const res = san.San.fromMove(position.*, move);
        _ = position.make_move_and_flip_turn(move);
        return res;
    }
};

test "captures and promotions" {
    try testPositionSequence("cxd3",
        \\........
        \\........
        \\........
        \\........
        \\........
        \\...p....
        \\..P.....
        \\........
    ,
        \\........
        \\........
        \\........
        \\........
        \\........
        \\...P....
        \\........
        \\........
    );

    try testPositionSequence("Qd6",
        \\........
        \\.....Q..
        \\........
        \\..q.....
        \\........
        \\...p....
        \\..P.....
        \\........
    ,
        \\........
        \\........
        \\..qQ....
        \\........
        \\........
        \\...p....
        \\..P.....
        \\........
    );

    try testPositionSequence("Qxb7",
        \\........
        \\.q...Q..
        \\........
        \\........
        \\........
        \\...p....
        \\..P.....
        \\........
    ,
        \\........
        \\.Q......
        \\........
        \\........
        \\........
        \\...p....
        \\..P.....
        \\........
    );

    try testPositionSequence("d8=N",
        \\........
        \\.q.P.Q..
        \\........
        \\........
        \\........
        \\...p....
        \\..P.....
        \\........
    ,
        \\...N....
        \\.q...Q..
        \\........
        \\........
        \\........
        \\...p....
        \\..P.....
        \\........
    );
}
test "e2e4" {
    try testPositionSequence("e4",
        \\........
        \\........
        \\........
        \\........
        \\........
        \\........
        \\....P...
        \\....K...
    ,
        \\........
        \\........
        \\........
        \\........
        \\....P...
        \\........
        \\........
        \\....K...
    );
}

fn testPositionSequence(expected: []const u8, before: *const [71:0]u8, after: *const [71:0]u8) !void {
    const ally = std.testing.allocator;

    var root = try PositionNode.root(ally, types.Parses.white(before));
    defer root.deinit(ally);

    _ = try root.addChild(ally, types.Parses.black(after));

    const moves = try root.childMoves(ally);
    defer ally.free(moves);
    const sans = try SansFromMoves.ReduceSlice(ally, &root.position, moves);
    defer ally.free(sans);
    const sans_string = try san.Prints.fromSans(ally, sans);
    defer ally.free(sans_string);

    try std.testing.expectEqualStrings(expected, sans_string);
}

fn expectMovesUptoRoot(expected: []const u8, ucis: []const u8) !void {
    const ally = std.testing.allocator;

    var iterator = std.mem.splitScalar(u8, ucis, ' ');

    var root = try PositionNode.root(ally, types.Fen.parse(types.Fen.Initial));
    defer root.deinit(ally);

    var child = root;
    while (iterator.next()) |uci| {
        const move = san.Uci.toMove(san.Uci.move(uci), child.position);
        var position = child.position;
        _ = position.make_move_and_flip_turn(move);
        child = try child.addChild(ally, position);
    }

    const line = try child.movesToRoot(ally);
    defer line.deinit(ally);
    const sans = try SansFromMoves.ReduceSlice(ally, &root.position, line.moves);
    defer ally.free(sans);
    const sans_string = try san.Prints.fromSans(ally, sans);
    defer ally.free(sans_string);

    try std.testing.expectEqualStrings(expected, sans_string);
}

test "moves up to root" {
    try expectMovesUptoRoot("e4", "e2e4");
    try expectMovesUptoRoot("e4 e5 Nc3 Nc6", "e2e4 e7e5 b1c3 b8c6");
}
