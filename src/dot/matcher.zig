const std = @import("std");
const testing = std.testing;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const Table = @import("table.zig").Table;
const Tree = @import("tree.zig").Tree;
const History = @import("runner.zig").History;
const chess = @import("chess/types.zig");
const par = @import("parser.zig");

pub const Matcher = struct {
    pub fn run_dot(allocator: Allocator, history: History, dot: par.DotRef) !void {
        _ = allocator;
        _ = history;
        _ = dot;
    }
    pub fn run_star(allocator: Allocator, history: History, star: par.StarRef) !void {
        _ = allocator;
        _ = history;
        _ = star;
    }
};
