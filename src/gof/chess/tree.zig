const std = @import("std");
const types = @import("types.zig");
const flat_map = @import("flat_map.zig");
const san = @import("san.zig");

pub const PositionNode = struct {
    depth: usize,
    position: types.Position,
    children: ?std.ArrayList(PositionNode),

    pub fn init(depth: usize, position: types.Position) PositionNode {
        return .{ .depth = depth, .position = position, .children = null };
    }

    pub fn addChild(self: *PositionNode, allocator: std.mem.Allocator, position: types.Position) !void {
        if (self.children == null) {
            self.children = .empty;
            errdefer self.children.?.deinit(allocator);
        }
        try self.children.?.append(allocator, PositionNode.init(self.depth + 1, position));
    }

    const NodePositionToMove = struct {
        pub fn flatMapContext(context: types.Position, child: PositionNode) ?types.Move {
            return PositionsToMove.move(context, child.position);
        }
    };

    pub fn childMoves(self: PositionNode, allocator: std.mem.Allocator) ![]types.Move {
        const mapMoves = flat_map.ArrayListMapContext(NodePositionToMove, types.Position, PositionNode, types.Move);
        if (self.children) |children| {
            var res = try mapMoves.flatMapContext(allocator, self.position, children.items);
            return res.toOwnedSlice(allocator);
        } else {
            return &[0]types.Move{};
        }
    }

    pub fn deinit(self: *PositionNode, allocator: std.mem.Allocator) void {
        if (self.children) |*children| {
            for (children.items) |*child| child.deinit(allocator);
            children.deinit(allocator);
        }
    }
};

const PositionsToMove = struct {
    pub fn move(p_from: types.Position, p_to: types.Position) types.Move {
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

    var root = PositionNode.init(0, types.Parses.white(
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

    try root.addChild(ally, types.Parses.black(
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
        _ = position.make_move(move);
        return res;
    }
};

test "captures and promotions" {
    const before =
        \\........
        \\........
        \\........
        \\........
        \\........
        \\...p....
        \\..P.....
        \\........
    ;

    const after =
        \\........
        \\........
        \\........
        \\........
        \\........
        \\...P....
        \\........
        \\........
    ;

    try testPositionSequence(before, after, "cxd3");
}

fn testPositionSequence(before: *const [71:0]u8, after: *const [71:0]u8, expected: []const u8) !void {
    const ally = std.testing.allocator;

    var root = PositionNode.init(0, types.Parses.white(before));
    defer root.deinit(ally);

    try root.addChild(ally, types.Parses.black(after));

    const moves = try root.childMoves(ally);
    defer ally.free(moves);
    const sans = try SansFromMoves.ReduceSlice(ally, &root.position, moves);
    defer ally.free(sans);
    const sans_string = try san.Prints.fromSans(ally, sans);
    defer ally.free(sans_string);

    try std.testing.expectEqualStrings(expected, sans_string);
}
