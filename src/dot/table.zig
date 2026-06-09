const std = @import("std");
const testing = std.testing;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

pub fn Table(C: type, R: type) type {
    return struct {
        symbols: []C,
        columns: []ArrayList(R),

        const Self = @This();

        pub fn deinit(self: *Self, allocator: Allocator) void {
            allocator.free(self.symbols);
            for (self.columns) |*column| column.deinit(allocator);
            allocator.free(self.columns);
        }

        pub fn init(allocator: Allocator, symbols: []C, capacity: usize) !Self {
            var columns = try ArrayList(ArrayList(R)).initCapacity(allocator, symbols.len);
            errdefer columns.deinit(allocator);

            for (symbols) |_| {
                var column = try ArrayList(R).initCapacity(allocator, capacity);
                errdefer column.deinit(allocator);
                try columns.append(allocator, column);
            }
            return .{ .symbols = symbols, .columns = try columns.toOwnedSlice(allocator) };
        }

        pub fn getValue(self: Self, column: usize, row: usize) R {
            return self.columns[column].items[row];
        }

        pub fn setLastRow(self: Self, column: usize, value: R) void {
            self.columns[column].items[self.columns[column].items.len - 1] = value;
        }

        pub fn duplicateLastRow(self: *Self, allocator: Allocator) !void {
            for (self.columns) |*column| {
                try column.append(allocator, column.items[column.items.len - 1]);
            }
        }

        pub fn appendRow(self: *Self, allocator: Allocator, row: []R) !void {
            for (row, self.columns) |value, *column| {
                try column.append(allocator, value);
            }
        }

        pub fn clearRetainingCapacity(self: *Self) void {
            for (self.columns) |*column| column.clearRetainingCapacity();
        }
    };
}

test "basic usage" {
    const ally = std.testing.allocator;

    var symbols = try ArrayList(usize).initCapacity(ally, 10);

    try symbols.append(ally, 1);
    try symbols.append(ally, 2);
    try symbols.append(ally, 3);
    try symbols.append(ally, 4);

    var table = try Table(usize, usize).init(ally, try symbols.toOwnedSlice(ally), 100);
    defer table.deinit(ally);

    try std.testing.expectEqual(4, table.columns.len);

    var row = try ArrayList(usize).initCapacity(ally, 8);
    defer row.deinit(ally);

    try row.append(ally, 50);
    try row.append(ally, 51);
    try row.append(ally, 52);
    try row.append(ally, 53);
    try table.appendRow(ally, row.items);

    try std.testing.expectEqual(1, table.columns[0].items.len);
    try std.testing.expectEqual(51, table.getValue(1, 0));
    try std.testing.expectEqual(52, table.getValue(2, 0));

    try table.duplicateLastRow(ally);

    try std.testing.expectEqual(2, table.columns[0].items.len);

    table.setLastRow(1, 0);
    try std.testing.expectEqual(0, table.getValue(1, 1));
}
