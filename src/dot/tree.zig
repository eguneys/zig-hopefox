const std = @import("std");
const testing = std.testing;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

pub fn Tree(C: type) type {
    return struct {
        flat: ArrayList(Node),
        size: usize = 0,
        appending: usize = 0,

        const Self = @This();

        pub fn deinit(self: *Self, allocator: Allocator) void {
            self.flat.deinit(allocator);
        }

        pub fn init(allocator: Allocator) !Self {
            var flat = try ArrayList(Node).initCapacity(allocator, 1);
            errdefer flat.deinit(allocator);

            try flat.append(allocator, Node{ .parent = 0, .value = undefined, .children = .{ .off = 1, .len = 0 } });

            return .{ .flat = flat, .size = 1 };
        }

        pub fn getNode(self: *Self, off: usize) Node {
            return self.flat.items[off];
        }

        pub fn appendChild(self: *Self, allocator: Allocator, off: usize, value: C) !usize {
            try self.flat.append(allocator, .{ .parent = off, .value = value, .children = .{
                .off = 0,
                .len = 0,
            } });

            if (off != self.appending) {
                self.appending = off;
                if (self.flat.items[self.appending].children.len == 0) {
                    self.flat.items[self.appending].children.off = self.flat.items.len - 1;
                }
            }

            self.flat.items[off].children.len += 1;
            return self.flat.items.len - 1;
        }

        pub fn getHistory(self: *Self, allocator: Allocator, off: usize) ![]usize {
            var result = try ArrayList(usize).initCapacity(allocator, 1);
            errdefer result.deinit(allocator);

            var parent = off;
            while (parent != 0) {
                try result.append(allocator, parent);
                parent = self.getNode(parent).parent;
            }

            const res = try result.toOwnedSlice(allocator);
            std.mem.reverse(C, res);
            return res;
        }

        pub const Node = struct {
            value: C,
            parent: usize,
            children: Slice,
        };

        pub const Slice = struct {
            off: usize,
            len: usize,
        };
    };
}

test "basic usage" {
    const ally = std.testing.allocator;

    var tree = try Tree(usize).init(ally);
    defer tree.deinit(ally);

    try std.testing.expectEqual(0, tree.getNode(0).children.len);

    try std.testing.expectEqual(1, tree.appendChild(ally, 0, 1));
    try std.testing.expectEqual(2, tree.appendChild(ally, 0, 2));
    try std.testing.expectEqual(3, tree.appendChild(ally, 0, 3));

    try std.testing.expectEqual(3, tree.getNode(0).children.len);
    try std.testing.expectEqual(0, tree.getNode(1).children.len);
    try std.testing.expectEqual(0, tree.getNode(2).children.len);

    try std.testing.expectEqual(4, tree.appendChild(ally, 2, 4));
    try std.testing.expectEqual(5, tree.appendChild(ally, 2, 5));
    try std.testing.expectEqual(6, tree.appendChild(ally, 2, 6));

    try std.testing.expectEqual(3, tree.getNode(0).children.len);
    try std.testing.expectEqual(0, tree.getNode(1).children.len);
    try std.testing.expectEqual(3, tree.getNode(2).children.len);

    try std.testing.expectEqual(7, tree.appendChild(ally, 3, 7));

    try std.testing.expectEqual(3, tree.getNode(0).children.len);
    try std.testing.expectEqual(0, tree.getNode(1).children.len);
    try std.testing.expectEqual(3, tree.getNode(2).children.len);
    try std.testing.expectEqual(1, tree.getNode(3).children.len);

    try std.testing.expectEqual(8, tree.appendChild(ally, 1, 8));
    try std.testing.expectEqual(9, tree.appendChild(ally, 1, 9));

    try std.testing.expectEqual(3, tree.getNode(0).children.len);
    try std.testing.expectEqual(2, tree.getNode(1).children.len);
    try std.testing.expectEqual(3, tree.getNode(2).children.len);
    try std.testing.expectEqual(1, tree.getNode(3).children.len);

    try std.testing.expectEqual(1, tree.getNode(0).children.off);
    try std.testing.expectEqual(4, tree.getNode(2).children.off);
    try std.testing.expectEqual(8, tree.getNode(1).children.off);
    try std.testing.expectEqual(7, tree.getNode(3).children.off);

    _ = try tree.appendChild(ally, 9, 10);
    try std.testing.expectEqual(11, try tree.appendChild(ally, 10, 11));

    const history = try tree.getHistory(ally, 11);
    defer ally.free(history);
    try std.testing.expectEqualSlices(usize, &[_]usize{ 1, 9, 10, 11 }, history);
}
