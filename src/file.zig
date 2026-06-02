const std = @import("std");
const types = @import("chess/types.zig");

const PuzzleMeta = packed struct(u1096) {
    id: u40,
    move: u16,
    solution: u1024,
    size: u16,

    fn parse(s_id: []const u8, s_moves: []const u8) PuzzleMeta {
        const id = std.mem.readInt(u40, s_id[0..5], .native);

        var solution: u1024 = undefined;
        var size: u16 = 0;
        var move: u16 = 0;
        var parts = std.mem.splitScalar(u8, s_moves, ' ');
        while (parts.next()) |part| {
            const res: u16 = @bitCast(types.Uci.parse(part));
            if (move == 0) {
                move = res;
            } else {
                var array: *[64]u16 = @ptrCast(&solution);
                array[size] = res;
                size += 1;
            }
        }

        return PuzzleMeta{ .id = id, .move = move, .solution = solution, .size = size };
    }
};

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

            const meta = PuzzleMeta.parse(id, moves);

            var position = types.Fen.parse(fen);

            _ = position.make_move(@bitCast(meta.move));

            try writer.add(position, meta);
        }

        try writer.close(io);
    }
};

test "af" {
    try BuildDb.read_csv_to_build_db_if_doesnt_exists(std.testing.io, "data/athousand_sorted.csv", "data/athousand.pos.db", "data/athousand.meta.db");
}
