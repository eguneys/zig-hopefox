const std = @import("std");
const testing = std.testing;
const Allocator = std.mem.Allocator;

pub fn TableBuilder(comptime K: type, comptime T: type) type {
    return struct {
        columns: std.AutoHashMapUnmanaged(K, bool),

        const Self = @This();

        pub fn init() Self {
            return .{ .columns = .{} };
        }

        pub fn addColumn(self: *Self, allocator: std.mem.Allocator, key: K) !void {
            try self.columns.put(allocator, key, true);
        }

        pub fn toTable(self: *Self, allocator: Allocator, capacity: usize) !Table(T) {
            const res = try Table(T).initCapacity(allocator, self.columns.size, capacity);

            self.columns.deinit(allocator);
            return res;
        }
    };
}

pub fn Table(comptime T: type) type {
    return struct {
        columns: []std.ArrayList(T),

        const Self = @This();

        pub fn initCapacity(allocator: Allocator, cols: usize, capacity: usize) !Self {
            const columns = try allocator.alloc(std.ArrayList(T), cols);
            for (columns) |*col| {
                col.* = try std.ArrayList(T).initCapacity(allocator, capacity);
            }

            return .{ .columns = columns };
        }

        pub fn size(self: Self) usize {
            return self.columns[0].items.len;
        }

        pub fn appendRow(self: *Self, allocator: Allocator, row: []const T) !void {
            std.debug.assert(row.len == self.columns.len);
            for (row, self.columns) |value, *column| {
                try column.append(allocator, value);
            }
        }

        pub fn appendDuplicateLastRow(self: *Self, allocator: Allocator) !void {
            for (self.columns) |*column| {
                try column.append(allocator, column.getLast());
            }
        }

        pub fn setLastRow(self: *const Self, col: usize, value: T) void {
            const items = self.columns[col].items;
            items[items.len - 1] = value;
        }

        pub fn getColumn(self: Self, col: usize) []T {
            return self.columns[col].items;
        }

        pub fn deinit(self: Self, allocator: Allocator) void {
            for (self.columns) |*column| {
                column.deinit(allocator);
            }
            allocator.free(self.columns);
        }
    };
}

test "basic usage" {
    const ally = testing.allocator;

    const Foo = struct { a: u8 };

    var table = try Table(Foo).initCapacity(ally, 3, 1024);
    defer table.deinit(ally);

    try testing.expectEqual(3, table.columns.len);
    try testing.expectEqual(0, table.size());

    const rows = [_]Foo{ .{ .a = 8 }, .{ .a = 2 }, .{ .a = 3 } };
    try table.appendRow(ally, &rows);

    try testing.expectEqualSlices(Foo, rows[0..1], table.getColumn(0));
    try testing.expectEqual(1, table.size());

    try table.appendDuplicateLastRow(ally);
    try testing.expectEqual(2, table.size());

    try testing.expectEqualSlices(Foo, &[_]Foo{ rows[0], rows[0] }, table.getColumn(0));
}
