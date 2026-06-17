const std = @import("std");
const types = @import("dot/chess/types.zig");
const san = @import("dot/chess/san.zig");

const SizeOfPuzzleMeta = 1096 / 8;
const PuzzleMeta = packed struct(u1096) {
    id: u40,
    move: u16,
    solution: u1024,
    size: u16,

    fn parse(position: types.Position, s_id: []const u8, s_moves: []const u8) PuzzleMeta {
        const id = std.mem.readInt(u40, s_id[0..5], .native);

        var solution: u1024 = undefined;
        var size: u16 = 0;
        var firstMove: u16 = 0;
        var parts = std.mem.splitScalar(u8, s_moves, ' ');
        var position2 = position;
        while (parts.next()) |part| {
            const move = san.Uci.move(part).toMove(position2);
            const res: u16 = @bitCast(move);
            _ = position2.make_move(move);
            position2.flipTurn();
            if (firstMove == 0) {
                firstMove = res;
            } else {
                var words: *[64]u16 = @ptrCast(&solution);
                words[size] = res;
                size += 1;
            }
        }

        return PuzzleMeta{ .id = id, .move = firstMove, .solution = solution, .size = size };
    }

    pub fn moves(self: PuzzleMeta) [64]types.Move {
        return @bitCast(self.solution);
    }
};

test "basic usage" {
    const ally = std.testing.allocator;
    const position = types.Fen.parse(types.Fen.Initial);
    var meta = PuzzleMeta.parse(position, "abcdef", "e2e4 e7e5 b1c3");

    //try std.testing.expectEqual(2, meta.moves().len);
    const res = try types.Prints.moveFromTo(ally, meta.moves()[0]);
    defer ally.free(res);
    try std.testing.expectEqualStrings("e7e5", res);
    const res2 = try types.Prints.moveFromTo(ally, meta.moves()[1]);
    defer ally.free(res2);
    try std.testing.expectEqualStrings("b1c3", res2);
}

const DbHeader = packed struct(u128) { magic: u32 = 0x5a7a70, version: u32 = 1, count: u64 };

const DbWriter = struct {
    meta_file: std.Io.File,
    file: std.Io.File,
    buffer: [4096]u8,
    buffer2: [4096]u8,
    writer: std.Io.File.Writer,
    writer2: std.Io.File.Writer,
    header: DbHeader,

    fn open(self: *DbWriter, io: std.Io, path: []const u8, meta_path: []const u8) !void {
        self.header = .{ .count = 0 };
        self.file = try std.Io.Dir.cwd()
            .createFile(io, path, .{});

        self.writer = self.file.writer(io, &self.buffer);

        self.meta_file = try std.Io.Dir.cwd()
            .createFile(io, meta_path, .{});
        self.writer2 = self.meta_file.writer(io, &self.buffer2);

        try self.writer2.interface.writeStruct(self.header, .native);
    }

    fn add(self: *DbWriter, position: types.Position, meta: PuzzleMeta) !void {
        try self.writer.interface.writeStruct(position, .native);
        try self.writer2.interface.writeStruct(meta, .native);
        self.header.count += 1;
    }

    fn close(self: *DbWriter, io: std.Io) !void {
        try self.writer2.seekTo(0);
        try self.writer2.interface.writeStruct(self.header, .native);
        try self.writer2.flush();
        try self.writer.flush();
        self.file.close(io);
        self.meta_file.close(io);
    }
};

pub const BuildDb = struct {
    pub fn read_csv_to_build_db_if_doesnt_exists(io: std.Io, csv_file: []const u8, db_file: []const u8, meta_file: []const u8) !void {
        std.Io.Dir.cwd().access(io, meta_file, .{}) catch |err| {
            if (err == error.FileNotFound) {
                var stdout = std.Io.File.stdout().writer(io, &.{});
                try stdout.interface.print("Building, Positions Db.\n", .{});
                try read_csv_to_build_db(io, csv_file, db_file, meta_file);
            }
        };
    }

    fn read_csv_to_build_db(io: std.Io, csv_file: []const u8, db_file: []const u8, meta_file: []const u8) !void {
        var writer: DbWriter = undefined;

        try writer.open(io, db_file, meta_file);

        var buffer: [500]u8 = undefined;

        const file = try std.Io.Dir.cwd()
            .openFile(io, csv_file, .{ .mode = .read_only });

        defer file.close(io);
        var reader = file.reader(io, &buffer);

        var i_reader = &reader.interface;

        while (try i_reader.takeDelimiter('\n')) |line| {
            var parts = std.mem.splitScalar(u8, line, ',');

            const id = parts.next().?;
            const fen = parts.next().?;
            const moves = parts.next().?;

            var position = types.Fen.parse(fen);

            const meta = PuzzleMeta.parse(position, id, moves);

            _ = position.make_move(@bitCast(meta.move));
            position.flipTurn();

            try writer.add(position, meta);
        }

        try writer.close(io);
    }
};

test "af" {
    try BuildDb.read_csv_to_build_db_if_doesnt_exists(std.testing.io, "data/athousand_sorted.csv", "data/athousand.pos.db", "data/athousand.meta.db");
}

pub const DbReader = struct {
    meta_file: std.Io.File,
    file: std.Io.File,
    buffer: [4096]u8,
    buffer2: [4096]u8,
    reader: std.Io.File.Reader,
    reader2: std.Io.File.Reader,
    header: DbHeader,

    pub fn open(io: std.Io, path: []const u8, meta_path: []const u8) !DbReader {
        var self: DbReader = undefined;
        self.file = try std.Io.Dir.cwd()
            .openFile(io, path, .{});

        self.reader = self.file.reader(io, &self.buffer);

        self.meta_file = try std.Io.Dir.cwd()
            .openFile(io, meta_path, .{});
        self.reader2 = self.meta_file.reader(io, &self.buffer2);

        var buffer: [@sizeOf(DbHeader)]u8 = undefined;
        try self.reader2.interface.readSliceAll(&buffer);

        self.header = @bitCast(buffer);

        return self;
    }

    pub fn readPosition(self: *DbReader, off: usize) !types.Position {
        var buffer: [@sizeOf(types.Position)]u8 = undefined;
        try self.reader.seekTo(off * @sizeOf(types.Position));
        try self.reader.interface.readSliceAll(&buffer);
        return @bitCast(buffer);
    }
    pub fn readMeta(self: *DbReader, off: usize) !PuzzleMeta {
        var buffer: [SizeOfPuzzleMeta]u8 = undefined;
        try self.reader2.seekTo(@sizeOf(DbHeader) + off * SizeOfPuzzleMeta);
        try self.reader2.interface.readSliceAll(&buffer);
        return @bitCast(buffer);
    }

    fn close(self: *DbWriter, io: std.Io) !void {
        self.file.close(io);
        self.meta_file.close(io);
    }
};

test "db writer db reader" {
    const ally = std.testing.allocator;
    var writer: DbWriter = undefined;
    try writer.open(std.testing.io, "data/test.pos.db", "data/test.meta.db");

    var meta = PuzzleMeta.parse(types.Fen.parse(types.Fen.Initial), "abcdef", "e2e4 e7e5 b1c3");
    try writer.add(types.Fen.parse(types.Fen.Initial), meta);

    try writer.close(std.testing.io);

    var reader = try DbReader.open(std.testing.io, "data/test.pos.db", "data/test.meta.db");

    try std.testing.expectEqual(1, reader.header.count);

    var meta2 = try reader.readMeta(0);

    const position = types.Fen.parse(types.Fen.Initial);
    const move1: types.Move = @bitCast(meta.move);
    try std.testing.expectEqual(san.Uci.move("e2e4").toMove(position), move1);
    try std.testing.expectEqual(2, meta.size);
    const res = try types.Prints.moveFromTo(ally, meta.moves()[0]);
    defer ally.free(res);
    try std.testing.expectEqualStrings("e7e5", res);
    try std.testing.expectEqual(san.Uci.move("e7e5").toMove(position), meta.moves()[0]);

    const move: types.Move = @bitCast(meta2.move);
    try std.testing.expectEqual(san.Uci.move("e2e4").toMove(position), move);
    try std.testing.expectEqual(2, meta2.size);
    try std.testing.expectEqual(san.Uci.move("e7e5").toMove(position), meta2.moves()[0]);
    try std.testing.expectEqual(san.Uci.move("b1c3").toMove(position), meta2.moves()[1]);
}

test "moves not working 2" {
    const ally = std.testing.allocator;

    var reader = try DbReader.open(std.testing.io, "data/athousand.pos.db", "data/athousand.meta.db");

    try std.testing.expectEqual(1000, reader.header.count);

    const position = try reader.readPosition(39);
    var meta = try reader.readMeta(39);

    const res = try types.Prints.moveFromTo(ally, meta.moves()[0]);
    defer ally.free(res);
    try std.testing.expectEqualStrings("c5d6", res);

    const res2 = try types.Prints.moveFromTo(ally, meta.moves()[1]);
    defer ally.free(res2);
    try std.testing.expectEqualStrings("f3f4", res2);

    var builder = try san.PrintBuilder.init(ally);
    defer builder.deinit(ally);
    builder.resetPosition(position);

    for (meta.moves()[0..meta.size]) |move| {
        try builder.appendMove(ally, move);
    }
}
