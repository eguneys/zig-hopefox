const std = @import("std");
const testing = std.testing;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const Table = @import("table.zig").Table;
const Tree = @import("tree.zig").Tree;
const History = @import("runner.zig").History;
const chess = @import("chess/types.zig");
const par = @import("parser.zig");
const lx = @import("lexer.zig");

pub const Matcher = struct {
    pub const Slice = struct { off: usize, len: usize };
    pub fn run_dot(allocator: Allocator, history: History, slice: Slice, dot: par.Dot) !void {
        _ = allocator;
        _ = history;
        _ = dot;
        _ = slice;
    }
    pub fn run_star(allocator: Allocator, history: History, slice: Slice, star: par.Star) !void {
        switch (history.program.tokens[star.starword].identity.starword) {
            lx.StarWordId.Captures => {
                try dispatch_captures(allocator, history, slice, star);
            },
            else => {},
        }
    }

    fn dispatch_captures(allocator: Allocator, history: History, slice: Slice, star: par.Star) !void {
        _ = allocator;
        _ = history;
        _ = slice;
        _ = star;
    }
};
