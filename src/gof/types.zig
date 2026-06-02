const std = @import("std");

const Def = struct {};

pub const ParseErrorMsg = struct {
    line: usize,
    column: usize,
    message: []const u8,
};

pub const Diagnostics = struct {
    errors: std.ArrayList(ParseErrorMsg),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) !Diagnostics {
        return .{
            .errors = try std.ArrayList(ParseErrorMsg).initCapacity(allocator, 100),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Diagnostics) void {
        for (self.errors.items) |err| {
            self.allocator.free(err.message);
        }
        self.errors.deinit();
    }

    pub fn addError(self: *Diagnostics, line: usize, col: usize, msg: []const u8) !void {
        const owned_msg = try self.allocator.dupe(u8, msg);

        try self.allocator.append(.{ .line = line, .column = col, .message = owned_msg });
    }

    pub fn printAll(self: Diagnostics) void {
        for (self.errors.items) |err| {
            std.debug.print("Parser Error [{d}:{d}]: {s}\n", .{ err.line, err.column, err.message });
        }
    }
};

const Parser = struct {
    allocator: std.mem.Allocator,
    diags: *Diagnostics,

    pub fn init(allocator: std.mem.Allocator, diags: *Diagnostics) Parser {
        return .{
            .allocator = allocator,
            .diags = diags,
        };
    }

    fn parse(self: *Parser, script: []const u8) !void {
        _ = self;
        _ = script;
    }
};

pub const Usage = struct {
    pub fn usage(script: []const u8, gpa_allocator: std.mem.Allocator) !void {
        var arena = std.heap.ArenaAllocator.init(gpa_allocator);
        const arena_allocator = arena.allocator();

        var diags = try Diagnostics.init(arena_allocator);

        var parser = Parser.init(arena_allocator, &diags);

        const ast = try parser.parse(script);

        if (diags.errors.items.len > 0) {
            std.debug.print("Parsing failed with {d} errors:\n", .{diags.errors.items.len});
            diags.printAll();
            return;
        }

        _ = ast;
    }
};
