const std = @import("std");
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;

pub fn ArrayListFlatMaps(map: type, T: type, U: type) type {
    return struct {
        pub fn flatMap(allocator: Allocator, list: []T) !ArrayList(U) {
            var result = try ArrayList(U).initCapacity(allocator, list.len);
            for (list) |item| {
                if (map.flatMap(item)) |result_item|
                    try result.append(allocator, result_item);
            }
            return result;
        }

        pub fn mapAllocator(allocator: Allocator, list: []T) !ArrayList(U) {
            var result = try ArrayList(U).initCapacity(allocator, list.len);
            for (list) |item| {
                if (try map.mapAllocator(allocator, item)) |result_item|
                    try result.append(allocator, result_item);
            }
            return result;
        }
    };
}

pub fn ArrayListMapContext(map: type, Context: type, T: type, U: type) type {
    return struct {
        pub fn flatMapContext(allocator: Allocator, context: Context, list: []T) !ArrayList(U) {
            var result = try ArrayList(U).initCapacity(allocator, list.len);
            for (list) |item| {
                if (map.flatMapContext(context, item)) |result_item|
                    try result.append(allocator, result_item);
            }
            return result;
        }

        pub fn mapContext(allocator: Allocator, context: Context, list: []T) !ArrayList(U) {
            var result = try ArrayList(U).initCapacity(allocator, list.len);
            for (list) |item| {
                const result_item = map.mapContext(context, item);
                try result.append(allocator, result_item);
            }
            return result;
        }

        pub fn mapWithContext(allocator: Allocator, context: Context, list: []T) !ArrayList(U) {
            var result = try ArrayList(U).initCapacity(allocator, list.len);
            for (list) |item| {
                const result_item = map.mapWithContext(context, item);
                try result.append(allocator, result_item);
            }
            return result;
        }
    };
}

test "basic flatMaps" {
    const ally = std.testing.allocator;

    const Foo = struct { a: u8 };
    const Bar = struct { b: u8 };

    const FooBarDoubler = struct {
        fn flatMap(foo: Foo) ?Bar {
            return if (foo.a == 0) null else Bar{ .b = foo.a * 3 };
        }
    };

    const mapFooBar = ArrayListFlatMaps(FooBarDoubler, Foo, Bar);

    var foos = try ArrayList(Foo).initCapacity(ally, 3);
    defer foos.deinit(ally);
    try foos.append(ally, Foo{ .a = 1 });
    try foos.append(ally, Foo{ .a = 0 });
    try foos.append(ally, Foo{ .a = 2 });

    var bars = try mapFooBar.flatMap(ally, foos.items);
    defer bars.deinit(ally);

    try std.testing.expectEqual(2, bars.items.len);
    try std.testing.expectEqual(3, bars.items[0].b);
    try std.testing.expectEqual(6, bars.items[1].b);
}

test "map context" {
    const ally = std.testing.allocator;

    const Foo = struct { a: u8 };
    const Bar = struct { b: u8 };

    const Context = struct { times: u8 };

    const FooBarDoubler = struct {
        fn mapContext(context: Context, foo: Foo) Bar {
            return Bar{ .b = foo.a * context.times };
        }
    };

    const mapFooBar = ArrayListMapContext(FooBarDoubler, Context, Foo, Bar);

    var foos = try ArrayList(Foo).initCapacity(ally, 3);
    defer foos.deinit(ally);
    try foos.append(ally, Foo{ .a = 1 });
    try foos.append(ally, Foo{ .a = 0 });
    try foos.append(ally, Foo{ .a = 2 });

    const doubler = Context{ .times = 2 };
    var bars = try mapFooBar.mapContext(ally, doubler, foos.items);
    defer bars.deinit(ally);

    try std.testing.expectEqual(3, bars.items.len);
    try std.testing.expectEqual(2, bars.items[0].b);
    try std.testing.expectEqual(0, bars.items[1].b);
    try std.testing.expectEqual(4, bars.items[2].b);
}
