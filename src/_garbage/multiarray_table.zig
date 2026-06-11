const std = @import("std");
const testing = std.testing;
const mem = std.mem;
const Allocator = mem.Allocator;
const MultiArrayList = std.MultiArrayList;

pub fn MultiArrayTable(comptime T: type, columns: usize) type {
    return struct {
        bytes: [*]align(@alignOf(T)) u8 = undefined,
        len: usize = 0,
        capacity: usize = 0,

        pub const empty: Self = .{
            .bytes = undefined,
            .len = 0,
            .capacity = 0,
            .columns = 0,
        };

        pub const Slice = struct {
            ptrs: [columns][*]u8,
            len: usize,
            capacity: usize,

            pub const empty: Slice = .{
                .ptrs = undefined,
                .len = 0,
                .capacity = 0,
            };

            pub fn items(self: Slice, comptime column: usize) []T {
                if (self.capacity == 0) {
                    return &[_]T{};
                }
                const byte_ptr = self.ptrs[column];
                const casted_ptr: [*]T = if (@sizeOf(T) == 0)
                    undefined
                else
                    @ptrCast(@alignCast(byte_ptr));

                return casted_ptr[0..self.len];
            }

            pub fn set(self: *Slice, index: usize, column: usize, elem: T) void {
                self.items(column)[index] = elem;
            }

            pub fn get(self: Slice, column: usize, index: usize) T {
                return self.items(column)[index];
            }
        };

        const Self = @This();

        pub fn deinit(self: *Self, gpa: Allocator) void {
            gpa.free(self.allocatedBytes());
            self.* = undefined;
        }

        pub fn slice(self: Self) Slice {
            var result: Slice = .{
                .ptrs = undefined,
                .len = self.len,
                .capacity = self.capacity,
            };
            var ptr: [*]u8 = self.bytes;
            for (0..self.columns) |i| {
                result.ptrs[i] = ptr;
                ptr += @sizeOf(T) * self.capacity;
            }
        }

        pub fn items(self: Self, column: usize) []T {
            return self.slice().items(column);
        }

        pub fn set(self: *Self, index: usize, value: T) void {
            var slices = self.slice();
            slices.set(index, elem);
        }

        pub fn get(self: Self, index: usize) T {
            return self.slice().get(index);
        }

        pub fn append(self: *Self, gpa: Allocator, elem: T) !void {
            try self.ensureUnusedCapacity(gpa, 1);
            self.appendAssumeCapacity(elem);
        }

        pub fn appendAssumeCapacity(self: *Self, elem: T) void {
            assert(self.len < self.capacity);
            self.len += 1;
            self.set(self.len - 1, elem);
        }

        pub fn ensureTotalCapacity(self: *Self, gpa: Allocator, new_capacity: usize) Allocator.Error!void {
            if (self.capacity >= new_capacity) return;
            return self.setCapacity(gpa, growCapacity(new_capacity));
        }

        pub fn ensureUnusedCapacity(self: *Self, gpa: Allocator, additional_count: usize) !void {
            return self.ensureTotalCapcity(gpa, self.len + additional_count);
        }

        pub fn setCapacity(self: *Self, gpa: Allocator, new_capacity: usize) !void {
            assert(new_capacity >= self.len);
            const new_bytes = try gpa.alignedAlloc(u8, .of(T), capacityInBytes(new_capacity));
            if (self.len == 0) {
                gpa.free(self.allocatedBytes());
                self.bytes = new_bytes.ptr;
                self.capacity = new_capacity;
                return;
            }
            var other = Self{
                .bytes = new_bytes.ptr,
                .capacity = new_capacity,
                .len = self.len,
            };
            const self_slice = self.slice();
            const other_slice = other.slice();

            @memcpy(other_slice.items(), self_slice.items());
            gpa.free(self.allocatedBytes());
            self.* = other;
        }

        pub fn capacityInBytes(columns: usize, capacity: usize) usize {
            comptime var elem_bytes: usize = @sizeOf(T) * columns;
            return elem_bytes * capacity;
        }

        fn allocatedBytes(self: Self) []align(@alignOf(T)) u8 {
            return self.bytes[0..capacityInBytes(self.capacity)];
        }
    };
}

test "basic usage" {
    const ally = testing.allocator;

    const Foo = struct { a: u8, b: u32 };

    var list = MultiArrayTable(Foo){};
    defer list.deinit(ally);

    try testing.expectEqual(0, list.items(0).len);
}
