const std = @import("std");
const testing = std.testing;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const AutoHashMap = std.AutoHashMap;
const log = @import("logs.zig");

pub fn Table(C: type, R: type) type {
    return struct {
        columns: ArrayList(ArrayList(R)),
        column_by_symbol: AutoHashMap(C, usize),

        const Self = @This();

        pub fn deinit(self: *Self, allocator: Allocator) void {
            for (self.columns.items) |*column| column.deinit(allocator);
            self.columns.deinit(allocator);
            self.column_by_symbol.deinit();
        }

        pub fn init(allocator: Allocator) !Self {
            const column_by_symbol: AutoHashMap(C, usize) = .init(allocator);

            return .{ .column_by_symbol = column_by_symbol, .columns = .empty };
        }

        pub fn addColumn(self: *Self, allocator: Allocator, key: C) !bool {
            const existing = try self.column_by_symbol.getOrPut(key);

            if (!existing.found_existing) {
                existing.value_ptr.* = self.columns.items.len;

                var column: ArrayList(R) = .empty;
                errdefer column.deinit(allocator);
                try self.columns.append(allocator, column);
                return true;
            }
            return false;
        }

        pub fn getColumn(self: Self, column: C) []R {
            const icolumn = self.column_by_symbol.get(column).?;
            return self.columns.items[icolumn].items;
        }

        pub fn getValue(self: Self, column: C, row: usize) R {
            const icolumn = self.column_by_symbol.get(column).?;
            return self.columns.items[icolumn].items[row];
        }

        pub fn setLastRow(self: Self, column: C, value: R) void {
            const icolumn = self.column_by_symbol.get(column).?;
            self.columns.items[icolumn].items[self.columns.items[icolumn].items.len - 1] = value;
        }

        pub fn duplicateRow(self: *Self, allocator: Allocator, row: usize) !void {
            for (self.columns.items) |*column| {
                try column.append(allocator, column.items[row]);
            }
        }

        pub fn appendRow(self: *Self, allocator: Allocator, row: []R) !void {
            for (row, self.columns.items) |value, *column| {
                try column.append(allocator, value);
            }
        }

        pub fn clearRetainingCapacity(self: *Self) void {
            for (self.columns.items) |*column| column.clearRetainingCapacity();
        }
    };
}

test "basic usage" {
    const ally = std.testing.allocator;

    var table = try Table(usize, usize).init(ally);
    defer table.deinit(ally);

    _ = try table.addColumn(ally, 1);
    _ = try table.addColumn(ally, 2);
    _ = try table.addColumn(ally, 3);
    _ = try table.addColumn(ally, 4);

    _ = try table.addColumn(ally, 3);
    _ = try table.addColumn(ally, 3);
    try std.testing.expectEqual(4, table.columns.items.len);

    var row = try ArrayList(usize).initCapacity(ally, 8);
    defer row.deinit(ally);

    try row.append(ally, 50);
    try row.append(ally, 51);
    try row.append(ally, 52);
    try row.append(ally, 53);
    try table.appendRow(ally, row.items);

    try std.testing.expectEqual(1, table.columns.items[0].items.len);
    try std.testing.expectEqual(51, table.getValue(2, 0));
    try std.testing.expectEqual(52, table.getValue(3, 0));

    try table.duplicateLastRow(ally);

    try std.testing.expectEqual(2, table.columns.items[0].items.len);

    table.setLastRow(2, 0);
    try std.testing.expectEqual(0, table.getValue(2, 1));
}
